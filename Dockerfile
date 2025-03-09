FROM dart:stable

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN dart pub get

COPY . .

# Install Ollama
RUN apt-get update && apt-get install -y curl && \
    curl -fsSL https://ollama.com/install.sh | sh

# Expose the port Ollama will run on
EXPOSE 8080

# Copy the entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Start the Ollama service and run MeDoc
CMD ["/entrypoint.sh"]
