import 'dart:convert';
import 'dart:io';
import 'package:me_doc/src/code_analyzer.dart';
import 'package:me_doc/src/ai/deepseek_provider.dart';
import 'package:me_doc/src/git_service.dart';

/// Service for interacting with AI to generate documentation
class AIService {
  final DeepSeekProvider _provider;
  final int _maxFilesPerBatch;
  final int _delayBetweenBatches;

  AIService({
    required DeepSeekProvider provider,
    int maxFilesPerBatch = 10,
    int delayBetweenBatches = 2000,
  })  : _provider = provider,
        _maxFilesPerBatch = maxFilesPerBatch,
        _delayBetweenBatches = delayBetweenBatches;

  /// Creates an AI service with the DeepSeek provider via Ollama
  static Future<AIService> create({
    String modelName = 'deepseek-coder',
    double temperature = 0.1,
    int contextLength = 4096,
    bool verbose = true,
    int maxFilesPerBatch = 10,
    int delayBetweenBatches = 2000,
  }) async {
    final provider = DeepSeekProvider(
      modelName: modelName,
      temperature: temperature,
      contextLength: contextLength,
      verbose: verbose,
    );

    final isInitialized = await provider.initialize();
    if (!isInitialized) {
      throw Exception(
          'Failed to initialize Ollama with model $modelName. Make sure Ollama is running and the model is installed.');
    }

    return AIService(
      provider: provider,
      maxFilesPerBatch: maxFilesPerBatch,
      delayBetweenBatches: delayBetweenBatches,
    );
  }

  /// Disposes of the AI service resources
  Future<void> dispose() async {
    await _provider.dispose();
  }

  /// Generate overview documentation for the entire project (exposed publicly)
  Future<String> generateProjectOverview(ProjectStructure structure) async {
    return await _generateProjectOverview(structure);
  }

  /// Generates documentation for code files
  Future<Map<String, String>> generateCodeDocumentation(
      ProjectStructure structure,
      {Function(int, int, String)? progressCallback}) async {
    final result = <String, String>{};

    // Generate project overview
    print('Generating project overview...');
    result['overview'] = await _generateProjectOverview(structure);

    // Filter files with classes and create batches
    final filesToProcess = structure.files.entries
        .where((entry) => entry.value.classes.isNotEmpty)
        .toList();

    final totalFiles = filesToProcess.length;
    print(
        'Processing $totalFiles files with classes in batches of $_maxFilesPerBatch');

    // Process files in batches
    for (int i = 0; i < filesToProcess.length; i += _maxFilesPerBatch) {
      final batchEnd = (i + _maxFilesPerBatch < filesToProcess.length)
          ? i + _maxFilesPerBatch
          : filesToProcess.length;

      final batch = filesToProcess.sublist(i, batchEnd);

      print(
          'Processing batch ${(i ~/ _maxFilesPerBatch) + 1}/${(totalFiles / _maxFilesPerBatch).ceil()}: ${batch.length} files');

      // Process each file in the batch
      for (int j = 0; j < batch.length; j++) {
        final fileEntry = batch[j];
        final filePath = fileEntry.key;
        final fileAnalysis = fileEntry.value;

        final fileIndex = i + j + 1;
        print(
            'Generating documentation for file $fileIndex/$totalFiles: ${fileAnalysis.relativePath}');

        if (progressCallback != null) {
          progressCallback(fileIndex, totalFiles, fileAnalysis.relativePath);
        }

        try {
          final fileContent = await _readFileContent(filePath);
          result[fileAnalysis.relativePath] = await _generateFileDocumentation(
            fileAnalysis,
            fileContent,
            structure.metadata.name,
          );
        } catch (e) {
          print('Error processing ${fileAnalysis.relativePath}: $e');
          result[fileAnalysis.relativePath] =
              'Error generating documentation: $e';
        }
      }

      // Wait between batches to let Ollama recover resources
      if (batchEnd < filesToProcess.length) {
        print('Waiting $_delayBetweenBatches ms before next batch...');
        await Future.delayed(Duration(milliseconds: _delayBetweenBatches));
      }
    }

    return result;
  }

