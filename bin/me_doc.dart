import 'dart:io';
import 'package:args/args.dart';
import 'package:me_doc/src/generator.dart';
import 'package:yaml/yaml.dart';
import 'package:path/path.dart' as path;

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('project', abbr: 'p', help: 'Path to Flutter project')
    ..addOption('output', abbr: 'o', help: 'Output directory for documentation')
    ..addOption('config', abbr: 'c', help: 'Path to configuration file')
    ..addOption('model',
        abbr: 'm', help: 'Ollama model name', defaultsTo: 'deepseek-coder')
    ..addOption('temperature',
        abbr: 't', help: 'AI temperature (0.0-1.0)', defaultsTo: '0.1')
    ..addOption('batch-size',
        help: 'Max files to process per batch', defaultsTo: '10')
    ..addOption('batch-delay',
        help: 'Milliseconds delay between batches', defaultsTo: '2000')
    ..addOption('max-files',
        help: 'Maximum number of files to process (0 for all)', defaultsTo: '0')
    ..addOption('max-tags',
        help: 'Maximum number of tags to analyze for changelog (0 for all)',
        defaultsTo: '10')
    ..addMultiOption('exclude',
        abbr: 'e',
        help: 'File patterns to exclude (can be used multiple times)',
        defaultsTo: [])
    ..addFlag('verbose',
        abbr: 'v', help: 'Show detailed output', defaultsTo: true)
    ..addFlag('overview-only',
        help: 'Generate only project overview without individual file docs',
        defaultsTo: false)
    ..addFlag('help',
        abbr: 'h', negatable: false, help: 'Show usage information');

  try {
    final results = parser.parse(arguments);

    if (results['help'] ||
        (results['project'] == null && results['config'] == null)) {
      printUsage(parser);
      exit(0);
    }

    // Load config file if provided, otherwise use CLI arguments
    Map<String, dynamic> config;
    if (results['config'] != null) {
      config = await loadConfig(results['config']);
    } else {
      final projectPath = results['project'];
      if (projectPath == null) {
        print('Error: Project path is required');
        printUsage(parser);
        exit(1);
      }

      config = {
        'projectPath': projectPath,
        'outputPath': results['output'] ?? '${projectPath}/docs',
        'modelName': results['model'],
        'temperature': double.parse(results['temperature']),
        'contextLength': 4096,
        'verbose': results['verbose'],
        'maxFilesPerBatch': int.parse(results['batch-size']),
        'delayBetweenBatches': int.parse(results['batch-delay']),
        'maxFilesToProcess': int.parse(results['max-files']),
        'excludePaths': results['exclude'],
        'overviewOnly': results['overview-only'],
        'maxTags': int.parse(results['max-tags']),
      };
    }

    // Create generator with proper handling of excludePaths
    final generator = DocumentGenerator(
      projectPath: config['projectPath'],
      outputPath: config['outputPath'],
      modelName: config['modelName'] ?? 'deepseek-coder',
      temperature: config['temperature'] ?? 0.1,
      contextLength: config['contextLength'] ?? 4096,
      verbose: config['verbose'] ?? true,
      maxFilesPerBatch: config['maxFilesPerBatch'] ?? 10,
      delayBetweenBatches: config['delayBetweenBatches'] ?? 2000,
      maxFilesToProcess: config['maxFilesToProcess'] ?? 0,
      excludePaths: _getExcludePathsList(config['excludePaths']),
      overviewOnly: config['overviewOnly'] ?? false,
      maxTags: config['maxTags'] ?? 10,
    );

    // Run generation
    await generator.generateDocumentation();
  } catch (e) {
    print('Error: $e');
    printUsage(parser);
    exit(1);
  }
}

// Helper function to ensure excludePaths is always a List<String>
List<String> _getExcludePathsList(dynamic excludePaths) {
  if (excludePaths == null) {
    return [];
  } else if (excludePaths is List) {
    return excludePaths.map((e) => e.toString()).toList();
  } else if (excludePaths is Map && excludePaths.containsKey('list')) {
    final list = excludePaths['list'];
    if (list is List) {
      return list.map((e) => e.toString()).toList();
    }
  }
  return [];
}

void printUsage(ArgParser parser) {
  print('MeDoc - Mekari Document Generator with Ollama');
  print('Usage: me_doc --project <flutter_project_path> [options]');
  print('       me_doc --config <config_file_path>');
  print(parser.usage);
  print('\nExample:');
  print(
      '  me_doc --project ~/my_flutter_app --model deepseek-coder:7b-instruct --batch-size 5');
  print('\nPerformance Tips:');
  print('  - For large projects use --batch-size 5 --batch-delay 3000');
  print('  - Use --max-files 100 to process only a subset of files');
  print(
      '  - Use --max-tags 5 to limit changelog generation to recent releases');
  print('  - Use --overview-only to generate only project-level documentation');
  print(
      '  - Use --exclude "lib/generated/**" --exclude "lib/models/**" to skip certain paths');
  print('\nNotes:');
  print('  - Ollama must be installed and running on your system');
  print('  - Make sure to pull the model first: ollama pull deepseek-coder');
}

Future<Map<String, dynamic>> loadConfig(String configPath) async {
  final file = File(configPath);
  if (!file.existsSync()) {
    throw Exception('Config file not found: $configPath');
  }

  final yamlString = await file.readAsString();
  final yamlMap = loadYaml(yamlString);

  // Convert YamlMap to Map<String, dynamic>
  return convertYamlToMap(yamlMap);
}

Map<String, dynamic> convertYamlToMap(dynamic yamlMap) {
  if (yamlMap is YamlMap) {
    final map = <String, dynamic>{};
    for (var entry in yamlMap.entries) {
      final key = entry.key.toString();
      final value = entry.value;
      if (value is YamlMap) {
        map[key] = convertYamlToMap(value);
      } else if (value is YamlList) {
        map[key] = value
            .map((item) => item is YamlMap || item is YamlList
                ? convertYamlToMap(item)
                : item)
            .toList();
      } else {
        map[key] = value;
      }
    }
    return map;
  } else if (yamlMap is YamlList) {
    return {
      'list': yamlMap
          .map((item) => item is YamlMap || item is YamlList
              ? convertYamlToMap(item)
              : item)
          .toList()
    };
  }

  return {};
}

String? findDefaultModel() {
  // Try to find DeepSeek model in common locations
  final homeDir = Platform.environment['HOME'] ?? '';
  final possibleLocations = [
    path.join(homeDir, 'models', 'deepseek-r1-8b'),
    path.join(homeDir, '.cache', 'deepseek-models', 'deepseek-r1-8b'),
    path.join(homeDir, 'Documents', 'models', 'deepseek-r1-8b'),
    'models/deepseek-r1-8b',
  ];

  for (final location in possibleLocations) {
    if (Directory(location).existsSync()) {
      final modelFile = path.join(location, 'model.bin');
      if (File(modelFile).existsSync()) {
        return modelFile;
      }
    }
  }

  return null;
}
