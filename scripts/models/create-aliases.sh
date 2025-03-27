#!/bin/bash

# Script to create common OpenAI API-compatible model aliases for LocalAI
# This script will create configuration files that map OpenAI model names to your local models

set -e

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
NC='\033[0m' # No Color

# Print with colors
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Configuration
LOCALAI_DIR="/opt/localai"
CONFIG_DIR="$LOCALAI_DIR/config"
MODELS_DIR="$LOCALAI_DIR/models"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  error "Please run as root or with sudo"
fi

# Check if LocalAI installation exists
if [ ! -d "$CONFIG_DIR" ]; then
  error "LocalAI configuration directory not found at $CONFIG_DIR. Make sure LocalAI is installed."
fi

# Get list of available models
echo "Available models:"
echo "-----------------"
ls -1 "$CONFIG_DIR" | grep ".yaml" | sed 's/.yaml$//'
echo ""

# Interactive model selection
read -p "Enter model name for 'gpt-3.5-turbo' alias (small model, fast responses): " GPT35_MODEL
read -p "Enter model name for 'gpt-4' alias (your largest/most capable model): " GPT4_MODEL
read -p "Enter model name for 'text-embedding-ada-002' alias (optional, press Enter to skip): " EMBEDDING_MODEL

# Create gpt-3.5-turbo alias
if [ -n "$GPT35_MODEL" ]; then
  info "Creating gpt-3.5-turbo alias pointing to $GPT35_MODEL..."
  
  # Get source model config to copy parameters
  if [ ! -f "$CONFIG_DIR/${GPT35_MODEL}.yaml" ]; then
    warn "Source model configuration not found. Creating basic configuration."
    MODEL_FILE=$(ls "$MODELS_DIR" | grep -m 1 "${GPT35_MODEL}" || echo "")
    
    if [ -z "$MODEL_FILE" ]; then
      error "Could not find a model file for ${GPT35_MODEL}. Make sure the model exists."
    fi
    
    cat > "$CONFIG_DIR/gpt-3.5-turbo.yaml" << EOL
name: gpt-3.5-turbo
backend: llama-cpp
parameters:
  model: /models/${MODEL_FILE}
  context_size: 2048
  threads: 4
  f16: true
template:
  chat:
    template: |
      <s>{{- if .System }}
      {{.System}}
      {{- end }}
      {{- range \$i, \$message := .Messages }}
      {{- if eq \$message.Role "user" }}
      [INST] {{ \$message.Content }} [/INST]
      {{- else if eq \$message.Role "assistant" }}
      {{ \$message.Content }}
      {{- end }}
      {{- end }}
EOL
  else
    # Read parameters from source model
    SOURCE_MODEL_FILE=$(grep -A 2 "model:" "$CONFIG_DIR/${GPT35_MODEL}.yaml" | grep -oP "/models/\\K[^\"]*")
    CONTEXT_SIZE=$(grep -A 5 "parameters:" "$CONFIG_DIR/${GPT35_MODEL}.yaml" | grep "context_size" | grep -oP "\\d+")
    THREADS=$(grep -A 5 "parameters:" "$CONFIG_DIR/${GPT35_MODEL}.yaml" | grep "threads" | grep -oP "\\d+")
    F16=$(grep -A 5 "parameters:" "$CONFIG_DIR/${GPT35_MODEL}.yaml" | grep "f16" | grep -oP "(true|false)")
    
    # Create config using source model parameters
    cat > "$CONFIG_DIR/gpt-3.5-turbo.yaml" << EOL
name: gpt-3.5-turbo
backend: llama-cpp
parameters:
  model: /models/${SOURCE_MODEL_FILE}
  context_size: ${CONTEXT_SIZE:-2048}
  threads: ${THREADS:-4}
  f16: ${F16:-true}
EOL

    # Copy template if it exists
    if grep -q "template:" "$CONFIG_DIR/${GPT35_MODEL}.yaml"; then
      sed -n '/template:/,/^[a-z]/p' "$CONFIG_DIR/${GPT35_MODEL}.yaml" | sed '$d' >> "$CONFIG_DIR/gpt-3.5-turbo.yaml"
    else
      cat >> "$CONFIG_DIR/gpt-3.5-turbo.yaml" << EOL
