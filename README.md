# LocalAI Self-Hosted Deployment Guide

## 🚀 Quick Start with Deploy Script

For a clean Ubuntu 22.04 installation, you can use our deployment script:

```bash
# Clone the repository
git clone https://github.com/yourusername/self_hosted_ai.git
cd self_hosted_ai

# Make the script executable
chmod +x deploy.sh

# Run the deployment script
sudo ./deploy.sh
```

This script will:
1. Check system requirements (disk space, memory)
2. Install all dependencies (Docker, Docker Compose, Python packages)
3. Set up the LocalAI directory structure at /opt/localai/
4. Run the setup script
5. Provide next steps for downloading models

This guide provides comprehensive instructions for managing your self-hosted LocalAI deployment after installation.

## ⚡️ New: CPU-Optimized Models Downloader

We've added two scripts to automatically download CPU-optimized models:

### 1. Curated Model Collection Script

```bash
# Make the script executable
chmod +x /opt/localai/download-cpu-optimized-models.sh

# Run it
sudo ./download-cpu-optimized-models.sh
```

The script will:
1. Download several high-quality 4-bit quantized models optimized for CPU performance
2. Configure them with appropriate settings for your CPU
3. Create OpenAI-compatible aliases for easy integration
4. Intelligently adjust thread counts based on your available CPU cores

### 2. Dynamic Model Discovery Script

```bash
# Install requirements
pip install huggingface_hub tqdm requests

# Make the script executable
chmod +x /opt/localai/auto-update-models.py

# Run with default settings
sudo python3 /opt/localai/auto-update-models.py

# Or show advanced options
sudo python3 /opt/localai/auto-update-models.py --help
```

This Python script will:
1. Query the Hugging Face API to find trending GGUF models
2. Identify Q4_K_M quantized files (best for CPU inference)
3. Download the most popular models automatically
4. Create appropriate configurations adjusted for your CPU
5. Create OpenAI-compatible aliases (e.g., gpt-3.5-turbo)

Example advanced usage:
```bash
# Download only small models (1-3B params)
sudo python3 /opt/localai/auto-update-models.py --small-only

# Download specific model categories
sudo python3 /opt/localai/auto-update-models.py --include-categories "llama,phi,gemma"

# List trending models without downloading
sudo python3 /opt/localai/auto-update-models.py --list-only
```

See [CPU_OPTIMIZED_MODELS.md](docs/CPU_OPTIMIZED_MODELS.md) for detailed information about model quantization and CPU performance considerations.

## Table of Contents

