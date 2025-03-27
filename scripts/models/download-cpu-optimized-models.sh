#!/bin/bash
# Script to download a curated set of CPU-optimized models for LocalAI

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

# Detect system architecture and set appropriate image tag
detect_architecture() {
  info "Detecting system architecture..."
  
  # Get architecture using uname
  ARCH=$(uname -m)
  
  # Set the appropriate image tag based on architecture
  case "$ARCH" in
    x86_64)
      LOCALAI_IMAGE="localai/localai:latest-aio-cpu"
      info "Detected x86_64 architecture, using $LOCALAI_IMAGE"
      ;;
    aarch64|arm64)
      LOCALAI_IMAGE="localai/localai:latest-aio-cpu-arm64"
      info "Detected ARM64 architecture, using $LOCALAI_IMAGE"
      
      # Fallback plan if ARM64 image doesn't exist
      if ! docker pull "$LOCALAI_IMAGE" &>/dev/null; then
        warn "ARM64-specific image not found. Trying to use platform specification instead."
        LOCALAI_IMAGE="localai/localai:latest-aio-cpu"
        PLATFORM_ARGS="--platform linux/arm64"
        
        # Install QEMU for emulation if ARM64-specific image not found
        info "Installing QEMU for architecture emulation..."
        apt-get update && apt-get install -y qemu-user-static
        docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
        
        info "Using $LOCALAI_IMAGE with platform specification and emulation"
      fi
      ;;
    *)
      warn "Unknown architecture: $ARCH, defaulting to amd64 image"
      LOCALAI_IMAGE="localai/localai:latest-aio-cpu"
      ;;
  esac
  
  # Set default platform args if not set
  PLATFORM_ARGS=${PLATFORM_ARGS:-""}
  
  success "Architecture detection complete"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  error "Please run as root or with sudo"
fi

# Configuration
LOCALAI_DIR="/opt/localai"
MODELS_DIR="$LOCALAI_DIR/models"
CONFIG_DIR="$LOCALAI_DIR/config"

# Check if LocalAI is installed
if [ ! -d "$LOCALAI_DIR" ]; then
  error "LocalAI directory not found at $LOCALAI_DIR. Please install LocalAI first."
fi

# Define CPU-optimized models
# Format: "name:url:description:size_in_MB"
MODELS=(
  "phi-2-q4:huggingface://TheBloke/phi-2-GGUF/phi-2.Q4_K_M.gguf:Microsoft's Phi-2 2.7B parameter model (general purpose):1400"
  "tinyllama-1.1b:huggingface://TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf:Small 1.1B parameter model good for basic tasks:560"
  "orca-mini-3b-q4:huggingface://TheBloke/orca_mini_3B-GGUF/orca-mini-3b.Q4_K_M.gguf:3B parameter model with good reasoning:1500"
  "stablelm-2-1.6b:huggingface://TheBloke/StableLM-2-1.6B-GGUF/stablelm-2-1.6b.Q4_K_M.gguf:Stability AI's 1.6B parameter model:750"
)

# Larger models (optional - commented out by default)
LARGE_MODELS=(
  "llama-3.1-8b-instruct:huggingface://TheBloke/Llama-3.1-8B-Instruct-GGUF/llama-3.1-8b-instruct.Q4_K_M.gguf:Meta's Llama 3.1 8B instruction model - high quality but needs good CPU:4200"
  "mistral-7b-instruct:huggingface://TheBloke/Mistral-7B-Instruct-v0.2-GGUF/mistral-7b-instruct-v0.2.Q4_K_M.gguf:Mistral AI's 7B instruction model - high quality but needs good CPU:3800"
  "gemma-2b-instruct:huggingface://TheBloke/Gemma-2b-it-GGUF/gemma-2b-it.Q4_K_M.gguf:Google's Gemma 2B instruction model:1200"
)

# Check available disk space
AVAILABLE_SPACE=$(df -BM --output=avail "$LOCALAI_DIR" | tail -n 1 | tr -d 'M')
REQUIRED_SPACE=0

# Calculate required space
for model_entry in "${MODELS[@]}"; do
  model_size=$(echo $model_entry | cut -d: -f4)
  REQUIRED_SPACE=$((REQUIRED_SPACE + model_size))
done

# Add a 20% buffer
REQUIRED_SPACE=$((REQUIRED_SPACE * 12 / 10))

if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
  warn "Warning: You may not have enough disk space."
  warn "Required: ${REQUIRED_SPACE}MB, Available: ${AVAILABLE_SPACE}MB"
  read -p "Do you want to continue anyway? (y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

# Display menu
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}   CPU-Optimized Models Downloader      ${NC}"
echo -e "${GREEN}=========================================${NC}"
echo
echo "This script will download the following CPU-optimized models:"
echo