template:
  chat:
    template: |
      <s>{{- if .System }}
      {{.System}}
      {{- end }}
      {{- range \$i, \$message := .Messages }}
      {{- if eq \$message.Role "user" }}
      [INST] {{ \$message.Content }} [/INST]
      {{- else if eq \$message.Role "assistant" }}
      {{ \$message.Content }}
      {{- end }}
      {{- end }}
EOL
    fi
  fi
  
  success "Created gpt-3.5-turbo alias!"
fi

# Create gpt-4 alias
if [ -n "$GPT4_MODEL" ]; then
  info "Creating gpt-4 alias pointing to $GPT4_MODEL..."
  
  # Get source model config to copy parameters
  if [ ! -f "$CONFIG_DIR/${GPT4_MODEL}.yaml" ]; then
    warn "Source model configuration not found. Creating basic configuration."
    MODEL_FILE=$(ls "$MODELS_DIR" | grep -m 1 "${GPT4_MODEL}" || echo "")
    
    if [ -z "$MODEL_FILE" ]; then
      error "Could not find a model file for ${GPT4_MODEL}. Make sure the model exists."
    fi
    
    cat > "$CONFIG_DIR/gpt-4.yaml" << EOL
name: gpt-4
backend: llama-cpp
parameters:
  model: /models/${MODEL_FILE}
  context_size: 4096
  threads: 8
  f16: true
template:
  chat:
    template: |
      <s>{{- if .System }}
      {{.System}}
      {{- end }}
      {{- range \$i, \$message := .Messages }}
      {{- if eq \$message.Role "user" }}
      [INST] {{ \$message.Content }} [/INST]
      {{- else if eq \$message.Role "assistant" }}
      {{ \$message.Content }}
      {{- end }}
      {{- end }}
EOL
  else
    # Read parameters from source model
    SOURCE_MODEL_FILE=$(grep -A 2 "model:" "$CONFIG_DIR/${GPT4_MODEL}.yaml" | grep -oP "/models/\\K[^\"]*")
    CONTEXT_SIZE=$(grep -A 5 "parameters:" "$CONFIG_DIR/${GPT4_MODEL}.yaml" | grep "context_size" | grep -oP "\\d+")
    THREADS=$(grep -A 5 "parameters:" "$CONFIG_DIR/${GPT4_MODEL}.yaml" | grep "threads" | grep -oP "\\d+")
    F16=$(grep -A 5 "parameters:" "$CONFIG_DIR/${GPT4_MODEL}.yaml" | grep "f16" | grep -oP "(true|false)")
    
    # Create config using source model parameters
    cat > "$CONFIG_DIR/gpt-4.yaml" << EOL
name: gpt-4
backend: llama-cpp
parameters:
  model: /models/${SOURCE_MODEL_FILE}
  context_size: ${CONTEXT_SIZE:-4096}
  threads: ${THREADS:-8}
  f16: ${F16:-true}
EOL

    # Copy template if it exists
    if grep -q "template:" "$CONFIG_DIR/${GPT4_MODEL}.yaml"; then
      sed -n '/template:/,/^[a-z]/p' "$CONFIG_DIR/${GPT4_MODEL}.yaml" | sed '$d' >> "$CONFIG_DIR/gpt-4.yaml"
    else
      cat >> "$CONFIG_DIR/gpt-4.yaml" << EOL
template:
  chat:
    template: |
      <s>{{- if .System }}
      {{.System}}
      {{- end }}
      {{- range \$i, \$message := .Messages }}
      {{- if eq \$message.Role "user" }}
      [INST] {{ \$message.Content }} [/INST]
      {{- else if eq \$message.Role "assistant" }}
      {{ \$message.Content }}
      {{- end }}
      {{- end }}
EOL
    fi
  fi
  
  success "Created gpt-4 alias!"
fi

# Create text-embedding-ada-002 alias (if provided)
if [ -n "$EMBEDDING_MODEL" ]; then
  info "Creating text-embedding-ada-002 alias pointing to $EMBEDDING_MODEL..."
  
  # Get source model config to copy parameters
  if [ ! -f "$CONFIG_DIR/${EMBEDDING_MODEL}.yaml" ]; then
    warn "Source model configuration not found. Creating basic configuration."
    MODEL_FILE=$(ls "$MODELS_DIR" | grep -m 1 "${EMBEDDING_MODEL}" || echo "")
    
    if [ -z "$MODEL_FILE" ]; then
      error "Could not find a model file for ${EMBEDDING_MODEL}. Make sure the model exists."
    fi
    
    cat > "$CONFIG_DIR/text-embedding-ada-002.yaml" << EOL