- [What to Expect After Installation](#what-to-expect-after-installation)
- [Basic Operations](#basic-operations)
- [Managing Models](#managing-models)
- [Load Balancing and Scaling](#load-balancing-and-scaling)
- [Security Considerations](#security-considerations)
- [Troubleshooting](#troubleshooting)

## What to Expect After Installation

After successfully running the `setup-localai.sh` script, you'll have:

- A LocalAI instance running on port 8080
- Three pre-installed models:
  - `phi-2-q4` (Microsoft Phi-2, quantized)
  - `orca-mini-3b-q4` (Orca Mini 3B, quantized)
  - `llama-3.2-1b-instruct` (Meta Llama 3.2 1B Instruct)
- A secure configuration with a randomly generated API key
- Management scripts for maintenance and updates

The installation creates these directories:
- `/opt/localai/models/` - Contains model files (.gguf)
- `/opt/localai/config/` - Contains model configurations and settings
- `/opt/localai/` - Contains Docker Compose files and management scripts

## Basic Operations

### Checking Server Status

```bash
# Check if LocalAI is running
cd /opt/localai
docker-compose ps

# View logs
docker-compose logs -f
```

### Starting and Stopping

```bash
# Start services
cd /opt/localai
docker-compose up -d

# Stop services
docker-compose down

# Restart services
docker-compose restart
```

### Testing the API

Test that the API is working correctly:

```bash
# Using curl with your API key (found in .env file)
API_KEY=$(grep API_KEY /opt/localai/.env | cut -d= -f2)

curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{
    "model": "phi-2-q4",
    "messages": [
      {
        "role": "user",
        "content": "Hello, can you tell me about yourself?"
      }
    ],
    "temperature": 0.7
  }'
```

### Accessing the Web UI

LocalAI includes a basic web UI that can be accessed at:
```
http://localhost:8080/
```

## Managing Models

### Creating Model Aliases

For easier integration with existing applications and developer workflows, you can create model aliases that map familiar model names (like OpenAI's) to your local models:

```bash
# Create an alias configuration file
sudo nano /opt/localai/config/gpt-3.5-turbo.yaml
```

Add the following content to create an alias that points to one of your local models:

```yaml
name: gpt-3.5-turbo  # The alias name (what developers will use)
backend: llama-cpp
parameters:
  model: /models/phi-2-q4.gguf  # Point to your actual model file
  context_size: 2048
  threads: 4
  f16: true
template:
  chat:
    template: |
      <s>{{- if .System }}
      {{.System}}
      {{- end }}
      {{- range $i, $message := .Messages }}
      {{- if eq $message.Role "user" }}
      [INST] {{ $message.Content }} [/INST]
      {{- else if eq $message.Role "assistant" }}
      {{ $message.Content }}
      {{- end }}
      {{- end }}
```

After creating the alias, restart LocalAI:

```bash
cd /opt/localai && docker-compose restart localai
```

Now developers can use the familiar OpenAI model names in their applications:

```python
# Python example using the alias
import openai

openai.api_key = "your_localai_api_key"
openai.api_base = "http://localhost:8080/v1"

response = openai.ChatCompletion.create(
    model="gpt-3.5-turbo",  # This will use your phi-2-q4 model
    messages=[
        {"role": "user", "content": "Hello, how are you?"}
    ]
)
```

You can create multiple aliases including:
- `gpt-3.5-turbo` → points to a medium model
- `gpt-4` → points to your largest model
- `text-embedding-ada-002` → points to an embedding model

This makes it much easier to integrate with existing code and libraries that expect specific model names.

### Automated Alias Creation

For convenience, the repository includes a script to automatically create common OpenAI-compatible aliases:

```bash
# Make the script executable
chmod +x /opt/localai/create-aliases.sh

# Run the script
sudo /opt/localai/create-aliases.sh
```

The script will:
1. Show you a list of available models
2. Ask which models to map to common OpenAI model names
3. Create the configuration files automatically
4. Restart LocalAI to apply the changes

This is the fastest way to set up aliases for OpenAI compatibility.

### Model-Specific API Endpoints

In addition to aliases, LocalAI supports directly accessing models through dedicated endpoints:

```bash
# Standard endpoint (requires model parameter in JSON)
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{
    "model": "phi-2-q4",
    "messages": [{"role": "user", "content": "Hello"}]
  }'

# Model-specific endpoint (doesn't need model parameter in JSON)
curl http://localhost:8080/v1/models/phi-2-q4/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

This approach allows developers to hardcode the model in the URL rather than in the payload, which can simplify API integration in some workflows.

### Configuring Path-Based Routing

For advanced setups, you can use a reverse proxy to create intuitive routing:

```nginx
# Example Nginx configuration for model-specific paths
server {
    listen 80;
    server_name ai.yourdomain.com;

    # Route specific paths to specific models
    location /api/small/ {
        proxy_pass http://localhost:8080/v1/models/phi-2-q4/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /api/medium/ {
        proxy_pass http://localhost:8080/v1/models/orca-mini-3b-q4/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /api/large/ {
        proxy_pass http://localhost:8080/v1/models/llama-3.2-1b-instruct/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    # Default API path
    location /api/ {
        proxy_pass http://localhost:8080/v1/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

With this configuration, developers could use endpoints like:
- `/api/small/chat/completions` → Routes to phi-2-q4
- `/api/medium/chat/completions` → Routes to orca-mini-3b-q4
- `/api/large/chat/completions` → Routes to llama-3.2-1b-instruct

### Currently Installed Models

The installation comes with three pre-configured models:

1. **phi-2-q4** - Microsoft Phi-2 (small but capable general purpose model)
   - Good for: Text generation, coding, reasoning, QA
   - Size: ~2GB

2. **orca-mini-3b-q4** - Orca Mini 3B (slightly larger general purpose model)
   - Good for: More detailed responses, better reasoning
   - Size: ~4GB

3. **llama-3.2-1b-instruct** - Llama 3.2 1B Instruct (latest from Meta)
   - Good for: Instruction following, chat
   - Size: ~2GB

### Adding New Models

The easiest way to add a new model is using the provided script:

```bash
cd /opt/localai
sudo ./add-model.sh model_name model_url
```

For example:

```bash
# Add TinyLlama
sudo ./add-model.sh tinyllama-1.1b huggingface://TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf

# Add MistralLite
sudo ./add-model.sh mistral-7b-lite huggingface://TheBloke/Mistral-7B-Instruct-v0.2-GGUF/mistral-7b-instruct-v0.2.Q4_K_M.gguf
```

After adding a model, restart LocalAI:

```bash
docker-compose restart localai
```

### Model Configuration Structure

Each model has a YAML configuration file in `/opt/localai/config/`. Here's what a typical configuration looks like:

```yaml
name: phi-2-q4
backend: llama-cpp
parameters:
  model: /models/phi-2-q4.gguf
  context_size: 2048
  threads: 4
  f16: true
template:
  chat:
    template: |
      <s>{{- if .System }}
      {{.System}}
      {{- end }}
      {{- range $i, $message := .Messages }}
      {{- if eq $message.Role "user" }}
      [INST] {{ $message.Content }} [/INST]
      {{- else if eq $message.Role "assistant" }}
      {{ $message.Content }}
      {{- end }}
      {{- end }}
```

You can modify these configuration files to:
- Change `context_size` (memory usage/token limit)
- Adjust `threads` (CPU allocation)
- Customize prompt templates

After any configuration change, restart LocalAI:

```bash
cd /opt/localai
docker-compose restart localai
```

### Model Resources and Performance

The download script automatically uses 4-bit quantized models for optimal balance between performance and resource usage. For each model:

| Model | RAM Usage | CPU Usage | Response Speed |
|-------|-----------|-----------|----------------|
| phi-2-q4 | ~2GB | Low | Fast |
| orca-mini-3b-q4 | ~4GB | Medium | Medium |
| llama-3.2-1b | ~2GB | Low | Fast |

For better reasoning at the cost of more resources, consider adding:
- `llama-3.2-8b-instruct` (~8-12GB RAM)
- `mixtral-8x7b-instruct-q4` (~16-20GB RAM)

## Load Balancing and Scaling

LocalAI supports multiple approaches for load balancing and scaling:

### 1. Single-Server Multi-Model

By default, the installation serves multiple models from a single server. The resource allocation is managed dynamically based on which model is currently in use. Models are loaded and unloaded from memory as needed.

### 2. Worker Mode for Large Models

For very large models, LocalAI supports worker mode where model weights are distributed across multiple processes:

```bash
# Start a new worker for model sharding
sudo docker run -d --name localai-worker \
  --network host \
  -v /opt/localai/models:/models \
  localai/localai:v2.12.0-cpu \
  local-ai worker llama-cpp-rpc --llama-cpp-args="-m 4096"

# Configure main LocalAI to use the worker
echo "LLAMACPP_GRPC_SERVERS=localhost:34371" >> /opt/localai/.env
docker-compose restart localai
```

This is particularly useful for models >13B parameters.

### 3. Federated Mode for Multiple Instances

For true distributed inference across multiple servers, use federated mode:

```bash
# On the main server, generate a token
TOKEN=$(docker-compose exec localai local-ai federated --generate-token)

# On worker servers, join the network
sudo docker run -d --name localai-worker \
  --network host \
  -v /opt/localai/models:/models \
  -e TOKEN=$TOKEN \
  localai/localai:v2.12.0-cpu \
  local-ai worker p2p-llama-cpp-rpc
```

This allows for load distribution across multiple machines.

## Security Considerations

The installation implements several security best practices:

- **API Authentication**: A random API key is generated and required for all requests
- **Container Hardening**: Containers run with minimal privileges and resource limits
- **Secure Updates**: The update script includes version checking and backups
- **Input Validation**: Model names are validated to prevent injection attacks

For additional security in production:

1. **Configure HTTPS/TLS**: Enable TLS in the .env file and configure your domain
   ```
   ENABLE_TLS=true
   DOMAIN_NAME=your-domain.com
   ```

2. **Network Isolation**: Consider using a dedicated network for LocalAI
   ```
   docker network create localai-net
   # Update docker-compose.yml to use this network
   ```

3. **Regular Updates**: Run the update script periodically to get security patches
   ```
   cd /opt/localai && ./update.sh
   ```

## Troubleshooting

### Model Loading Issues

If a model fails to load:

1. Check model configuration in `/opt/localai/config/`
2. Verify model file exists in `/opt/localai/models/`
3. Check logs for memory issues:
   ```bash
   docker-compose logs -f localai | grep "memory"
   ```

### API Connection Problems

If you can't connect to the API:

1. Verify LocalAI is running: `docker-compose ps`
2. Check the API key in your requests against the `.env` file
3. Inspect network settings: `docker-compose logs localai | grep "listening"`

### Performance Issues

If models are responding slowly:

1. Increase `threads` parameter in the model configuration
2. Consider reducing `context_size` if memory is limited
3. Monitor resource usage with `docker stats`
4. Try a smaller model or more quantized version (Q3_K_M vs Q5_K_M)

For persistent issues, check the logs:
```bash
cd /opt/localai
docker-compose logs -f
```
