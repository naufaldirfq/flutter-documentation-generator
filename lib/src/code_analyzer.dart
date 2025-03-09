import 'dart:io';
import 'dart:convert';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

/// Analyzes a Flutter project's code structure
class CodeAnalyzer {
  final String projectPath;
  
  CodeAnalyzer(this.projectPath);
  
  /// Analyzes the project and returns its structure
  Future<ProjectStructure> analyzeProject() async {
    // Parse pubspec.yaml for project metadata
    final metadata = await _parseProjectMetadata();
    
    // Find all Dart files in the project
    final dartFiles = await _findDartFiles();
    
    // Set up analyzer
    final contextCollection = AnalysisContextCollection(
      includedPaths: [projectPath],
      resourceProvider: PhysicalResourceProvider.INSTANCE,
    );
    
    // Analyze each file
    final filesAnalysis = <String, FileAnalysis>{};
    final widgets = <String>[];
    final services = <String>[];
    final models = <String>[];
    
    print('Found ${dartFiles.length} Dart files to analyze');
    
    int count = 0;
    for (final file in dartFiles) {
      count++;
      if (count % 10 == 0) {
        print('Analyzing file $count/${dartFiles.length}');
      }
      
      try {
        final context = contextCollection.contextFor(file);
        final resolvedUnit = await context.currentSession.getResolvedUnit(file);
        
        if (resolvedUnit is ResolvedUnitResult) {
          final fileAnalysis = _analyzeFile(resolvedUnit, file);
          filesAnalysis[file] = fileAnalysis;
          
          // Categorize classes
          for (final classInfo in fileAnalysis.classes) {
            if (_isWidget(classInfo)) {
              widgets.add('${fileAnalysis.relativePath}:${classInfo.name}');
            } else if (_isService(classInfo)) {
              services.add('${fileAnalysis.relativePath}:${classInfo.name}');
            } else if (_isModel(classInfo)) {
              models.add('${fileAnalysis.relativePath}:${classInfo.name}');
            }
          }
        }
      } catch (e) {
        print('Error analyzing $file: $e');
        // Continue with next file
      }
    }
    
    return ProjectStructure(
      metadata: metadata,
      files: filesAnalysis,
      widgets: widgets,
      services: services,
      models: models,
    );
  }
  
  /// Parse project metadata from pubspec.yaml
  Future<ProjectMetadata> _parseProjectMetadata() async {
    try {
      final pubspecFile = File(path.join(projectPath, 'pubspec.yaml'));
      if (!pubspecFile.existsSync()) {
        return ProjectMetadata(
          name: 'unknown',
          description: 'No pubspec.yaml found',
          version: 'unknown',
          dependencies: {},
          devDependencies: {},
        );
      }
      
      final pubspecContent = await pubspecFile.readAsString();
      final yaml = loadYaml(pubspecContent);
      
      final dependencies = <String, String>{};
      if (yaml['dependencies'] is Map) {
        for (var entry in (yaml['dependencies'] as Map).entries) {
          dependencies[entry.key.toString()] = entry.value.toString();
        }
      }
      
      final devDependencies = <String, String>{};
      if (yaml['dev_dependencies'] is Map) {
        for (var entry in (yaml['dev_dependencies'] as Map).entries) {
          devDependencies[entry.key.toString()] = entry.value.toString();
        }
      }
      
      return ProjectMetadata(
        name: yaml['name']?.toString() ?? 'unknown',
        description: yaml['description']?.toString() ?? '',
        version: yaml['version']?.toString() ?? 'unknown',
        dependencies: dependencies,
        devDependencies: devDependencies,
      );
    } catch (e) {
      print('Error parsing pubspec.yaml: $e');
      return ProjectMetadata(
        name: 'unknown',
        description: 'Error parsing pubspec.yaml',
        version: 'unknown',
        dependencies: {},
        devDependencies: {},
      );
    }
  }
  
