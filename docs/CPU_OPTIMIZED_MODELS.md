# Guide to CPU-Optimized Models for LocalAI

This guide explains how to find, download, and optimize models for CPU-based LocalAI deployments.

## Understanding Model Quantization for CPU Performance

When running LLMs on CPU-only environments, model quantization is critical for performance. Quantization reduces the precision of the model weights (from 16-bit or 32-bit floating point to lower precision formats), which dramatically improves inference speed and reduces memory usage.

## How to Identify CPU-Optimized Models

### Quantization Formats to Look For

When searching for models, look for these quantizations (from most efficient to highest quality):

1. **Q2_K** - 2-bit quantization, fastest but lower quality
2. **Q3_K_M** - 3-bit quantization, good balance for very small models
3. **Q4_K_M** - 4-bit quantization, recommended for most CPU deployments
4. **Q5_K_M** - 5-bit quantization, better quality but slower
5. **Q6_K** - 6-bit quantization, high quality but significantly slower
8. **Q8_0** - 8-bit quantization, highest quality but much slower on CPU

For most CPU deployments, **Q4_K_M** offers the best balance between quality and performance.

### Model Size Considerations

Smaller models run much more efficiently on CPU:
- **1B-3B parameter models**: Good performance on most CPUs (phi-2, TinyLlama)
- **7B parameter models**: Acceptable with good CPU (Mistral 7B, Llama 3.1 8B)
- **>13B parameter models**: Generally too slow for real-time use on consumer CPUs

## Finding CPU-Optimized Models

### HuggingFace's TheBloke Repository

Most CPU-optimized models can be found in TheBloke's repository on HuggingFace. Use this pattern when downloading:

```
huggingface://TheBloke/[MODEL-NAME]-GGUF/[model-name].Q4_K_M.gguf
```

### Recommended CPU-Optimized Models

| Model | Parameters | URL for LocalAI |
|-------|------------|-----------------|
| Phi-2 | 2.7B | `huggingface://TheBloke/phi-2-GGUF/phi-2.Q4_K_M.gguf` |
| TinyLlama | 1.1B | `huggingface://TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf` |
| StableLM-2 | 1.6B | `huggingface://TheBloke/StableLM-2-1.6B-GGUF/stablelm-2-1.6b.Q4_K_M.gguf` |
| Llama-3.1-1B | 1B | `huggingface://TheBloke/Llama-3.1-1B-GGUF/llama-3.1-1b.Q4_K_M.gguf` |
| Llama-3.1-8B | 8B | `huggingface://TheBloke/Llama-3.1-8B-Instruct-GGUF/llama-3.1-8b-instruct.Q4_K_M.gguf` |
| Mistral-7B | 7B | `huggingface://TheBloke/Mistral-7B-Instruct-v0.2-GGUF/mistral-7b-instruct-v0.2.Q4_K_M.gguf` |
| Orca-Mini-3B | 3B | `huggingface://TheBloke/orca_mini_3B-GGUF/orca-mini-3b.Q4_K_M.gguf` |

## Using the Model Downloader Script

The provided `add-model.sh` script in LocalAI handles downloading models:

```bash
cd /opt/localai
sudo ./add-model.sh model_name_alias huggingface://TheBloke/MODEL-REPO-NAME/model-file.Q4_K_M.gguf
```

For example:
```bash
sudo ./add-model.sh tiny-llama huggingface://TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf
```

## Custom CPU Optimization in LocalAI

For additional CPU performance, you can modify model YAML configuration:

```yaml
name: model-name
backend: llama-cpp
parameters:
  model: /models/your-model.gguf
  
  # CPU Performance Optimizations
  context_size: 2048           # Lower is faster (512, 1024, 2048)
  threads: 4                   # Match to your CPU core count
  batch_size: 512              # Increase for bulk processing
  f16: true                    # Use half-precision (faster)
  
  # When using with federated inference
  parallel_processes: 2        # For multi-process inference
```

## Creating an Automated CPU-Optimized Model Downloader

Here's a script to automate downloading a curated set of CPU-optimized models:

```bash
#!/bin/bash
# Script: download-cpu-optimized-models.sh

# Configuration
LOCALAI_DIR="/opt/localai"
MODELS=(
  "phi-2:huggingface://TheBloke/phi-2-GGUF/phi-2.Q4_K_M.gguf"
  "tinyllama:huggingface://TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf"
  "orca-mini:huggingface://TheBloke/orca_mini_3B-GGUF/orca-mini-3b.Q4_K_M.gguf"
  "mistral-7b:huggingface://TheBloke/Mistral-7B-Instruct-v0.2-GGUF/mistral-7b-instruct-v0.2.Q4_K_M.gguf"
)

# Add each model
cd $LOCALAI_DIR
for model_entry in "${MODELS[@]}"; do
  model_name=$(echo $model_entry | cut -d: -f1)
  model_url=$(echo $model_entry | cut -d: -f2-)
  
  echo "Downloading $model_name from $model_url"
  sudo ./add-model.sh $model_name $model_url
done

# Restart LocalAI
sudo docker-compose restart localai

echo "CPU-optimized models downloaded and configured!"
```

Save this as `/opt/localai/download-cpu-optimized-models.sh` and make it executable:
```bash
chmod +x /opt/localai/download-cpu-optimized-models.sh
```

## Testing Model Performance on Your CPU

After downloading models, benchmark them to see which performs best on your specific CPU:

```bash
API_KEY=$(grep API_KEY /opt/localai/.env | cut -d= -f2)

# Time command measures execution time
time curl -s http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{
    "model": "phi-2",
    "messages": [
      {"role": "user", "content": "Write a short paragraph about CPU optimization."}
    ],
    "temperature": 0.7,
    "max_tokens": 100
  }'
```

Run this for each model to compare performance. Look for:
1. Total execution time
2. Tokens per second (shown in LocalAI logs)

## Advanced CPU Optimization Techniques

For production deployments that need maximum CPU performance:

1. **Compile LocalAI with CPU optimizations**:
   ```bash
   git clone https://github.com/mudler/LocalAI
   cd LocalAI
   make build-cpu ARGS="-DLLAMA_F16C=on -DLLAMA_AVX=on -DLLAMA_AVX2=on -DLLAMA_FMA=on"
   ```

2. **Use distilled models** - Models specifically distilled (teacher-student training) for smaller size and faster inference:
   - Microsoft's Phi-2 (2.7B)
   - Google's Gemma (2B)
   - TinyLlama (1.1B)

3. **Enable kernel optimizations**:
   - For Intel CPUs: Use Intel oneDNN library
   - For AMD CPUs: Use ROCm acceleration

## Troubleshooting Common Issues

1. **Model loads but inference is extremely slow**:
   - Try a more aggressive quantization (Q3_K_M or Q2_K)
   - Reduce context_size in model configuration
   - Check if you're running other memory-intensive processes

2. **Out of memory errors**:
   - Use a smaller model (e.g., switch from 7B to 3B parameters)
   - Try a more aggressive quantization format
   - Reduce context_size in model configuration

3. **Poor quality responses with fast models**:
   - Consider a higher quantization (Q5_K_M instead of Q4_K_M)
   - Increase tokens per request (may be slower but better quality)
   - Try a slightly larger model with a good quantization
