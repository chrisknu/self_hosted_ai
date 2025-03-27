#!/bin/bash
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
      # Try ARM64-specific image first
      if docker pull "localai/localai:latest-aio-cpu-arm64" &>/dev/null; then
        LOCALAI_IMAGE="localai/localai:latest-aio-cpu-arm64"
        PLATFORM_ARGS=""
        info "Using ARM64-specific image: $LOCALAI_IMAGE"
      else
        # Fall back to standard image with explicit platform flag
        LOCALAI_IMAGE="localai/localai:latest-aio-cpu"
        PLATFORM_ARGS="--platform=linux/amd64"
        info "ARM64-specific image not found. Using standard image with emulation: $LOCALAI_IMAGE"
        info "Setting explicit platform flag: $PLATFORM_ARGS"
      fi
      ;;
    *)
      warn "Unknown architecture: $ARCH, defaulting to amd64 image"
      LOCALAI_IMAGE="localai/localai:latest-aio-cpu"
      ;;
  esac
  
  # For x86_64, default platform args are empty
  if [ "$ARCH" = "x86_64" ]; then
    PLATFORM_ARGS=""
  fi
  success "Architecture detection complete"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  error "Please run as root or with sudo"
fi

# Configuration variables (can be customized)
LOCALAI_DIR="/opt/localai"
MODELS_DIR="$LOCALAI_DIR/models"
CONFIG_DIR="$LOCALAI_DIR/config"
COMPOSE_FILE="$LOCALAI_DIR/docker-compose.yml"
ENV_FILE="$LOCALAI_DIR/.env"
DEFAULT_PORT=8080
CADDY_PORT=80
ENABLE_TLS=false
DOMAIN_NAME="localhost"
DEFAULT_MODEL="llama-3.2-1b-instruct:q4_k_m"
# Generate a random API key if none is specified
API_KEY="$(openssl rand -hex 16)"
ENABLE_OAUTH=false

# Models to download
# Format: "model_name:download_url"
MODELS=(
  "phi-2-q4:huggingface://TheBloke/phi-2-GGUF/phi-2.Q4_K_M.gguf"
  "orca-mini-3b-q4:huggingface://TheBloke/orca_mini_3B-GGUF/orca-mini-3b.Q4_K_M.gguf"
)

print_banner() {
  echo -e "${GREEN}"
  echo "================================================================"
  echo "                LocalAI Deployment Script                        "
  echo "================================================================"
  echo -e "${NC}"
}

check_dependencies() {
  info "Checking for required dependencies..."
  
  # Check for curl
  if ! command -v curl &> /dev/null; then
    info "Installing curl..."
    apt-get update && apt-get install -y curl
  fi

  # Check for Docker with security verification
  if ! command -v docker &> /dev/null; then
    info "Installing Docker..."
    # Download with checksum verification
    curl -fsSL https://get.docker.com -o get-docker.sh
    # Verify script contents (basic check)
    if ! grep -q "docker-ce" get-docker.sh; then
      error "Docker installation script verification failed. Script may have been tampered with."
    fi
    # Install Docker
    sh get-docker.sh
    rm get-docker.sh
  fi

  # Check for Docker Compose
  if ! command -v docker-compose &> /dev/null; then
    info "Installing Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/download/v2.24.6/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
  fi
  
  success "All dependencies installed!"
}

create_directory_structure() {
  info "Creating directory structure..."
  mkdir -p "$MODELS_DIR"
  mkdir -p "$CONFIG_DIR"
  
  # Secure directory permissions
  chmod 750 "$LOCALAI_DIR"
  chmod 750 "$MODELS_DIR"
  chmod 750 "$CONFIG_DIR"
  
  success "Directory structure created at $LOCALAI_DIR"
}