  /// Find all Dart files in the project
  Future<List<String>> _findDartFiles() async {
    final result = <String>[];
    
    await _findFiles(Directory(projectPath), '.dart', result);
    
    // Filter out test files, generated files, and build directory
    return result.where((file) => 
      !file.contains('/test/') && 
      !file.contains('/.dart_tool/') &&
      !file.contains('/build/') &&
      !file.endsWith('.g.dart') &&
      !file.endsWith('.freezed.dart')
    ).toList();
  }
  
  /// Recursively find files with a specific extension
  Future<void> _findFiles(Directory directory, String extension, List<String> result) async {
    try {
      await for (final entity in directory.list()) {
        if (entity is File && entity.path.endsWith(extension)) {
          result.add(entity.path);
        } else if (entity is Directory && 
                  !path.basename(entity.path).startsWith('.') && 
                  !path.basename(entity.path).startsWith('build')) {
          await _findFiles(entity, extension, result);
        }
      }
    } catch (e) {
      // Skip directories that can't be read
    }
  }
  
  /// Analyze a single Dart file
  FileAnalysis _analyzeFile(ResolvedUnitResult resolvedUnit, String filePath) {
    final relativePath = path.relative(filePath, from: projectPath);
    final visitor = _CodeVisitor();
    resolvedUnit.unit.accept(visitor);
    
    return FileAnalysis(
      path: filePath,
      relativePath: relativePath,
      classes: visitor.classes,
      imports: visitor.imports,
      exports: visitor.exports,
    );
  }
  
  /// Check if a class is a Flutter widget
  bool _isWidget(ClassInfo classInfo) {
    return classInfo.superclass?.contains('Widget') == true ||
           classInfo.superclass?.contains('StatelessWidget') == true ||
           classInfo.superclass?.contains('StatefulWidget') == true ||
           classInfo.interfaces.any((i) => i.contains('Widget'));
  }
  
  /// Check if a class is likely a service
  bool _isService(ClassInfo classInfo) {
    return classInfo.name.contains('Service') ||
           classInfo.name.contains('Repository') ||
           classInfo.name.contains('Provider') ||
           classInfo.name.contains('Controller') ||
           classInfo.methods.any((m) => 
             m.name.contains('fetch') || 
             m.name.contains('get') ||
             m.name.contains('load') ||
             m.name.contains('save') ||
             m.name.contains('update') ||
             m.name.contains('delete')
           );
  }
  
  /// Check if a class is likely a data model
  bool _isModel(ClassInfo classInfo) {
    return classInfo.name.contains('Model') ||
           classInfo.name.contains('Entity') ||
           classInfo.name.contains('Data') ||
           classInfo.name.contains('DTO') ||
           (classInfo.fields.length > 2 && classInfo.methods.isEmpty);
  }
}

/// Visitor for collecting information about a Dart file
class _CodeVisitor extends RecursiveAstVisitor<void> {
  final List<ClassInfo> classes = [];
  final List<String> imports = [];
  final List<String> exports = [];
  
  @override
  void visitImportDirective(ImportDirective node) {
    imports.add(node.uri.stringValue ?? '');
    super.visitImportDirective(node);
  }
  
  @override
  void visitExportDirective(ExportDirective node) {
    exports.add(node.uri.stringValue ?? '');
    super.visitExportDirective(node);
  }
  
  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final classInfo = ClassInfo(
      name: node.name.lexeme,
      isAbstract: node.abstractKeyword != null,
      superclass: node.extendsClause?.superclass.element?.name,
      interfaces: node.implementsClause?.interfaces
          .map((type) => type.element?.name ?? "")
          .toList() ?? [],
      mixins: node.withClause?.mixinTypes
          .map((type) => type.element?.name ?? "")
          .toList() ?? [],
      fields: [],
      methods: [],
    );
    
