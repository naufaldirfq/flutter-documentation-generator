import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;

/// Service for extracting Git history information
class GitService {
  final String projectPath;
  
  GitService(this.projectPath);
  
  /// Retrieves the project's Git history
  Future<GitHistory> getProjectHistory() async {
    final history = GitHistory();
    
    try {
      // Check if the directory is a Git repository
      final gitDir = Directory(path.join(projectPath, '.git'));
      if (!gitDir.existsSync()) {
        print('Warning: Not a Git repository - $projectPath');
        return history;
      }
      
      // Get commits
      history.commits = await _getCommits();
      
      // Extract unique authors from commits
      final authors = <String>{};
      for (final commit in history.commits) {
        authors.add(commit.author);
      }
      history.authors = authors.toList();
      
      // Set first and last commit dates
      if (history.commits.isNotEmpty) {
        history.firstCommitDate = history.commits.last.date;
        history.lastCommitDate = history.commits.first.date;
      }
      
      // Get tags and branches
      history.tags = await _getTags();
      history.branches = await _getBranches();
      
      return history;
    } catch (e) {
      print('Error extracting Git history: $e');
      return history;
    }
  }
  
  /// Gets list of commits
  Future<List<GitCommit>> _getCommits() async {
    final result = <GitCommit>[];
    
    // Get commit log with format: hash|author|date|subject
    final output = await _runGitCommand([
      'log', 
      '--pretty=format:%H|%an|%ad|%s', 
      '--date=iso',
    ]);
    
    if (output.isEmpty) return result;
    
    // Parse commit log
    final lines = output.split('\n');
    for (final line in lines) {
      final parts = line.split('|');
      if (parts.length < 4) continue;
      
      final hash = parts[0];
      final author = parts[1];
      final date = parts[2];
      final message = parts[3];
      
      // Get files changed in this commit
      final changes = await _getCommitChanges(hash);
      
      result.add(GitCommit(
        hash: hash,
        author: author,
        date: date,
        message: message,
        changes: changes,
      ));
    }
    
    return result;
  }
  
  /// Gets list of changes in a commit
  Future<List<FileChange>> _getCommitChanges(String hash) async {
    final result = <FileChange>[];
    
    // Get diff stats for the commit with format: status|path
    final output = await _runGitCommand([
      'show',
      '--name-status',
      '--format=',
      hash,
    ]);
    
    if (output.isEmpty) return result;
    
    // Parse diff stats
    final lines = output.trim().split('\n');
    for (final line in lines) {
      if (line.isEmpty) continue;
      
      final parts = line.split('\t');
      if (parts.length < 2) continue;
      
      final status = parts[0];
      final filePath = parts[1];
      
      ChangeType changeType;
      switch (status[0]) {
        case 'A': changeType = ChangeType.added; break;
        case 'M': changeType = ChangeType.modified; break;
        case 'D': changeType = ChangeType.deleted; break;
        case 'R': changeType = ChangeType.renamed; break;
        default: changeType = ChangeType.modified; break;
      }
      
      result.add(FileChange(
        path: filePath,
        type: changeType,
      ));
    }
    
    return result;
  }
  
  /// Gets list of Git tags
  Future<List<GitTag>> _getTags() async {
    final result = <GitTag>[];
    
    // Get tags with format: name|hash|date
    final output = await _runGitCommand([
      'tag',
      '--sort=creatordate',
      '--format=%(refname:short)|%(objectname)|%(creatordate:iso)',
    ]);
    
    if (output.isEmpty) return result;
    
    // Parse tags
    final lines = output.trim().split('\n');
    for (final line in lines) {
      if (line.isEmpty) continue;
      
      final parts = line.split('|');
      if (parts.length < 3) continue;
      
      result.add(GitTag(
        name: parts[0],
        hash: parts[1],
        date: parts[2],
      ));
    }
    
    return result;
  }
  
  /// Gets list of Git branches
  Future<List<String>> _getBranches() async {
    final output = await _runGitCommand(['branch', '--list']);
    
    if (output.isEmpty) return [];
    
    // Parse branches (removing the * marker from current branch)
    return output.split('\n')
        .map((branch) => branch.trim().replaceAll('* ', ''))
        .where((branch) => branch.isNotEmpty)
        .toList();
  }
  
  /// Runs a Git command and returns the output
  Future<String> _runGitCommand(List<String> args) async {
    try {
      final result = await Process.run(
        'git',
        args,
        workingDirectory: projectPath,
      );
      
      if (result.exitCode != 0) {
        print('Warning: Git command failed: ${result.stderr}');
        return '';
      }
      
      return result.stdout.toString();
    } catch (e) {
      print('Error running Git command: $e');
      return '';
    }
  }
}

/// Represents the Git history of a project
class GitHistory {
  List<String> authors = [];
  String firstCommitDate = '';
  String lastCommitDate = '';
  List<GitCommit> commits = [];
  List<GitTag> tags = [];
  List<String> branches = [];
  
  Map<String, dynamic> toJson() {
    return {
      'authors': authors,
      'firstCommitDate': firstCommitDate,
      'lastCommitDate': lastCommitDate,
      'commits': commits.map((commit) => commit.toJson()).toList(),
      'tags': tags.map((tag) => tag.toJson()).toList(),
      'branches': branches,
    };
  }
}

/// Represents a Git commit
class GitCommit {
  final String hash;
  final String author;
  final String date;
  final String message;
  final List<FileChange> changes;
  
  GitCommit({
    required this.hash,
    required this.author,
    required this.date,
    required this.message,
    required this.changes,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'hash': hash,
      'author': author,
      'date': date,
      'message': message,
      'changes': changes.map((change) => change.toJson()).toList(),
    };
  }
}

/// Represents a change to a file in a Git commit
class FileChange {
  final String path;
  final ChangeType type;
  
  FileChange({
    required this.path,
    required this.type,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'type': type.toString().split('.').last,
    };
  }
}

/// Type of change to a file
enum ChangeType {
  added,
  modified,
  deleted,
  renamed,
}

/// Represents a Git tag
class GitTag {
  final String name;
  final String hash;
  final String date;
  
  GitTag({
    required this.name,
    required this.hash,
    required this.date,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'hash': hash,
      'date': date,
    };
  }
}