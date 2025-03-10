import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

/// AI provider that uses Ollama to run DeepSeek models locally
class DeepSeekProvider {
  final String modelName;
  final int contextLength;
  final double temperature;
  final bool verbose;
  final String ollamaUrl;
  final int maxRetries;
  final int retryDelay;
  final int timeout;

  DeepSeekProvider({
    this.modelName = 'deepseek-coder',
    this.contextLength = 4096,
    this.temperature = 0.1,
    this.verbose = true,
    this.ollamaUrl = 'http://localhost:11434',
    this.maxRetries = 3,
    this.retryDelay = 5000,
    this.timeout = 120000, // 2 minute timeout
  });

  /// Check if Ollama is running and the model is available
  Future<bool> initialize() async {
    try {
      if (verbose) {
        print('Checking if Ollama is running...');
      }

      // Check if Ollama is running
      final response = await http
          .get(Uri.parse('$ollamaUrl/api/tags'))
          .timeout(Duration(milliseconds: timeout));

      if (response.statusCode != 200) {
        print('Error: Ollama server is not running at $ollamaUrl');
        return false;
      }

      // Parse the response to check if the model is available
      final models = jsonDecode(response.body)['models'] as List;
      final modelExists =
          models.any((model) => model['name'].toString().contains(modelName));

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
      final response = await http
          .get(Uri.parse('$ollamaUrl/api/tags'))
          .timeout(Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<String> generateResponse(String prompt) async {
    int attempts = 0;

    // Truncate prompt if too long
    if (prompt.length > contextLength * 4) {
      final truncatedLength = contextLength * 4 - 100;
      prompt = prompt.substring(0, truncatedLength) +
          "\n\n[Note: Content was truncated due to length limitations. Please focus on the visible code.]";

      if (verbose) {
        print('Warning: Prompt was truncated to ${prompt.length} characters');
      }
    }

    while (attempts < maxRetries) {
      attempts++;
      try {
        if (!await isReady()) {
          throw Exception('Ollama server is not ready or not running');
        }

        if (verbose) {
          print('Sending prompt to Ollama (attempt $attempts/$maxRetries)...');
        }

        final response = await http
            .post(
              Uri.parse('$ollamaUrl/api/generate'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'model': modelName,
                'prompt': prompt,
                'system':
                    'You are an expert Flutter developer and technical documentation writer. Generate clear, accurate, and detailed documentation with proper Markdown formatting.',
                'stream': false,
                'options': {
                  'temperature': temperature,
                  'num_ctx': contextLength,
                }
              }),
            )
            .timeout(Duration(milliseconds: timeout));

        if (response.statusCode != 200) {
          throw Exception('Error from Ollama API: ${response.body}');
        }

        final responseJson = jsonDecode(response.body);
        final generatedText = responseJson['response'] ?? '';

        if (generatedText.isEmpty) {
          throw Exception('Ollama returned an empty response');
        }

        return generatedText;
      } catch (e) {
        print('Error generating response (attempt $attempts/$maxRetries): $e');

        if (attempts < maxRetries) {
          print('Retrying in ${retryDelay / 1000} seconds...');
          await Future.delayed(Duration(milliseconds: retryDelay));
        } else {
          return 'Error: Failed to generate response after $maxRetries attempts - $e';
        }
      }
    }

    return 'Error: Failed to generate response after $maxRetries attempts';
  }
}
