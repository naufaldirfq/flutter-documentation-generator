import 'package:http/http.dart' as http;
import 'dart:convert';

/// AI provider that uses Ollama to run DeepSeek models locally
class DeepSeekProvider {
  final String modelName;
  final int contextLength;
  final double temperature;
  final bool verbose;
  final String ollamaUrl;
  
  DeepSeekProvider({
    this.modelName = 'deepseek-coder',
    this.contextLength = 4096,
    this.temperature = 0.1,
    this.verbose = true,
    this.ollamaUrl = 'http://localhost:11434',
  });
  
  /// Check if Ollama is running and the model is available
  Future<bool> initialize() async {
    try {
      if (verbose) {
        print('Checking if Ollama is running...');
      }
      
      // Check if Ollama is running
      final response = await http.get(Uri.parse('$ollamaUrl/api/tags'));
      if (response.statusCode != 200) {
        print('Error: Ollama server is not running at $ollamaUrl');
        return false;
      }
      
      // Parse the response to check if the model is available
      final models = jsonDecode(response.body)['models'] as List;
      final modelExists = models.any((model) => 
          model['name'].toString().contains(modelName));
      
      if (!modelExists) {
        print('Warning: Model $modelName not found in Ollama.');
        print('Please run: ollama pull $modelName');
        return false;
      }
      
      if (verbose) {
        print('Ollama is running and $modelName model is available');
      }
      
      return true;
    } catch (e) {
      print('Error connecting to Ollama: $e');
      print('Please make sure Ollama is running with: ollama serve');
      return false;
    }
  }
  
  Future<void> dispose() async {
    // No need to dispose anything with Ollama
    // It runs as a separate process
  }
  
  Future<bool> isReady() async {
    try {
      final response = await http.get(Uri.parse('$ollamaUrl/api/tags'));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
  
  Future<String> generateResponse(String prompt) async {
    try {
      if (!await isReady()) {
        throw Exception('Ollama server is not ready or not running');
      }
      
      if (verbose) {
        print('Sending prompt to Ollama...');
      }
      
      final response = await http.post(
        Uri.parse('$ollamaUrl/api/generate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': modelName,
          'prompt': prompt,
          'system': 'You are an expert Flutter developer and technical documentation writer. Generate clear, accurate, and detailed documentation with proper Markdown formatting.',
          'stream': false,
          'options': {
            'temperature': temperature,
            'num_ctx': contextLength,
          }
        }),
      );
      
      if (response.statusCode != 200) {
        throw Exception('Error from Ollama API: ${response.body}');
      }
      
      final responseJson = jsonDecode(response.body);
      return responseJson['response'] ?? '';
      
    } catch (e) {
      print('Error generating response with Ollama: $e');
      return 'Error: Failed to generate response - $e';
    }
  }
}