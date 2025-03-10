# MeDoc - Mekari Document Generator

MeDoc is an AI-powered documentation generator for Flutter projects that automatically creates comprehensive code documentation, changelogs, and project summaries using local AI models.

## Features

- **Automatic Documentation**: Generate detailed docs for Flutter projects with minimal effort
- **Local AI Processing**: Uses Ollama with DeepSeek Coder for privacy and offline use
- **Code Analysis**: Parses and analyzes Flutter/Dart code structure and relationships
- **Git Integration**: Extracts project history to generate detailed changelogs with tag-based versioning
- **Markdown Output**: Clean, structured documentation in Markdown format
- **Performance Optimizations**: Batch processing and configurable limits for large projects

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
- `--batch-size`: Max files to process per batch (default: 10)
- `--batch-delay`: Milliseconds delay between batches (default: 2000)
- `--max-files`: Maximum number of files to process (default: 0 = all files)
- `--max-tags`: Maximum number of tags to analyze for changelog (default: 10)
- `--exclude`, `-e`: File patterns to exclude (can be used multiple times)
- `--overview-only`: Generate only project-level docs without individual file docs
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
modelName: "deepseek-coder:7b-instruct"
temperature: 0.1
contextLength: 4096
verbose: true

# Performance tuning
maxFilesPerBatch: 5        # Process 5 files at a time
delayBetweenBatches: 3000  # Wait 3 seconds between batches
maxFilesToProcess: 100     # Limit to first 100 files (0 for all files)
maxTags: 5                 # Limit to 5 most recent tags for changelog

# Generation options
overviewOnly: true         # Generate only project-level docs

# Documentation settings
excludePaths:
  - "**/*.g.dart"
  - "lib/generated/**"
  - "**/test/**"
```

Then run:

```bash
dart run bin/me_doc.dart --config me_doc_config.yaml
```

## Performance Optimization for Large Projects

When dealing with large codebases (hundreds or thousands of files), MeDoc provides several optimization options:

### Overview-Only Mode

Generate just the project-level documentation without individual file docs:

```bash
dart run bin/me_doc.dart --project ./my_app --overview-only
```

This mode significantly reduces generation time while still providing:
- Project overview documentation
- Project summary (README.md)
- Changelog based on Git history

### Batch Processing

Process files in smaller batches with delays to prevent resource exhaustion:

```bash
dart run bin/me_doc.dart --project ./my_app --batch-size 5 --batch-delay 3000
```

### Limiting File Count

Process only a subset of files to focus on the most important parts:

```bash
dart run bin/me_doc.dart --project ./my_app --max-files 100
```

### Excluding Unnecessary Files

Skip generated files or less important modules:

```bash
dart run bin/me_doc.dart --project ./my_app --exclude "lib/generated/**" --exclude "**/models/**"
```

### Limiting Tag Processing

For repositories with many tags, limit changelog generation to recent releases:

```bash
dart run bin/me_doc.dart --project ./my_app --max-tags 5
```

This generates a changelog focusing only on the 5 most recent version tags, improving performance and readability.

### Choosing Smaller Models

For faster processing with less memory use:

```bash
dart run bin/me_doc.dart --project ./my_app --model deepseek-coder:7b-instruct
```

## Output Structure

MeDoc generates the following documentation:

- `README.md`: Project overview and summary
- `CHANGELOG.md`: Detailed changelog based on Git history, organized by version tags
- `/code/`: Directory containing documentation for each source file
- `/code/overview.md`: High-level overview of the project architecture and structure
- `generation_info.json`: Stats about the documentation generation process
- `progress.log`: Detailed progress tracking during generation

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

1. **Stuck on "Sending prompt to Ollama..."**
   - Reduce batch size (`--batch-size 3`)
   - Increase delay between batches (`--batch-delay 5000`)
   - Use the smaller 7B model
   - Close other memory-intensive applications

2. **Out of Memory Errors**
   - Use a smaller model variant
   - Reduce the number of files processed
   - Close other applications
   - Add swap space to your system

3. **Slow Generation**
   - Use batch processing with reasonable delays
   - Exclude less important files
   - Use the smaller 7B model

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

[MIT License](LICENSE)