import 'dart:io';
import 'package:path/path.dart' as path;

/// Service for interacting with Git repositories
class GitService {
  final String repositoryPath;

  GitService(this.repositoryPath);

  /// Get the project's Git history
  Future<GitHistory> getProjectHistory() async {
    final history = GitHistory();

    try {
      // Check if this is a Git repository
      final gitDirExists =
          await Directory(path.join(repositoryPath, '.git')).exists();
      if (!gitDirExists) {
        print('Warning: No Git repository found at $repositoryPath');
        return history;
      }

      // Get all authors
      final authors = await _getAuthors();
      history.authors = authors;

      // Get all commits
      final commits = await _getCommits();
      history.commits = commits;

      // Get first and last commit dates
      if (commits.isNotEmpty) {
        history.firstCommitDate = commits.last.date;
        history.lastCommitDate = commits.first.date;
      }

      // Get branches
      final branches = await _getBranches();
      history.branches = branches;

      // Get tags and their commit information
      final tagsInfo = await _getTags();
      history.tags = tagsInfo['tags'] as List<String>;
      history.tagToCommit = tagsInfo['tagToCommit'] as Map<String, String>;
      history.tagDate = tagsInfo['tagDate'] as Map<String, String>;
    } catch (e) {
      print('Error getting Git history: $e');
    }

    return history;
  }

  /// Get all authors who contributed to the repository
  Future<List<String>> _getAuthors() async {
    final result =
        await _runGitCommand(['log', '--format=%an <%ae>', '--no-merges']);

    if (result.isEmpty) return [];

    final uniqueAuthors = <String>{};
    for (final line in result.split('\n')) {
      if (line.trim().isNotEmpty) {
        uniqueAuthors.add(line.trim());
      }
    }

    return uniqueAuthors.toList();
  }

  /// Get all commits in the repository (newest first)
  Future<List<GitCommit>> _getCommits() async {
    final result = await _runGitCommand([
      'log',
      '--pretty=format:%H|%an|%ad|%s|%b',
      '--date=iso',
      '--no-merges',
    ]);

    if (result.isEmpty) return [];

    final commits = <GitCommit>[];
    final lines = result.split('\n');

    for (final line in lines) {
      if (line.trim().isEmpty) continue;

      final parts = line.split('|');
      if (parts.length >= 4) {
        final hash = parts[0];
        final author = parts[1];
        final date = parts[2];
        final shortMessage = parts[3];
        // Join the rest as the full commit message
        final message =
            parts.length > 4 ? parts.sublist(4).join('|') : shortMessage;

        commits.add(GitCommit(
          hash: hash,
          author: author,
          date: date,
          shortMessage: shortMessage,
          message: message,
        ));
      }
    }

    return commits;
  }

  /// Get all branches in the repository
  Future<List<String>> _getBranches() async {
    final result = await _runGitCommand(['branch', '--list', '--no-color']);

    if (result.isEmpty) return [];

    final branches = <String>[];
    for (final line in result.split('\n')) {
      if (line.trim().isNotEmpty) {
        // Remove the leading '* ' or '  ' from branch names
        branches.add(line.trim().replaceFirst(RegExp(r'^\*?\s*'), ''));
      }
    }

    return branches;
  }

  /// Get all tags in the repository with their commit hashes and dates
  Future<Map<String, dynamic>> _getTags() async {
    final tags = <String>[];
    final tagToCommit = <String, String>{};
    final tagDate = <String, String>{};

    // Get list of tags
    final tagsResult = await _runGitCommand(['tag', '-l']);
    if (tagsResult.isNotEmpty) {
      tags.addAll(tagsResult.split('\n').where((t) => t.trim().isNotEmpty));
    }

    // Get tag -> commit mapping
    for (final tag in tags) {
      try {
        // Get commit hash for the tag
        final commitHash = await _runGitCommand(['rev-list', '-n', '1', tag]);
        if (commitHash.trim().isNotEmpty) {
          tagToCommit[tag] = commitHash.trim();

          // Get commit date for the tag
          final dateResult = await _runGitCommand(
              ['show', '-s', '--format=%ad', '--date=iso', commitHash.trim()]);
          if (dateResult.trim().isNotEmpty) {
            tagDate[tag] = dateResult.trim();
          }
        }
      } catch (e) {
        print('Error getting info for tag $tag: $e');
      }
    }

    return {
      'tags': tags,
      'tagToCommit': tagToCommit,
      'tagDate': tagDate,
    };
  }

  /// Run a Git command and return the output
  Future<String> _runGitCommand(List<String> arguments) async {
    try {
      final result = await Process.run(
        'git',
        arguments,
        workingDirectory: repositoryPath,
      );

      if (result.exitCode == 0) {
        return result.stdout.toString().trim();
      } else {
        print('Git command error: ${result.stderr}');
        return '';
      }
    } catch (e) {
      print('Error running Git command: $e');
      return '';
    }
  }