name: text-embedding-ada-002
backend: llama-cpp
parameters:
  model: /models/${MODEL_FILE}
  context_size: 512
  threads: 4
  f16: true
  embeddings: true
EOL
  else
    # Read parameters from source model
    SOURCE_MODEL_FILE=$(grep -A 2 "model:" "$CONFIG_DIR/${EMBEDDING_MODEL}.yaml" | grep -oP "/models/\\K[^\"]*")
    CONTEXT_SIZE=$(grep -A 5 "parameters:" "$CONFIG_DIR/${EMBEDDING_MODEL}.yaml" | grep "context_size" | grep -oP "\\d+")
    THREADS=$(grep -A 5 "parameters:" "$CONFIG_DIR/${EMBEDDING_MODEL}.yaml" | grep "threads" | grep -oP "\\d+")
    F16=$(grep -A 5 "parameters:" "$CONFIG_DIR/${EMBEDDING_MODEL}.yaml" | grep "f16" | grep -oP "(true|false)")
    
    # Create config using source model parameters
    cat > "$CONFIG_DIR/text-embedding-ada-002.yaml" << EOL
name: text-embedding-ada-002
backend: llama-cpp
parameters:
  model: /models/${SOURCE_MODEL_FILE}
  context_size: ${CONTEXT_SIZE:-512}
  threads: ${THREADS:-4}
  f16: ${F16:-true}
  embeddings: true
EOL
  fi
  
  success "Created text-embedding-ada-002 alias!"
fi

# Create additional aliases for other OpenAI models (you can expand this list)
info "Creating additional OpenAI-compatible aliases..."

# gpt-3.5-turbo-0613 points to the same model as gpt-3.5-turbo
if [ -f "$CONFIG_DIR/gpt-3.5-turbo.yaml" ]; then
  cp "$CONFIG_DIR/gpt-3.5-turbo.yaml" "$CONFIG_DIR/gpt-3.5-turbo-0613.yaml"
  sed -i 's/name: gpt-3.5-turbo/name: gpt-3.5-turbo-0613/' "$CONFIG_DIR/gpt-3.5-turbo-0613.yaml"
  success "Created gpt-3.5-turbo-0613 alias"
fi

# gpt-4-0613 points to the same model as gpt-4
if [ -f "$CONFIG_DIR/gpt-4.yaml" ]; then
  cp "$CONFIG_DIR/gpt-4.yaml" "$CONFIG_DIR/gpt-4-0613.yaml"
  sed -i 's/name: gpt-4/name: gpt-4-0613/' "$CONFIG_DIR/gpt-4-0613.yaml"
  success "Created gpt-4-0613 alias"
fi

echo ""
info "Restarting LocalAI to apply changes..."
cd "$LOCALAI_DIR" && docker-compose restart localai

success "Model aliases created successfully!"
echo ""
echo "You can now use these OpenAI-compatible model names in your API calls:"
if [ -n "$GPT35_MODEL" ]; then echo "- gpt-3.5-turbo -> points to $GPT35_MODEL"; fi
if [ -n "$GPT35_MODEL" ]; then echo "- gpt-3.5-turbo-0613 -> points to $GPT35_MODEL"; fi
if [ -n "$GPT4_MODEL" ]; then echo "- gpt-4 -> points to $GPT4_MODEL"; fi
if [ -n "$GPT4_MODEL" ]; then echo "- gpt-4-0613 -> points to $GPT4_MODEL"; fi
if [ -n "$EMBEDDING_MODEL" ]; then echo "- text-embedding-ada-002 -> points to $EMBEDDING_MODEL"; fi
echo ""
echo "Example usage:"
echo "curl http://localhost:8080/v1/chat/completions \\"
echo "  -H \"Content-Type: application/json\" \\"
echo "  -H \"Authorization: Bearer \$API_KEY\" \\"
echo "  -d '{"
echo "    \"model\": \"gpt-3.5-turbo\","
echo "    \"messages\": [{\"role\": \"user\", \"content\": \"Hello\"}]"
echo "  }'"
