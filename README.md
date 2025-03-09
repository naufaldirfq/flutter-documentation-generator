# MeDoc - Mekari Document Generator

MeDoc is an AI-powered documentation generator for Flutter projects that automatically creates comprehensive code documentation, changelogs, and project summaries using local AI models.

## Features

- **Automatic Documentation**: Generate detailed docs for Flutter projects with minimal effort
- **Local AI Processing**: Uses Ollama with DeepSeek Coder for privacy and offline use
- **Code Analysis**: Parses and analyzes Flutter/Dart code structure and relationships
- **Git Integration**: Extracts project history to generate detailed changelogs
- **Markdown Output**: Clean, structured documentation in Markdown format

## Prerequisites

- Dart SDK 3.0.0 or higher
- [Ollama](https://ollama.ai/) - Local AI model server
- Git (for project history analysis)

## Quick Start

### 1. Install Ollama

```bash
# macOS/Linux
curl -fsSL https://ollama.com/install.sh | sh

# Windows: Download from https://ollama.com
```

### 2. Pull the DeepSeek Coder model

```bash
# Pull the model (only needed once)
ollama pull deepseek-coder
```

### 3. Install MeDoc

```bash
git clone https://github.com/your-username/me-doc.git
cd me-doc
dart pub get
```

### 4. Run MeDoc

```bash
# Make sure Ollama is running
ollama serve

# Run MeDoc
dart run bin/me_doc.dart --project /path/to/your_flutter_project
```

## Usage Options

### Command Line

```bash
dart run bin/me_doc.dart --project /path/to/flutter_project [options]
```

Options:
- `--project`, `-p`: Path to Flutter project (required unless using config file)
- `--output`, `-o`: Output directory for documentation (default: project_path/docs)
- `--model`, `-m`: Ollama model to use (default: deepseek-coder)
- `--temperature`, `-t`: AI creativity level 0.0-1.0 (default: 0.1)
- `--config`, `-c`: Path to configuration file
- `--verbose`, `-v`: Show detailed output (default: true)
- `--help`, `-h`: Show usage information

### Using a Configuration File

Create a `me_doc_config.yaml` file:

```yaml
# Project paths
projectPath: "./your_flutter_project"
outputPath: "./docs"

# Ollama AI Settings
modelName: "deepseek-coder"
temperature: 0.1
contextLength: 4096
verbose: true

# Documentation settings
include:
  - lib/**/*.dart
exclude:
  - lib/generated/**
```

Then run:

```bash
dart run bin/me_doc.dart --config me_doc_config.yaml
```

## Output Structure

MeDoc generates the following documentation:

- `README.md`: Project overview and summary
- `CHANGELOG.md`: Detailed changelog based on Git history
- `/code/`: Directory containing documentation for each source file

## Available Models

MeDoc works with the DeepSeek Coder family of models available through Ollama:

- `deepseek-coder` - Default model
- `deepseek-coder:7b-instruct` - 7B parameter version (smaller, faster)
- `deepseek-coder:33b-instruct` - 33B parameter version (better quality, more resources)

Choose the appropriate model based on your hardware capabilities.

## System Requirements

- **Minimum**: 8GB RAM, dual-core CPU for `deepseek-coder:7b-instruct`
- **Recommended**: 16GB RAM, quad-core CPU for default `deepseek-coder` model
- **High-end**: 32GB RAM, 8-core CPU for `deepseek-coder:33b-instruct` model

## Design and Architecture

MeDoc is built with a modular architecture:

- **Code Analyzer**: Parses Flutter/Dart code and extracts structure
- **Git Service**: Extracts repository history
- **AI Service**: Interfaces with Ollama to generate documentation
- **Document Generator**: Orchestrates the documentation process

## Advanced Usage

### Customizing the AI Model

You can use different Ollama models by changing the `modelName` parameter:

```bash
dart run bin/me_doc.dart --project ./my_app --model deepseek-coder:7b-instruct
```

### Adjusting Output Quality

For more creative output, increase the temperature:

```bash
dart run bin/me_doc.dart --project ./my_app --temperature 0.7
```

## Troubleshooting

### Common Issues

1. **"Failed to initialize Ollama"**
   - Ensure Ollama is running with `ollama serve`
   - Verify the model is installed with `ollama list`

2. **Slow Generation**
   - Try a smaller model like `deepseek-coder:7b-instruct`
   - Close other resource-intensive applications

3. **Out of Memory Errors**
   - Use a smaller model variant
   - Increase swap space on your system

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

[MIT License](LICENSE)