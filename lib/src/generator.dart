import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:me_doc/src/code_analyzer.dart';
import 'package:me_doc/src/ai_service.dart';
import 'package:me_doc/src/git_service.dart';

class DocumentGenerator {
  final String projectPath;
  final String outputPath;
  final String modelName;
  final double temperature;
  final int contextLength;
  final bool verbose;

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
  }) {
    _codeAnalyzer = CodeAnalyzer(projectPath);
    _gitService = GitService(projectPath);
  }

  Future<void> generateDocumentation() async {
    print('Starting documentation generation for $projectPath');

    try {
      // Initialize the AI service with Ollama
      _aiService = await AIService.create(
        modelName: modelName,
        temperature: temperature,
        contextLength: contextLength,
        verbose: verbose,
      );

      // Create output directory if it doesn't exist
      final outputDir = Directory(outputPath);
      if (!outputDir.existsSync()) {
        outputDir.createSync(recursive: true);
      }

      // Step 1: Analyze code structure
      print('Analyzing code structure...');
      final codeStructure = await _codeAnalyzer.analyzeProject();

      // Step 2: Get Git history and changes
      print('Retrieving project history...');
      final gitHistory = await _gitService.getProjectHistory();

      // Step 3: Generate documentation with AI
      print('Generating code documentation...');
      final codeDocumentation =
          await _aiService.generateCodeDocumentation(codeStructure);

      // Step 4: Generate changelog
      print('Generating changelog...');
      final changelog = await _aiService.generateChangelog(gitHistory);

      // Step 5: Generate project summary
      print('Generating project summary...');
      final projectSummary =
          await _aiService.generateProjectSummary(codeStructure, gitHistory);

      // Step 6: Write documentation to files
      await _writeDocumentation(codeDocumentation, changelog, projectSummary);

      print('Documentation successfully generated at $outputPath');
    } catch (e) {
      print('Error generating documentation: $e');
      rethrow;
    } finally {
      // Ensure we clean up resources
      if (_aiService != null) {
        await _aiService.dispose();
      }
    }
  }

  Future<void> _writeDocumentation(
    Map<String, String> codeDocumentation,
    String changelog,
    String projectSummary,
  ) async {
    // Write code documentation
    for (final entry in codeDocumentation.entries) {
      final filePath = path.join(outputPath, 'code', '${entry.key}.md');
      final fileDir = Directory(path.dirname(filePath));
      if (!fileDir.existsSync()) {
        fileDir.createSync(recursive: true);
      }
      await File(filePath).writeAsString(entry.value);
    }

    // Write changelog
    await File(path.join(outputPath, 'CHANGELOG.md')).writeAsString(changelog);

    // Write project summary
    await File(path.join(outputPath, 'README.md'))
        .writeAsString(projectSummary);
  }
}