create_docker_compose() {
  info "Creating docker-compose.yml..."
  
  # Set up platform specification for docker-compose if needed
  PLATFORM_SPEC=""
  if [ -n "$PLATFORM_ARGS" ]; then
    # Extract platform value
    PLATFORM_VALUE=$(echo "$PLATFORM_ARGS" | grep -o 'linux/[^ "]*')
    if [ -n "$PLATFORM_VALUE" ]; then
      PLATFORM_SPEC="    platform: $PLATFORM_VALUE"
      info "Adding platform specification to docker-compose.yml: $PLATFORM_VALUE"
    fi
  fi
  
  cat > "$COMPOSE_FILE" << EOL
version: '3.8'

services:
  localai:
    image: ${LOCALAI_IMAGE}
    container_name: localai
    restart: unless-stopped
${PLATFORM_SPEC}
    ports:
      - "${DEFAULT_PORT}:8080"
    volumes:
      - ${MODELS_DIR}:/models
      - ${CONFIG_DIR}:/config
    environment:
      - MODELS_PATH=/models
      - CONFIG_PATH=/config
      - THREADS=4
      - DEBUG=false
      - CONTEXT_SIZE=2048
      # Add resource limits
    deploy:
      resources:
        limits:
          cpus: '0.75'
          memory: 4G
        reservations:
          cpus: '0.25'
          memory: 2G
EOL

  if [ -n "$API_KEY" ]; then
    cat >> "$COMPOSE_FILE" << EOL
      - API_KEY=${API_KEY}
EOL
  fi

  # Add Caddy for reverse proxy (needed for future OAuth integration)
  if [ "$ENABLE_TLS" = true ] || [ "$ENABLE_OAUTH" = true ]; then
    cat >> "$COMPOSE_FILE" << EOL

  caddy:
    image: caddy:2.7.6
    container_name: caddy
    restart: unless-stopped
    ports:
      - "${CADDY_PORT}:80"
      - "443:443"
    volumes:
      - ${CONFIG_DIR}/Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      - localai

volumes:
  caddy_data:
  caddy_config:
EOL

    # Create a secured Caddyfile
    cat > "$CONFIG_DIR/Caddyfile" << EOL
${DOMAIN_NAME} {
  # Security headers
  header {
    # Enable HTTP Strict Transport Security (HSTS)
    Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
    # Prevent MIME-sniffing
    X-Content-Type-Options "nosniff"
    # Clickjacking protection
    X-Frame-Options "DENY"
    # XSS protection
    X-XSS-Protection "1; mode=block"
    # Restrict referrer information
    Referrer-Policy "strict-origin-when-cross-origin"
  }
  # Placeholder for OAuth2 authentication
  # To enable OAuth, uncomment the following lines and configure with your provider
  # forward_auth oauth2-proxy:4180 {
  #   uri /oauth2/auth
  #   copy_headers X-Auth-Request-User X-Auth-Request-Email
  # }
  
  reverse_proxy localai:8080
}
EOL
  fi

  # Create environment file
  cat > "$ENV_FILE" << EOL
# LocalAI Configuration
DEFAULT_PORT=${DEFAULT_PORT}
DOMAIN_NAME=${DOMAIN_NAME}
API_KEY=${API_KEY}
ENABLE_OAUTH=${ENABLE_OAUTH}
ENABLE_TLS=${ENABLE_TLS}
EOL

  success "Docker compose file created!"
}

create_model_configs() {
  info "Creating model configurations..."
  
  # Create a base configuration for each model
  for model_entry in "${MODELS[@]}"; do
    model_name=$(echo $model_entry | cut -d: -f1)
    
    cat > "$CONFIG_DIR/$model_name.yaml" << EOL
name: $model_name
backend: llama-cpp
parameters:
  model: /models/$model_name.gguf
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
  done
  
  success "Model configurations created!"
}

