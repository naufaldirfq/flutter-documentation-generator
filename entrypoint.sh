#!/bin/sh

# Start Ollama in the background
ollama serve &

# Wait for Ollama to start
sleep 10

# Pull the DeepSeek model
ollama pull deepseek-coder

# Keep the container running
tail -f /dev/null
