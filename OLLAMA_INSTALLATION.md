# Using Ollama with MeDoc

This guide explains how to set up Ollama for use with MeDoc.

## Install Ollama

### macOS

```bash
curl -fsSL https://ollama.com/install.sh | sh
```

### Linux

```bash
curl -fsSL https://ollama.com/install.sh | sh
```

### Windows

Download the installer from [ollama.com](https://ollama.com).

## Start Ollama

After installation, start the Ollama service:

```bash
ollama serve
```

## Pull the DeepSeek model

Before using MeDoc, you need to download the DeepSeek model:

```bash
# Pull the default model
ollama pull deepseek-coder

# Or pull a specific version
ollama pull deepseek-coder:7b-instruct
```

## Available DeepSeek Models

Ollama provides several sizes of the DeepSeek model:

- `deepseek-coder` - Default model
- `deepseek-coder:7b-instruct` - 7B parameter version
- `deepseek-coder:33b-instruct` - 33B parameter version (requires more RAM)

Choose the appropriate model based on your hardware capabilities:
- 7B: Minimum 8GB RAM
- 33B: Minimum 32GB RAM

## Verify Installation

To verify that Ollama is working correctly:

```bash
ollama list
```

You should see `deepseek-coder` listed among the available models.

## Troubleshooting

### Ollama Not Starting

If Ollama doesn't start properly:

```bash
# Check the status
ps aux | grep ollama

# Restart manually
ollama serve
```

### Model Not Found

If MeDoc can't find the model:

```bash
# Make sure you've pulled it
ollama pull deepseek-coder

# Verify it's available
ollama list
```

### Out of Memory

If you encounter memory errors:
- Use a smaller model variant (e.g., 7B instead of 33B)
- Close other memory-intensive applications
- Add a swap file to your system