  /// Generates a changelog based on Git history
  Future<String> generateChangelog(GitHistory history) async {
    print('Generating changelog...');

    // Limit the number of commits to analyze to avoid overwhelming the model
    final limitedCommits = history.commits.take(50).toList();
    final limitedHistory = GitHistory()
      ..authors = history.authors
      ..firstCommitDate = history.firstCommitDate
      ..lastCommitDate = history.lastCommitDate
      ..commits = limitedCommits
      ..tags = history.tags
      ..branches = history.branches;

    final prompt = '''
    Create a detailed changelog based on the following Git commit history.
    Format the changelog in Markdown with the following sections:
    - Features: New functionality
    - Bug fixes: Issues that were resolved
    - Improvements: Enhancements to existing features
    - Breaking changes: Changes that might break existing functionality
    
    For each item, include a brief description and the relevant commit hash.
    
    The Git history is provided in the following format:
    ${jsonEncode(limitedHistory.toJson())}
    ''';

    return await _provider.generateResponse(prompt);
  }

  /// Generates a project summary
  Future<String> generateProjectSummary(
      ProjectStructure structure, GitHistory history) async {
    print('Generating project summary...');

    final prompt = '''
    Create a comprehensive project summary for this Flutter project with the following structure and metadata:
    
    Project metadata:
    ${jsonEncode(structure.metadata.toJson())}
    
    The summary should include:
    1. Project Overview: High-level description and purpose
    2. Architecture: Description of the project's architecture pattern
    3. Key Components: List of important widgets, services, and models
    4. Dependencies: Notable external packages used and their purpose
    5. Getting Started: Instructions to run and use the project
    
    Format the summary in Markdown with proper headings, lists, and code blocks where appropriate.
    
    Additional context from Git history:
    ${jsonEncode({
          'authors': history.authors,
          'firstCommitDate': history.firstCommitDate,
          'lastCommitDate': history.lastCommitDate,
          'totalCommits': history.commits.length,
        })}
    ''';

    return await _provider.generateResponse(prompt);
  }

  /// Generate overview documentation for the entire project
  Future<String> _generateProjectOverview(ProjectStructure structure) async {
    final prompt = '''
    Create a comprehensive overview documentation for the following Flutter project:
    
    Project name: ${structure.metadata.name}
    Description: ${structure.metadata.description}
    Version: ${structure.metadata.version}
    
    Key statistics:
    - ${structure.files.length} Dart files
    - ${structure.widgets.length} Widget classes 
    - ${structure.services.length} Service classes
    - ${structure.models.length} Model classes
    
    Dependencies:
    ${structure.metadata.dependencies.entries.map((e) => "- ${e.key}: ${e.value}").join("\n")}
    
    Create a well-structured Markdown document that explains:
    1. Project purpose and overview
    2. System architecture and design patterns used
    3. Module organization
    4. Key components and their responsibilities
    5. How the components interact
    
    Focus on providing a clear high-level understanding of the project's structure and design philosophy.
    ''';

    return await _provider.generateResponse(prompt);
  }

  /// Generate documentation for a specific file
  Future<String> _generateFileDocumentation(
    FileAnalysis fileAnalysis,
    String fileContent,
    String projectName,
  ) async {
    // Truncate file content if it's too long to avoid exceeding context limits
    if (fileContent.length > 10000) {
      fileContent = fileContent.substring(0, 10000) +
          '\n... (content truncated for length)';
    }

    final prompt = '''
    Generate comprehensive documentation for the following Dart file:
    
    File path: ${fileAnalysis.relativePath}
    
    File analysis:
    ${jsonEncode(fileAnalysis.toJson())}
    
    File content:
    ```dart
    $fileContent
    ```
    
    Create a Markdown document that includes:
    1. File purpose and overview
    2. Detailed explanations of each class, its purpose, and usage
    3. Descriptions of important methods and parameters
    4. Usage examples where appropriate
    5. Notes about any complex or non-obvious patterns
    
    If this is a Widget class, explain its UI structure, parameters, and when to use it.
    If this is a Service class, explain its functionality and how it integrates with the rest of the app.
    If this is a Model class, explain its data structure and purpose.
    
    Format the documentation with proper Markdown headings, code blocks, tables, and lists.
    ''';

    return await _provider.generateResponse(prompt);
  }

  /// Read the content of a file
  Future<String> _readFileContent(String filePath) async {
    try {
      return await File(filePath).readAsString();
    } catch (e) {
      return "// Could not read file: $e";
    }
  }
}
