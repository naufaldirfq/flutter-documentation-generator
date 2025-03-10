import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:me_doc/src/code_analyzer.dart';
import 'package:me_doc/src/ai_service.dart';
import 'package:me_doc/src/git_service.dart';
import 'package:intl/intl.dart';

class DocumentGenerator {
  final String projectPath;
  final String outputPath;
  final String modelName;
  final double temperature;
  final int contextLength;
  final bool verbose;
  final int maxFilesPerBatch;
  final int delayBetweenBatches;
  final List<String> excludePaths;
  final int maxFilesToProcess;
  final bool overviewOnly;
  final int maxTags; // Add this field

  late final CodeAnalyzer _codeAnalyzer;
  late AIService _aiService;
  late final GitService _gitService;

  DocumentGenerator({
    required this.projectPath,
    required this.outputPath,
    this.modelName = 'deepseek-coder',
    this.temperature = 0.1,
    this.contextLength = 4096,
    this.verbose = true,
    this.maxFilesPerBatch = 10,
    this.delayBetweenBatches = 2000,
    this.excludePaths = const [],
    this.maxFilesToProcess = 0, // 0 means process all
    this.overviewOnly = false,
    this.maxTags = 10, // Default to 10 tags
  }) {
    _codeAnalyzer = CodeAnalyzer(projectPath, excludePaths: excludePaths);
    _gitService = GitService(projectPath);
  }

  Future<void> generateDocumentation() async {
    final startTime = DateTime.now();
    print(
        'Starting documentation generation for $projectPath at ${_formatDateTime(startTime)}');

    if (overviewOnly) {
      print(
          'Overview-only mode enabled: Will generate only project-level documentation');
    }

    try {
      // Initialize the AI service with Ollama
      _aiService = await AIService.create(
        projectPath: projectPath, // Pass projectPath to AIService
        modelName: modelName,
        temperature: temperature,
        contextLength: contextLength,
        verbose: verbose,
        maxFilesPerBatch: maxFilesPerBatch,
        delayBetweenBatches: delayBetweenBatches,
      );

      // Create output directory if it doesn't exist
      final outputDir = Directory(outputPath);
      if (!outputDir.existsSync()) {
        outputDir.createSync(recursive: true);
      }

      // Create code directory structure in advance
      final codeDir = Directory(path.join(outputPath, 'code'));
      if (!codeDir.existsSync()) {
        codeDir.createSync(recursive: true);
      }

      // Write generation info log
      final infoLog = {
        'startTime': _formatDateTime(startTime),
        'projectPath': projectPath,
        'modelName': modelName,
        'temperature': temperature,
        'maxFilesPerBatch': maxFilesPerBatch,
        'maxFilesToProcess': maxFilesToProcess > 0 ? maxFilesToProcess : 'all',
        'excludePaths': excludePaths,
        'overviewOnly': overviewOnly,
      };
      await File(path.join(outputPath, 'generation_info.json'))
          .writeAsString(JsonEncoder.withIndent('  ').convert(infoLog));

      // Step 1: Analyze code structure
      print('Analyzing code structure...');
      var codeStructure = await _codeAnalyzer.analyzeProject();

      // Apply file limit if specified
      if (maxFilesToProcess > 0 &&
          codeStructure.files.length > maxFilesToProcess) {
        print(
            'Limiting analysis to $maxFilesToProcess files out of ${codeStructure.files.length}');

        // Keep only the specified number of files
        final limitedFiles = <String, FileAnalysis>{};
        int count = 0;
        for (var entry in codeStructure.files.entries) {
          if (count < maxFilesToProcess) {
            limitedFiles[entry.key] = entry.value;
            count++;
          } else {
            break;
          }
        }

        // Create a new structure with limited files
        codeStructure = ProjectStructure(
          metadata: codeStructure.metadata,
          files: limitedFiles,
          widgets: codeStructure.widgets,
          services: codeStructure.services,
          models: codeStructure.models,
        );
      }

      // Step 2: Get Git history and changes
      print('Retrieving project history...');
      final gitHistory = await _gitService.getProjectHistory();

      // Create progress log file
      final progressLogFile = File(path.join(outputPath, 'progress.log'));
      if (progressLogFile.existsSync()) {
        progressLogFile.deleteSync();
      }
      progressLogFile.createSync();

      // Step 3: Generate project overview documentation
      print('Generating project overview...');
      final overview = await _aiService.generateProjectOverview(codeStructure);

      // Ensure code directory exists before writing the overview file
      final overviewFilePath = path.join(outputPath, 'code', 'overview.md');
      final overviewDir = Directory(path.dirname(overviewFilePath));
      if (!overviewDir.existsSync()) {
        overviewDir.createSync(recursive: true);
      }

      await File(overviewFilePath).writeAsString(overview);

      Map<String, String> codeDocumentation = {'overview': overview};

      // Generate individual file documentation only if not in overview-only mode
      if (!overviewOnly) {
        // Step 4: Generate documentation with AI for individual files
        print('Generating documentation for individual files...');
        codeDocumentation = await _aiService.generateCodeDocumentation(
          codeStructure,
          progressCallback: (current, total, filePath) {
            final percentage = (current / total * 100).toStringAsFixed(1);
            final progressLine =
                '[$percentage%] File $current/$total: $filePath';
            progressLogFile.writeAsStringSync('$progressLine\n',
                mode: FileMode.append);
          },
        );

        // Write files as they are generated
        await _writeCodeDocumentation(codeDocumentation);
      } else {
        print(
            'Skipping individual file documentation generation (overview-only mode)');
      }

      // Step 5: Generate changelog
      print('Generating changelog...');
      final changelog =
          await _aiService.generateChangelog(gitHistory, maxTags: maxTags);
      await File(path.join(outputPath, 'CHANGELOG.md'))
          .writeAsString(changelog);

      // Step 6: Generate project summary
      print('Generating project summary...');
      final projectSummary =
          await _aiService.generateProjectSummary(codeStructure, gitHistory);
      await File(path.join(outputPath, 'README.md'))
          .writeAsString(projectSummary);

      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);
      print('Documentation successfully generated at $outputPath');
      print('Total time: ${_formatDuration(duration)}');

      // Update info log with completion time
      infoLog['endTime'] = _formatDateTime(endTime);
      infoLog['duration'] = _formatDuration(duration);
      infoLog['filesProcessed'] = codeStructure.files.length;
      infoLog['filesDocumented'] =
          overviewOnly ? 0 : codeStructure.files.length;
      await File(path.join(outputPath, 'generation_info.json'))
          .writeAsString(JsonEncoder.withIndent('  ').convert(infoLog));
    } catch (e) {
      print('Error generating documentation: $e');
      rethrow;
    } finally {
      // Ensure we clean up resources
      await _aiService.dispose();
    }
  }

  Future<void> _writeCodeDocumentation(
      Map<String, String> codeDocumentation) async {
    // Write code documentation
    for (final entry in codeDocumentation.entries) {
      final filePath = path.join(outputPath, 'code', '${entry.key}.md');
      final fileDir = Directory(path.dirname(filePath));
      if (!fileDir.existsSync()) {
        fileDir.createSync(recursive: true);
      }
      await File(filePath).writeAsString(entry.value);
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(dateTime);
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    return '${hours}h ${minutes}m ${seconds}s';
  }
}