    for (final member in node.members) {
      if (member is FieldDeclaration) {
        for (final variable in member.fields.variables) {
          classInfo.fields.add(FieldInfo(
            name: variable.name.lexeme,
            type: member.fields.type?.toString() ?? 'dynamic',
            isStatic: member.isStatic,
            isFinal: member.fields.isFinal,
            isConst: member.fields.isConst,
            isPrivate: variable.name.lexeme.startsWith('_'),
          ));
        }
      } else if (member is MethodDeclaration) {
        classInfo.methods.add(MethodInfo(
          name: member.name.lexeme,
          returnType: member.returnType?.toString() ?? 'dynamic',
          isStatic: member.isStatic,
          isGetter: member.isGetter,
          isSetter: member.isSetter,
          isPrivate: member.name.lexeme.startsWith('_'),
        ));
      } else if (member is ConstructorDeclaration) {
        classInfo.methods.add(MethodInfo(
          name: member.name?.lexeme ?? 'constructor',
          returnType: classInfo.name,
          isStatic: false,
          isGetter: false,
          isSetter: false,
          isPrivate: (member.name?.lexeme ?? '').startsWith('_'),
          isConstructor: true,
        ));
      }
    }
    
    classes.add(classInfo);
    super.visitClassDeclaration(node);
  }
}

/// Represents the structure of a Flutter project
class ProjectStructure {
  final ProjectMetadata metadata;
  final Map<String, FileAnalysis> files;
  final List<String> widgets;
  final List<String> services;
  final List<String> models;
  
  ProjectStructure({
    required this.metadata,
    required this.files,
    required this.widgets,
    required this.services,
    required this.models,
  });
}

/// Metadata about a Flutter project from pubspec.yaml
class ProjectMetadata {
  final String name;
  final String description;
  final String version;
  final Map<String, String> dependencies;
  final Map<String, String> devDependencies;
  
  ProjectMetadata({
    required this.name,
    required this.description,
    required this.version,
    required this.dependencies,
    required this.devDependencies,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'version': version,
      'dependencies': dependencies,
      'devDependencies': devDependencies,
    };
  }
}

/// Analysis of a single Dart file
class FileAnalysis {
  final String path;
  final String relativePath;
  final List<ClassInfo> classes;
  final List<String> imports;
  final List<String> exports;
  
  FileAnalysis({
    required this.path,
    required this.relativePath,
    required this.classes,
    required this.imports,
    required this.exports,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'relativePath': relativePath,
      'classes': classes.map((c) => c.toJson()).toList(),
      'imports': imports,
      'exports': exports,
    };
  }
}

/// Information about a Dart class
class ClassInfo {
  final String name;
  final bool isAbstract;
  final String? superclass;
  final List<String> interfaces;
  final List<String> mixins;
  final List<FieldInfo> fields;
  final List<MethodInfo> methods;
  
  ClassInfo({
    required this.name,
    required this.isAbstract,
    this.superclass,
    required this.interfaces,
    required this.mixins,
    required this.fields,
    required this.methods,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'isAbstract': isAbstract,
      'superclass': superclass,
      'interfaces': interfaces,
      'mixins': mixins,
      'fields': fields.map((f) => f.toJson()).toList(),
      'methods': methods.map((m) => m.toJson()).toList(),
    };
  }
}

/// Information about a class field
class FieldInfo {
  final String name;
  final String type;
  final bool isStatic;
  final bool isFinal;
  final bool isConst;
  final bool isPrivate;
  
  FieldInfo({
    required this.name,
    required this.type,
    required this.isStatic,
    required this.isFinal,
    required this.isConst,
    required this.isPrivate,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'type': type,
      'isStatic': isStatic,
      'isFinal': isFinal,
      'isConst': isConst,
      'isPrivate': isPrivate,
    };
  }
}

/// Information about a class method
class MethodInfo {
  final String name;
  final String returnType;
  final bool isStatic;
  final bool isGetter;
  final bool isSetter;
  final bool isPrivate;
  final bool isConstructor;
  
  MethodInfo({
    required this.name,
    required this.returnType,
    required this.isStatic,
    required this.isGetter,
    required this.isSetter,
    required this.isPrivate,
    this.isConstructor = false,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'returnType': returnType,
      'isStatic': isStatic,
      'isGetter': isGetter,
      'isSetter': isSetter,
      'isPrivate': isPrivate,
      'isConstructor': isConstructor,
    };
  }
}