# List models
index=1
for model_entry in "${MODELS[@]}"; do
  model_name=$(echo $model_entry | cut -d: -f1)
  model_description=$(echo $model_entry | cut -d: -f3)
  model_size=$(echo $model_entry | cut -d: -f4)
  echo -e "${BLUE}$index. ${NC}$model_name - $model_description (${model_size}MB)"
  index=$((index + 1))
done

echo
echo -e "${YELLOW}Optional larger models (require more CPU power)${NC}"

# List large models
for model_entry in "${LARGE_MODELS[@]}"; do
  model_name=$(echo $model_entry | cut -d: -f1)
  model_description=$(echo $model_entry | cut -d: -f3)
  model_size=$(echo $model_entry | cut -d: -f4)
  echo -e "${BLUE}$index. ${NC}$model_name - $model_description (${model_size}MB)"
  index=$((index + 1))
done

echo
echo -e "${YELLOW}Note:${NC} Q4_K_M quantization is used for all models as it offers the best"
echo "balance between performance and quality for CPU inference."
echo

# Ask for confirmation
read -p "Do you want to download the recommended CPU-optimized models? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  exit 1
fi

# Ask about large models
read -p "Do you also want to download the larger models (requires better CPU)? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  DOWNLOAD_LARGE=true
else
  DOWNLOAD_LARGE=false
fi

# Detect system architecture
detect_architecture

# Download models
info "Starting download of CPU-optimized models..."
cd "$LOCALAI_DIR"

for model_entry in "${MODELS[@]}"; do
  model_name=$(echo $model_entry | cut -d: -f1)
  model_url=$(echo $model_entry | cut -d: -f2)
  
  info "Downloading $model_name from $model_url"
  
  # Use secure Docker run command with appropriate limitations
  if ! docker run --rm \
    --security-opt no-new-privileges=true \
    --cap-drop ALL \
    $PLATFORM_ARGS \
    -v "$MODELS_DIR:/models" \
    $LOCALAI_IMAGE \
    local-ai run "$model_url" --models-path=/models --model-name="$model_name.gguf"; then
    
    warn "Failed to download $model_name, but continuing with other models"
  else
    success "Downloaded $model_name successfully"
    
    # Create configuration YAML if it doesn't exist
    if [ ! -f "$CONFIG_DIR/$model_name.yaml" ]; then
      info "Creating configuration for $model_name"
      
      # Determine appropriate thread count based on CPU cores
      CPU_CORES=$(grep -c ^processor /proc/cpuinfo)
      RECOMMENDED_THREADS=$((CPU_CORES / 2))
      if [ "$RECOMMENDED_THREADS" -lt 2 ]; then
        RECOMMENDED_THREADS=2
      elif [ "$RECOMMENDED_THREADS" -gt 8 ]; then
        RECOMMENDED_THREADS=8
      fi
      
      cat > "$CONFIG_DIR/$model_name.yaml" << EOL
name: $model_name
backend: llama-cpp
parameters:
  model: /models/$model_name.gguf
  context_size: 2048
  threads: $RECOMMENDED_THREADS
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
      success "Created configuration for $model_name"
    fi
  fi
done

# Download large models if requested
if [ "$DOWNLOAD_LARGE" = true ]; then
  info "Downloading larger models..."
  
  for model_entry in "${LARGE_MODELS[@]}"; do
    model_name=$(echo $model_entry | cut -d: -f1)
    model_url=$(echo $model_entry | cut -d: -f2)
    
    info "Downloading $model_name from $model_url"
    
    # Use secure Docker run command with appropriate limitations
    if ! docker run --rm \
      --security-opt no-new-privileges=true \
      --cap-drop ALL \
      $PLATFORM_ARGS \
      -v "$MODELS_DIR:/models" \
      $LOCALAI_IMAGE \
      local-ai run "$model_url" --models-path=/models --model-name="$model_name.gguf"; then
      
      warn "Failed to download $model_name, but continuing with other models"
    else
      success "Downloaded $model_name successfully"
      
      # Create configuration YAML if it doesn't exist
      if [ ! -f "$CONFIG_DIR/$model_name.yaml" ]; then
        info "Creating configuration for $model_name"
        
        # Larger models need more threads
        CPU_CORES=$(grep -c ^processor /proc/cpuinfo)
        RECOMMENDED_THREADS=$((CPU_CORES - 2))
        if [ "$RECOMMENDED_THREADS" -lt 4 ]; then
          RECOMMENDED_THREADS=4
        elif [ "$RECOMMENDED_THREADS" -gt 12 ]; then
          RECOMMENDED_THREADS=12
        fi
        
        cat > "$CONFIG_DIR/$model_name.yaml" << EOL
