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
  final GitService _gitService;

  AIService({
    required DeepSeekProvider provider,
    required GitService gitService,
    int maxFilesPerBatch = 10,
    int delayBetweenBatches = 2000,
  })  : _provider = provider,
        _gitService = gitService,
        _maxFilesPerBatch = maxFilesPerBatch,
        _delayBetweenBatches = delayBetweenBatches;

  /// Creates an AI service with the DeepSeek provider via Ollama
  static Future<AIService> create({
    required String projectPath,
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

    final gitService = GitService(projectPath);

    return AIService(
      provider: provider,
      gitService: gitService,
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
  Future<String> generateChangelog(GitHistory history,
      {int maxTags = 10}) async {
    print('Generating changelog...');

    // Check if the project has tags for versioning
    if (history.tags.isNotEmpty) {
      return _generateTagBasedChangelog(history, maxTags: maxTags);
    } else {
      return _generateUntaggedChangelog(history);
    }
  }

  /// Generates a changelog based on tags in Git history
  Future<String> _generateTagBasedChangelog(GitHistory history,
      {int maxTags = 10}) async {
    print(
        'Generating tag-based changelog with ${history.tags.length} tags (limiting to $maxTags)...');

    // Sort tags by semantic versioning or date to ensure proper ordering
    final sortedTags = List<String>.from(history.tags);
    sortedTags.sort((a, b) {
      // Try to extract version numbers for comparison
      final regex = RegExp(r'v?(\d+)\.(\d+)\.(\d+)');
      final matchA = regex.firstMatch(a);
      final matchB = regex.firstMatch(b);

      if (matchA != null && matchB != null) {
        // Compare major version
        final majorA = int.parse(matchA.group(1)!);
        final majorB = int.parse(matchB.group(1)!);
        if (majorA != majorB) return majorB - majorA;

        // Compare minor version
        final minorA = int.parse(matchA.group(2)!);
        final minorB = int.parse(matchB.group(2)!);
        if (minorA != minorB) return minorB - minorA;

        // Compare patch version
        final patchA = int.parse(matchA.group(3)!);
        final patchB = int.parse(matchB.group(3)!);
        return patchB - patchA;
      }

      // Fall back to string comparison if not semver
      return b.compareTo(a);
    });

    // Limit to the specified number of tags (most recent first)
    if (sortedTags.length > maxTags) {
      print(
          'Limiting changelog to the $maxTags most recent tags out of ${sortedTags.length}');
      sortedTags.removeRange(maxTags, sortedTags.length);
    }

    // Create the changelog header that sets expectations
    final changelog = StringBuffer('''
# Changelog

This document contains all notable changes to this project organized by version tags.

''');

    // Process unreleased commits first (newer than the newest tag)
    final unreleased = await _gitService.getUnreleasedCommits();
    if (unreleased.isNotEmpty) {
      print('Processing unreleased changes (${unreleased.length} commits)');
      changelog.writeln('## [Unreleased]');
      changelog.writeln();

      // Group commits by type
      final features = <String>[];
      final bugfixes = <String>[];
      final improvements = <String>[];

      for (final commit in unreleased.take(15)) {
        final message = commit.shortMessage;
        final hash = commit.hash.substring(0, 7);

        if (_isFeatureCommit(commit.message)) {
          features.add('- $message (#$hash)');
        } else if (_isBugfixCommit(commit.message)) {
          bugfixes.add('- $message (#$hash)');
        } else {
          improvements.add('- $message (#$hash)');
        }
      }

      // Write grouped commits
      if (features.isNotEmpty) {
        changelog.writeln('### Features');
        features.forEach(changelog.writeln);
        changelog.writeln();
      }

      if (bugfixes.isNotEmpty) {
        changelog.writeln('### Bug Fixes');
        bugfixes.forEach(changelog.writeln);
        changelog.writeln();
      }

      if (improvements.isNotEmpty) {
        changelog.writeln('### Improvements');
        improvements.forEach(changelog.writeln);
        changelog.writeln();
      }

      changelog.writeln();
    }

    // Process each tag
    String? previousTag;
    for (int i = 0; i < sortedTags.length; i++) {
      final tag = sortedTags[i];
      print('Processing tag ${i + 1}/${sortedTags.length}: $tag');

      final tagDate = history.tagDate[tag];
      final formattedDate = _formatDateString(tagDate ?? '');

      // Start tag section
      changelog.writeln('## [$tag] - $formattedDate');
      changelog.writeln();

      // Get commits for this tag
      final tagCommits =
          await _gitService.getCommitsForTag(tag, previousTag: previousTag);
      previousTag = tag;

      if (tagCommits.isEmpty) {
        changelog.writeln('*No changes recorded for this tag.*');
        changelog.writeln();
        continue;
      }

      // Group commits by type
      final features = <String>[];
      final bugfixes = <String>[];
      final improvements = <String>[];

      for (final commit in tagCommits.take(20)) {
        final message = commit.shortMessage;
        final hash = commit.hash.substring(0, 7);

        if (_isFeatureCommit(commit.message)) {
          features.add('- $message (#$hash)');
        } else if (_isBugfixCommit(commit.message)) {
          bugfixes.add('- $message (#$hash)');
        } else {
          improvements.add('- $message (#$hash)');
        }
      }

      // Write grouped commits
      if (features.isNotEmpty) {
        changelog.writeln('### Features');
        features.forEach(changelog.writeln);
        changelog.writeln();
      }

      if (bugfixes.isNotEmpty) {
        changelog.writeln('### Bug Fixes');
        bugfixes.forEach(changelog.writeln);
        changelog.writeln();
      }

      if (improvements.isNotEmpty) {
        changelog.writeln('### Improvements');
        improvements.forEach(changelog.writeln);
        changelog.writeln();
      }
    }

    return changelog.toString();
  }

  /// Format date string from Git to a more readable format
  String _formatDateString(String gitDate) {
    try {
      // Git date format example: 2023-04-15 14:30:45 +0200
      final parts = gitDate.split(' ');
      if (parts.length >= 2) {
        return parts[0]; // Just return the date part YYYY-MM-DD
      }
      return gitDate;
    } catch (e) {
      return gitDate;
    }
  }

  /// Determine if a commit message indicates a feature
  bool _isFeatureCommit(String message) {
    message = message.toLowerCase();
    return message.contains('add') ||
        message.contains('feature') ||
        message.contains('implement') ||
        message.contains('support') ||
        message.contains('create');
  }

  /// Determine if a commit message indicates a bugfix
  bool _isBugfixCommit(String message) {
    message = message.toLowerCase();
    return message.contains('fix') ||
        message.contains('bug') ||
        message.contains('issue') ||
        message.contains('error') ||
        message.contains('crash') ||
        message.contains('resolve');
  }

  /// Generates a changelog for projects without version tags
  Future<String> _generateUntaggedChangelog(GitHistory history) async {
    print('Generating chronological changelog with no tags...');

    // Group commits by month for better organization
    final commitsByMonth = <String, List<GitCommit>>{};

    for (final commit in history.commits.take(100)) {
      // Limit to 100 commits
      final date = DateTime.parse(commit.date.split(' ')[0]);
      final monthKey = '${date.year}-${date.month.toString().padLeft(2, '0')}';

      if (!commitsByMonth.containsKey(monthKey)) {
        commitsByMonth[monthKey] = [];
      }
      commitsByMonth[monthKey]!.add(commit);
    }

    // Sort months in descending order
    final sortedMonths = commitsByMonth.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    // Process months in smaller chunks to avoid hitting context limits
    const int maxMonthsPerRequest = 2;
    final List<String> changelogParts = [];

    for (int i = 0; i < sortedMonths.length; i += maxMonthsPerRequest) {
      final end = (i + maxMonthsPerRequest < sortedMonths.length)
          ? i + maxMonthsPerRequest
          : sortedMonths.length;

      final monthBatch = sortedMonths.sublist(i, end);
      print(
          'Processing month batch ${i ~/ maxMonthsPerRequest + 1}/${(sortedMonths.length / maxMonthsPerRequest).ceil()} (${monthBatch.join(", ")})');

      final prompt = '''
      You are a technical documentation expert tasked with creating a part of a changelog from Git commit history.

      # TASK
      Create a well-formatted changelog section for the following months based on their commits.

      # FORMAT
      For each month, create a section like:
      
      ## YYYY-MM
      
      ### Features
      - Feature description (#commit-hash)
      
      ### Bug Fixes
      - Bug fix description (#commit-hash)
      
      ### Improvements
      - Improvement description (#commit-hash)

      # COMMIT DATA BY MONTH
      ${monthBatch.map((month) => '''
      ## $month
      ${commitsByMonth[month]!.take(15).map((c) => "- ${c.hash.substring(0, 7)}: ${_cleanCommitMessage(c.message)}").join('\n')}
      ''').join('\n\n')}

      # INSTRUCTIONS
      1. Remove Jira/ticket references (e.g., "ABC-123: ")
      2. Group similar commits together
      3. Only include meaningful changes (ignore trivial commits)
      4. Keep it concise but informative
      5. Use proper Markdown formatting
      ''';

      final batchChangelog = await _provider.generateResponse(prompt);
      changelogParts.add(batchChangelog);

      // Add a separator between batches
      if (i < sortedMonths.length - maxMonthsPerRequest) {
        changelogParts.add("\n\n");
      }
    }

    // Combine all parts into the final changelog
    final fullChangelog = '''
    # Changelog

    All notable changes to this project will be documented in this file.

    ${changelogParts.join('')}
    ''';

    return fullChangelog;
  }

  /// Clean commit message by removing ticket numbers and standardizing format
  String _cleanCommitMessage(String message) {
    // Remove ticket numbers (like PROJECT-123:)
    message = message.replaceAll(RegExp(r'^\s*\[?[A-Z]+-\d+\]?:?\s*'), '');

    // Remove merge commit prefixes
    message =
        message.replaceAll(RegExp(r'^Merge (branch|pull request) .*: '), '');

    // Remove multiple spaces
    message = message.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Capitalize first letter if needed
    if (message.isNotEmpty) {
      final firstChar = message[0];
      if (firstChar.toLowerCase() == firstChar) {
        message = firstChar.toUpperCase() + message.substring(1);
      }
    }

    return message;
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