download_models() {
  info "Setting up models (this may take some time)..."
  
  # Function to directly download from HuggingFace
  download_from_huggingface() {
    local model_name=$1
    local huggingface_url=$2
    
    # Extract HuggingFace path components
    # Format: huggingface://user/repo/filename
    local hf_path=${huggingface_url#huggingface://}
    local user=$(echo "$hf_path" | cut -d'/' -f1)
    local repo=$(echo "$hf_path" | cut -d'/' -f2)
    local filename=$(echo "$hf_path" | cut -d'/' -f3-)
    
    # Construct the direct download URL
    local download_url="https://huggingface.co/$user/$repo/resolve/main/$filename"
    
    info "Downloading $model_name directly from HuggingFace: $download_url"
    
    # Download with progress using curl
    if curl -L --progress-bar "$download_url" -o "$MODELS_DIR/$model_name.gguf"; then
      success "Downloaded $model_name"
      return 0
    else
      warn "Failed to download $model_name, but continuing with setup"
      return 1
    fi
  }
  
  # Use direct download for HuggingFace URLs
  for model_entry in "${MODELS[@]}"; do
    model_name=$(echo $model_entry | cut -d: -f1)
    model_url=$(echo $model_entry | cut -d: -f2-)
    
    info "Downloading $model_name from $model_url"
    
    # Check if it's a HuggingFace URL
    if [[ "$model_url" == huggingface://* ]]; then
      download_from_huggingface "$model_name" "$model_url"
    else
      # For non-HuggingFace URLs, use the original Docker method
      # Use the architecture-specific image
      docker run --rm \
        --security-opt no-new-privileges=true \
        --cap-drop ALL \
        $PLATFORM_ARGS \
        -v "$MODELS_DIR:/models" \
        $LOCALAI_IMAGE \
        local-ai run "$model_url" --models-path=/models --model-name="$model_name.gguf"
      
      if [ $? -ne 0 ]; then
        warn "Failed to download $model_name, but continuing with setup"
      else
        success "Downloaded $model_name"
      fi
    fi
  done
  
  # Also download the default model if specified
  if [ -n "$DEFAULT_MODEL" ]; then
    info "Downloading default model: $DEFAULT_MODEL"
    
    # Split the model specification
    default_model_name=$(echo "$DEFAULT_MODEL" | cut -d: -f1)
    default_model_type=$(echo "$DEFAULT_MODEL" | cut -d: -f2)
    
    # Check if it's a known standard model
    if [[ "$default_model_name" == llama-3* ]]; then
      info "Detected standard Llama 3 model, using direct download"
      
      # For Llama 3 models, we can construct the download URL
      model_filename="${default_model_name}-${default_model_type}.gguf"
      download_url="https://huggingface.co/localai/llama/resolve/main/$model_filename"
      
      if curl -L --progress-bar "$download_url" -o "$MODELS_DIR/$model_filename"; then
        success "Downloaded default model: $model_filename"
      else
        warn "Failed to download default model, but continuing with setup"
      fi
    else
      # Fall back to the Docker method
      docker run --rm \
        --security-opt no-new-privileges=true \
        --cap-drop ALL \
        $PLATFORM_ARGS \
        -v "$MODELS_DIR:/models" \
        $LOCALAI_IMAGE \
        local-ai run "$DEFAULT_MODEL" --models-path=/models
    fi
  fi
  
  success "Models downloaded"
}

start_services() {
  info "Starting LocalAI services..."
  
  cd "$LOCALAI_DIR"
  docker-compose up -d
  
  if [ $? -ne 0 ]; then
    error "Failed to start services"
  fi
  
  success "Services started!"
}

print_completion_message() {
  echo -e "${GREEN}"
  echo "================================================================"
  echo "             LocalAI Installation Complete!                      "
  echo "================================================================"
  echo -e "${NC}"
  echo "LocalAI is now running on http://localhost:${DEFAULT_PORT}"
  echo ""
  echo "Available models:"
  for model_entry in "${MODELS[@]}"; do
    model_name=$(echo $model_entry | cut -d: -f1)
    echo "  - $model_name"
  done
  if [ -n "$DEFAULT_MODEL" ]; then
    echo "  - Default model: $DEFAULT_MODEL"
  fi
  echo ""
  echo "Configuration directory: $CONFIG_DIR"
  echo "Models directory: $MODELS_DIR"
  echo "System architecture: $ARCH"
  echo "LocalAI image used: $LOCALAI_IMAGE"
  echo ""
  echo "To start/stop the services:"
  echo "  cd $LOCALAI_DIR && docker-compose up -d"
  echo "  cd $LOCALAI_DIR && docker-compose down"
  echo ""
  echo "To view logs:"
  echo "  cd $LOCALAI_DIR && docker-compose logs -f"
  echo ""
  if [ "$ENABLE_OAUTH" = false ]; then
    echo "To enable OAuth in the future:"
    echo "  1. Set ENABLE_OAUTH=true in $ENV_FILE"
    echo "  2. Configure the OAuth provider in the Caddyfile"
    echo "  3. Restart services with: cd $LOCALAI_DIR && docker-compose up -d"
  fi
}

create_management_scripts() {
  info "Creating management scripts..."
  
  # Create update script
  cat > "$LOCALAI_DIR/update.sh" << 'EOL'
#!/bin/bash
cd "$(dirname "$0")"
echo "Updating LocalAI container..."
# Check for available updates
echo "Checking for LocalAI updates..."
LATEST_VERSION=$(curl -s https://api.github.com/repos/mudler/LocalAI/releases/latest | grep -oP '"tag_name":\s*"\K[^"]+' || echo "unknown")
CURRENT_VERSION=$(docker inspect --format='{{.Config.Image}}' localai | grep -oP 'localai:v\K[^-]+' || echo "unknown")

if [ "$LATEST_VERSION" != "unknown" ] && [ "$CURRENT_VERSION" != "unknown" ]; then
  if [ "$LATEST_VERSION" = "$CURRENT_VERSION" ]; then
    echo "LocalAI is already at the latest version $CURRENT_VERSION"
  else
    echo "Updating LocalAI from $CURRENT_VERSION to $LATEST_VERSION"
    # Create backup before updating
    mkdir -p ../backups/$(date +%Y%m%d)
    cp -r ../config ../backups/$(date +%Y%m%d)/
    
    docker-compose pull
    docker-compose down
    docker-compose up -d
  fi
else
  echo "Could not determine version information. Proceeding with update anyway."
  docker-compose pull
  docker-compose down
  docker-compose up -d
fi
echo "Update complete!"
EOL
  chmod +x "$LOCALAI_DIR/update.sh"
  
  # Create model management script - include architecture detection in this script too
  cat > "$LOCALAI_DIR/add-model.sh" << EOL
#!/bin/bash
set -e

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
NC='\033[0m' # No Color

# Print with colors
info() { echo -e "\${BLUE}[INFO]\${NC} \$1"; }
success() { echo -e "\${GREEN}[SUCCESS]\${NC} \$1"; }
warn() { echo -e "\${YELLOW}[WARNING]\${NC} \$1"; }
error() { echo -e "\${RED}[ERROR]\${NC} \$1"; exit 1; }

# Detect system architecture and set appropriate image tag
detect_architecture() {
  info "Detecting system architecture..."
  
  # Get architecture using uname
  ARCH=\$(uname -m)
  
  # Set the appropriate image tag based on architecture
  case "\$ARCH" in
    x86_64)
      LOCALAI_IMAGE="localai/localai:latest-aio-cpu"
      info "Detected x86_64 architecture, using \$LOCALAI_IMAGE"
      ;;
    aarch64|arm64)
      # Try ARM64-specific image first
      if docker pull "localai/localai:latest-aio-cpu-arm64" &>/dev/null; then
        LOCALAI_IMAGE="localai/localai:latest-aio-cpu-arm64"
        PLATFORM_ARGS=""
        info "Using ARM64-specific image: \$LOCALAI_IMAGE"
      else
        # Fall back to standard image with explicit platform flag
        LOCALAI_IMAGE="localai/localai:latest-aio-cpu"
        PLATFORM_ARGS="--platform=linux/amd64"
        info "ARM64-specific image not found. Using standard image with emulation: \$LOCALAI_IMAGE"
        info "Setting explicit platform flag: \$PLATFORM_ARGS"
      fi
      ;;
    *)
      warn "Unknown architecture: \$ARCH, defaulting to amd64 image"
      LOCALAI_IMAGE="localai/localai:latest-aio-cpu"
      ;;
  esac
  
  # For x86_64, default platform args are empty
  if [ "\$ARCH" = "x86_64" ]; then
    PLATFORM_ARGS=""
  fi
  success "Architecture detection complete"
}

MODELS_DIR="\$(dirname "\$0")/models"
CONFIG_DIR="\$(dirname "\$0")/config"

# Detect the architecture
detect_architecture

if [ \$# -lt 2 ]; then
  echo "Usage: \$0 MODEL_NAME MODEL_URL"
  echo "Example: \$0 llama-2-7b-chat huggingface://TheBloke/Llama-2-7B-Chat-GGUF/llama-2-7b-chat.Q4_K_M.gguf"
  exit 1
fi

MODEL_NAME="\$1"
MODEL_URL="\$2"

# Function to directly download from HuggingFace
download_from_huggingface() {
  local model_name=\$1
  local huggingface_url=\$2
  
  # Extract HuggingFace path components
  # Format: huggingface://user/repo/filename
  local hf_path=\${huggingface_url#huggingface://}
  local user=\$(echo "\$hf_path" | cut -d'/' -f1)
  local repo=\$(echo "\$hf_path" | cut -d'/' -f2)
  local filename=\$(echo "\$hf_path" | cut -d'/' -f3-)
  
  # Construct the direct download URL
  local download_url="https://huggingface.co/\$user/\$repo/resolve/main/\$filename"
  
  echo "Downloading from HuggingFace: \$download_url"
  
  # Download with progress using curl
  if curl -L --progress-bar "\$download_url" -o "\$MODELS_DIR/\$model_name.gguf"; then
    echo "Successfully downloaded \$model_name"
    return 0
  else
    echo "Error: Failed to download model"
    exit 1
  fi
}

echo "Downloading model \$MODEL_NAME from \$MODEL_URL"
# Input validation
if [[ ! "\$MODEL_NAME" =~ ^[a-zA-Z0-9_-]+\$ ]]; then
  echo "Error: Model name can only contain alphanumeric characters, hyphens and underscores"
  exit 1
fi

# Check if it's a HuggingFace URL and download directly
if [[ "\$MODEL_URL" == huggingface://* ]]; then
  download_from_huggingface "\$MODEL_NAME" "\$MODEL_URL"
else
  # For non-HuggingFace URLs, use the Docker method
  # Secure download with container security constraints
  docker run --rm \
    --security-opt no-new-privileges=true \
    --cap-drop ALL \
    \$PLATFORM_ARGS \
    -v "\$MODELS_DIR:/models" \
    \$LOCALAI_IMAGE \
    local-ai run "\$MODEL_URL" --models-path=/models --model-name="\$MODEL_NAME.gguf"
  
  # Verify file was downloaded successfully
  if [ ! -f "\$MODELS_DIR/\$MODEL_NAME.gguf" ]; then
    echo "Error: Failed to download model"
    exit 1
  fi
fi

# Create config
cat > "\$CONFIG_DIR/\$MODEL_NAME.yaml" << EOF
name: \$MODEL_NAME
backend: llama-cpp
parameters:
  model: /models/\$MODEL_NAME.gguf
  context_size: 2048
  threads: 4
  f16: true
template:
  chat:
    template: |
      <s>{{- if .System }}
      {{.System}}
      {{- end }}
      {{- range \\\$i, \\\$message := .Messages }}
      {{- if eq \\\$message.Role "user" }}
      [INST] {{ \\\$message.Content }} [/INST]
      {{- else if eq \\\$message.Role "assistant" }}
      {{ \\\$message.Content }}
      {{- end }}
      {{- end }}
EOF

echo "Model \$MODEL_NAME added! Restart LocalAI for changes to take effect:"
echo "cd \$(dirname "\$0") && docker-compose restart localai"
EOL
  chmod +x "$LOCALAI_DIR/add-model.sh"
  
  success "Management scripts created!"
}

# Main installation flow
print_banner
check_dependencies
# Detect system architecture before proceeding
detect_architecture
create_directory_structure
create_docker_compose
create_model_configs
download_models
create_management_scripts
start_services
print_completion_message