name: $model_name
backend: llama-cpp
parameters:
  model: /models/$model_name.gguf
  context_size: 4096
  threads: $RECOMMENDED_THREADS
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
        success "Created configuration for $model_name"
      fi
    fi
  done
fi

# Create useful aliases
info "Creating OpenAI-compatible aliases..."

# Map to gpt-3.5-turbo (using a smaller/faster model)
if [ -f "$CONFIG_DIR/phi-2-q4.yaml" ]; then
  cp "$CONFIG_DIR/phi-2-q4.yaml" "$CONFIG_DIR/gpt-3.5-turbo.yaml"
  sed -i 's/name: phi-2-q4/name: gpt-3.5-turbo/' "$CONFIG_DIR/gpt-3.5-turbo.yaml"
  success "Created gpt-3.5-turbo alias (mapped to phi-2-q4)"
elif [ -f "$CONFIG_DIR/tinyllama-1.1b.yaml" ]; then
  cp "$CONFIG_DIR/tinyllama-1.1b.yaml" "$CONFIG_DIR/gpt-3.5-turbo.yaml"
  sed -i 's/name: tinyllama-1.1b/name: gpt-3.5-turbo/' "$CONFIG_DIR/gpt-3.5-turbo.yaml"
  success "Created gpt-3.5-turbo alias (mapped to tinyllama-1.1b)"
fi

# Map to gpt-4 (using the best model available)
if [ -f "$CONFIG_DIR/llama-3.1-8b-instruct.yaml" ] && [ "$DOWNLOAD_LARGE" = true ]; then
  cp "$CONFIG_DIR/llama-3.1-8b-instruct.yaml" "$CONFIG_DIR/gpt-4.yaml"
  sed -i 's/name: llama-3.1-8b-instruct/name: gpt-4/' "$CONFIG_DIR/gpt-4.yaml"
  success "Created gpt-4 alias (mapped to llama-3.1-8b-instruct)"
elif [ -f "$CONFIG_DIR/mistral-7b-instruct.yaml" ] && [ "$DOWNLOAD_LARGE" = true ]; then
  cp "$CONFIG_DIR/mistral-7b-instruct.yaml" "$CONFIG_DIR/gpt-4.yaml"
  sed -i 's/name: mistral-7b-instruct/name: gpt-4/' "$CONFIG_DIR/gpt-4.yaml"
  success "Created gpt-4 alias (mapped to mistral-7b-instruct)"
elif [ -f "$CONFIG_DIR/orca-mini-3b-q4.yaml" ]; then
  cp "$CONFIG_DIR/orca-mini-3b-q4.yaml" "$CONFIG_DIR/gpt-4.yaml"
  sed -i 's/name: orca-mini-3b-q4/name: gpt-4/' "$CONFIG_DIR/gpt-4.yaml"
  success "Created gpt-4 alias (mapped to orca-mini-3b-q4)"
fi

# Restart LocalAI to apply changes
info "Restarting LocalAI to apply changes..."
docker-compose restart localai

echo
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}   CPU-Optimized Models Downloaded      ${NC}"
echo -e "${GREEN}=========================================${NC}"
echo
echo "The following models are now available:"

# List installed models
ls -1 "$CONFIG_DIR" | grep -v "gpt-" | grep ".yaml" | sed 's/.yaml$//' | sort | while read model; do
  echo "- $model"
done

echo
echo "Aliases created:"
if [ -f "$CONFIG_DIR/gpt-3.5-turbo.yaml" ]; then
  GPT35_SOURCE=$(grep "model:" "$CONFIG_DIR/gpt-3.5-turbo.yaml" | grep -o '[^/]*\.gguf' | sed 's/\.gguf//')
  echo "- gpt-3.5-turbo -> $GPT35_SOURCE"
fi

if [ -f "$CONFIG_DIR/gpt-4.yaml" ]; then
  GPT4_SOURCE=$(grep "model:" "$CONFIG_DIR/gpt-4.yaml" | grep -o '[^/]*\.gguf' | sed 's/\.gguf//')
  echo "- gpt-4 -> $GPT4_SOURCE"
fi

echo
echo "System architecture: $ARCH"
echo "LocalAI image used: $LOCALAI_IMAGE"
echo

echo "You can now use these models with LocalAI. Example:"
echo "curl http://localhost:8080/v1/chat/completions \\"
echo "  -H \"Content-Type: application/json\" \\"
echo "  -H \"Authorization: Bearer \$API_KEY\" \\"
echo "  -d '{\"model\": \"phi-2-q4\", \"messages\": [{\"role\": \"user\", \"content\": \"Hello\"}]}'"
echo
echo "To integrate with OpenAI-compatible clients, use the aliases:"
echo "- gpt-3.5-turbo"
echo "- gpt-4"
echo

success "Setup complete!"
