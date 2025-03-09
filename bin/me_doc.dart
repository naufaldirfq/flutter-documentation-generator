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
    ..addFlag('verbose',
        abbr: 'v', help: 'Show detailed output', defaultsTo: true)
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
      };
    }

    // Create generator
    final generator = DocumentGenerator(
      projectPath: config['projectPath'],
      outputPath: config['outputPath'],
      modelName: config['modelName'] ?? 'deepseek-coder',
      temperature: config['temperature'] ?? 0.1,
      contextLength: config['contextLength'] ?? 4096,
      verbose: config['verbose'] ?? true,
    );

    // Run generation
    await generator.generateDocumentation();
  } catch (e) {
    print('Error: $e');
    printUsage(parser);
    exit(1);
  }
}

void printUsage(ArgParser parser) {
  print('MeDoc - Mekari Document Generator with Ollama');
  print('Usage: me_doc --project <flutter_project_path> [options]');
  print('       me_doc --config <config_file_path>');
  print(parser.usage);
  print('\nExample:');
  print(
      '  me_doc --project ~/my_flutter_app --model deepseek-coder:7b-instruct');
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
  if (yamlMap is Map) {
    return yamlMap.map((key, value) => MapEntry(
          key.toString(),
          value is Map || value is List ? convertYamlToMap(value) : value,
        ));
  } else if (yamlMap is List) {
    return {
      'list': yamlMap
          .map((item) =>
              item is Map || item is List ? convertYamlToMap(item) : item)
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