  /// Get commits associated with a specific tag
  Future<List<GitCommit>> getCommitsForTag(String tag,
      {String? previousTag}) async {
    try {
      // Get the commit hash for the tag
      final tagCommitHash = await _runGitCommand(['rev-list', '-n', '1', tag]);
      if (tagCommitHash.isEmpty) return [];

      // Determine the range to use
      String range;
      if (previousTag != null) {
        range = '$previousTag..$tag';
      } else {
        // If no previous tag, get all commits up to this tag
        range = tag;
      }

      // Get commits in the range
      final result = await _runGitCommand([
        'log',
        range,
        '--pretty=format:%H|%an|%ad|%s|%b',
        '--date=iso',
        '--no-merges',
      ]);

      if (result.isEmpty) return [];

      final commits = <GitCommit>[];
      final lines = result.split('\n');

      for (final line in lines) {
        if (line.trim().isEmpty) continue;

        final parts = line.split('|');
        if (parts.length >= 4) {
          final hash = parts[0];
          final author = parts[1];
          final date = parts[2];
          final shortMessage = parts[3];
          final message =
              parts.length > 4 ? parts.sublist(4).join('|') : shortMessage;

          final cleanedMessage = _cleanCommitMessage(message);
          final cleanedShortMessage = _cleanCommitMessage(shortMessage);

          commits.add(GitCommit(
            hash: hash,
            author: author,
            date: date,
            shortMessage: cleanedShortMessage,
            message: cleanedMessage,
          ));
        }
      }

      return commits;
    } catch (e) {
      print('Error getting commits for tag $tag: $e');
      return [];
    }
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

  /// Get all tags sorted by date (newest first)
  Future<List<String>> getSortedTags() async {
    final tagsInfo = await _getTags();
    final tags = tagsInfo['tags'] as List<String>;
    final tagDate = tagsInfo['tagDate'] as Map<String, String>;

    // Sort tags by date
    tags.sort((a, b) {
      final dateA = tagDate[a] ?? '';
      final dateB = tagDate[b] ?? '';
      return dateB.compareTo(dateA); // Newest first
    });

    return tags;
  }

  /// Get unreleased commits (commits after the most recent tag)
  Future<List<GitCommit>> getUnreleasedCommits() async {
    final sortedTags = await getSortedTags();
    if (sortedTags.isEmpty) {
      // If no tags, consider all commits as unreleased
      return await _getCommits();
    }

    final latestTag = sortedTags.first;

    // Get commits since the latest tag
    final result = await _runGitCommand([
      'log',
      '$latestTag..HEAD',
      '--pretty=format:%H|%an|%ad|%s|%b',
      '--date=iso',
      '--no-merges',
    ]);

    if (result.isEmpty) return [];

    final commits = <GitCommit>[];
    final lines = result.split('\n');

    for (final line in lines) {
      if (line.trim().isEmpty) continue;

      final parts = line.split('|');
      if (parts.length >= 4) {
        final hash = parts[0];
        final author = parts[1];
        final date = parts[2];
        final shortMessage = parts[3];
        final message =
            parts.length > 4 ? parts.sublist(4).join('|') : shortMessage;

        final cleanedMessage = _cleanCommitMessage(message);
        final cleanedShortMessage = _cleanCommitMessage(shortMessage);

        commits.add(GitCommit(
          hash: hash,
          author: author,
          date: date,
          shortMessage: cleanedShortMessage,
          message: cleanedMessage,
        ));
      }
    }

    return commits;
  }
}

/// Class representing a Git project's history
class GitHistory {
  List<String> authors = [];
  List<GitCommit> commits = [];
  String firstCommitDate = '';
  String lastCommitDate = '';
  List<String> branches = [];
  List<String> tags = [];
  Map<String, String> tagToCommit = {};
  Map<String, String> tagDate = {};

  Map<String, dynamic> toJson() {
    return {
      'authors': authors,
      'commits': commits.map((c) => c.toJson()).toList(),
      'firstCommitDate': firstCommitDate,
      'lastCommitDate': lastCommitDate,
      'branches': branches,
      'tags': tags,
      'tagToCommit': tagToCommit,
      'tagDate': tagDate,
    };
  }
}

/// Class representing a Git commit
class GitCommit {
  final String hash;
  final String author;
  final String date;
  final String shortMessage;
  final String message;

  GitCommit({
    required this.hash,
    required this.author,
    required this.date,
    required this.shortMessage,
    required this.message,
  });

  Map<String, dynamic> toJson() {
    return {
      'hash': hash,
      'author': author,
      'date': date,
      'shortMessage': shortMessage,
      'message': message,
    };
  }
}
