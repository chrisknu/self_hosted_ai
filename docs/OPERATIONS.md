# LocalAI Operations Guide

This document provides practical day-to-day operations procedures for managing your LocalAI deployment.

## Quick Reference

| Task | Command |
|------|---------|
| Check status | `cd /opt/localai && docker-compose ps` |
| View logs | `cd /opt/localai && docker-compose logs -f` |
| Start services | `cd /opt/localai && docker-compose up -d` |
| Stop services | `cd /opt/localai && docker-compose down` |
| Restart services | `cd /opt/localai && docker-compose restart` |
| Add a model | `cd /opt/localai && sudo ./add-model.sh model_name model_url` |
| Update LocalAI | `cd /opt/localai && sudo ./update.sh` |
| Get API key | `grep API_KEY /opt/localai/.env | cut -d= -f2` |

## Common Tasks

### Test Model Response

```bash
API_KEY=$(grep API_KEY /opt/localai/.env | cut -d= -f2)

curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{
    "model": "phi-2-q4",
    "messages": [
      {
        "role": "user",
        "content": "Write a short poem about AI"
      }
    ],
    "temperature": 0.7
  }'
```

### Get Available Models

```bash
curl http://localhost:8080/models \
  -H "Authorization: Bearer $API_KEY"
```

### Monitor Resource Usage

```bash
# View container stats
docker stats localai

# Check disk space
df -h /opt/localai
```

### Backup Configuration

```bash
# Create backup directory
mkdir -p /backup/localai/$(date +%Y%m%d)

# Backup configurations
cp -r /opt/localai/config /backup/localai/$(date +%Y%m%d)/
cp /opt/localai/.env /backup/localai/$(date +%Y%m%d)/
cp /opt/localai/docker-compose.yml /backup/localai/$(date +%Y%m%d)/
```

## Model Management 

### Recommended Models for Different Use Cases

| Use Case | Recommended Model | URL for add-model.sh |
|----------|-------------------|----------------------|
| General purpose (low resources) | phi-2-q4 | huggingface://TheBloke/phi-2-GGUF/phi-2.Q4_K_M.gguf |
| Text generation | llama-3.2-1b-instruct | llama-3.2-1b-instruct:q4_k_m |
| Code generation | codellama-7b | huggingface://TheBloke/CodeLlama-7B-Instruct-GGUF/codellama-7b-instruct.Q4_K_M.gguf |
| Reasoning | mixtral-8x7b-instruct | huggingface://TheBloke/Mixtral-8x7B-Instruct-v0.1-GGUF/mixtral-8x7b-instruct-v0.1.Q4_K_M.gguf |

### Modifying Model Parameters

Edit the model's YAML configuration file to adjust parameters:

```bash
# Edit phi-2 model configuration
sudo nano /opt/localai/config/phi-2-q4.yaml
```

Key parameters to consider adjusting:

- `context_size`: Increase for longer conversations (costs more memory)
- `threads`: Increase for faster inference (uses more CPU)
- `f16`: Set to false to use more memory but higher accuracy

After editing, restart LocalAI:

```bash
cd /opt/localai && docker-compose restart localai
```

### Freeing Up Disk Space

Models can consume significant disk space. To remove unused models:

```bash
# List all models
ls -lah /opt/localai/models/

# Remove a model file
sudo rm /opt/localai/models/unused-model.gguf
sudo rm /opt/localai/config/unused-model.yaml

# Restart LocalAI
cd /opt/localai && docker-compose restart localai
```

## Performance Optimization

### Memory Usage Optimization

If you're running multiple models on limited RAM:

1. Use 4-bit quantized models (Q4_K_M)
2. Reduce `context_size` to 1024 or 512 for smaller memory footprint
3. Set appropriate resource limits in docker-compose.yml

### CPU Usage Optimization

For optimal CPU usage:

1. Set `threads` based on your available CPU cores (usually # of cores - 1)
2. Schedule intensive batch tasks during off-hours
3. Consider using the worker mode to distribute load

### API Concurrency

LocalAI handles concurrent requests by default. For heavy usage:

1. Increase the container's CPU allocation in docker-compose.yml
2. Distribute models across multiple instances using federated mode
3. Add a load balancer in front of multiple LocalAI instances

## Integration Examples

### Python Client Example

```python
import requests
import json

# Replace with your actual API key
api_key = "your_api_key_here"

def query_localai(prompt, model="phi-2-q4", temperature=0.7, max_tokens=500):
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}"
    }
    
    payload = {
        "model": model,
        "messages": [
            {"role": "user", "content": prompt}
        ],
        "temperature": temperature,
        "max_tokens": max_tokens
    }
    
    response = requests.post("http://localhost:8080/v1/chat/completions", 
                            headers=headers, 
                            data=json.dumps(payload))
    
    return response.json()

# Example usage
result = query_localai("Explain quantum computing in simple terms")
print(result['choices'][0]['message']['content'])
```

### NodeJS Client Example

```javascript
const axios = require('axios');

// Replace with your actual API key
const apiKey = 'your_api_key_here';

async function queryLocalAI(prompt, model = 'phi-2-q4', temperature = 0.7, maxTokens = 500) {
  try {
    const response = await axios.post('http://localhost:8080/v1/chat/completions', {
      model: model,
      messages: [
        { role: 'user', content: prompt }
      ],
      temperature: temperature,
      max_tokens: maxTokens
    }, {
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`
      }
    });
    
    return response.data;
  } catch (error) {
    console.error('Error querying LocalAI:', error);
    throw error;
  }
}

// Example usage
queryLocalAI('Explain quantum computing in simple terms')
  .then(result => console.log(result.choices[0].message.content))
  .catch(err => console.error(err));
```

## Maintenance Schedule

Recommended maintenance schedule:

| Task | Frequency | Command |
|------|-----------|---------|
| Update LocalAI | Monthly | `cd /opt/localai && sudo ./update.sh` |
| Backup configurations | Monthly | See backup script above |
| Check logs for errors | Weekly | `cd /opt/localai && docker-compose logs --tail=100` |
| Check disk space | Weekly | `df -h /opt/localai` |
| Security audit | Quarterly | Review configs and update API keys |

## Troubleshooting Decision Tree

1. **API Error 401/403**
   - Check API key in request
   - Verify API key in `.env` file
   - Restart LocalAI

2. **API Error 404**
   - Check model name spelling
   - Verify model exists in `/models` directory
   - Check model configuration in `/config` directory

3. **Model Loading Failure**
   - Check logs: `docker-compose logs -f localai`
   - Verify memory availability: `free -h`
   - Try redownloading the model
   - Try a smaller or more quantized model

4. **Slow Response Times**
   - Check CPU usage: `top`
   - Verify model is appropriate for hardware
   - Adjust `threads` parameter in model config
   - Check context length in requests
