#!/bin/bash
# Make this script executable with: chmod +x deploy.sh
# Deploy script for self_hosted_ai in a clean Ubuntu 22.04 environment

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

# Installation directory
LOCALAI_DIR="/opt/localai"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  error "Please run as root or with sudo"
fi

# Check system requirements
check_system_requirements() {
  info "Checking system requirements..."
  
  # Check Ubuntu version
  if ! grep -q "Ubuntu 22" /etc/os-release 2>/dev/null; then
    warn "This script is designed for Ubuntu 22.04. You are running:"
    cat /etc/os-release 2>/dev/null | grep "PRETTY_NAME" || echo "Unknown OS"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      exit 1
    fi
  fi
  
  # Check disk space
  AVAILABLE_SPACE=$(df -BG --output=avail / 2>/dev/null | tail -n 1 | tr -d 'G' || echo "Unknown")
  if [[ "$AVAILABLE_SPACE" != "Unknown" && "$AVAILABLE_SPACE" -lt 20 ]]; then
    warn "Less than 20GB of free disk space available ($AVAILABLE_SPACE GB). Models typically require 5-15GB."
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      exit 1
    fi
  fi
  
  # Check memory
  TOTAL_MEM=$(free -g 2>/dev/null | awk '/^Mem:/{print $2}' || echo "Unknown")
  if [[ "$TOTAL_MEM" != "Unknown" && "$TOTAL_MEM" -lt 4 ]]; then
    warn "Less than 4GB of RAM detected. Performance may be poor."
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      exit 1
    fi
  fi
  
  success "System requirements checked."
}

# Install dependencies
install_dependencies() {
  info "Installing necessary packages..."
  
  # Update package lists
  apt-get update
  
  # Install essential packages
  apt-get install -y curl git python3-pip python3-venv
  
  # Check Docker
  if ! command -v docker &>/dev/null; then
    info "Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    
    # Start Docker service
    systemctl enable --now docker
    
    # Add current user to docker group if we're using sudo
    SUDO_USER=$(logname 2>/dev/null || echo $SUDO_USER)
    if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
      info "Adding user $SUDO_USER to the docker group"
      usermod -aG docker $SUDO_USER
      warn "You may need to log out and back in for docker group changes to take effect"
    fi
  else
    info "Docker is already installed"
    
    # Ensure Docker is running
    if ! systemctl is-active --quiet docker; then
      info "Starting Docker service"
      systemctl start docker
    fi
  fi
  
  # Check Docker Compose
  if ! command -v docker-compose &>/dev/null; then
    info "Installing Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/download/v2.24.6/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    # Create a symlink for the compose plugin
    mkdir -p /usr/local/lib/docker/cli-plugins
    ln -sf /usr/local/bin/docker-compose /usr/local/lib/docker/cli-plugins/docker-compose
  else
    # Check Docker Compose version
    COMPOSE_VERSION=$(docker-compose version --short 2>/dev/null || echo "0")
    MAJOR_VERSION=$(echo $COMPOSE_VERSION | cut -d. -f1)
    
    if [ "$MAJOR_VERSION" -lt 2 ]; then
      warn "Older version of Docker Compose detected: $COMPOSE_VERSION. Updating to v2.x"
      curl -L "https://github.com/docker/compose/releases/download/v2.24.6/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
      chmod +x /usr/local/bin/docker-compose
    fi
  fi
  
  # Install Python dependencies
  pip3 install -r requirements.txt
  
  # Install huggingface-cli for model downloads
  pip3 install "huggingface_hub[cli]"
  
  success "All dependencies installed!"
}

# Set up LocalAI directory structure
setup_localai_directory() {
  info "Setting up LocalAI directory structure..."
  
  # Create main directory if it doesn't exist
  mkdir -p "$LOCALAI_DIR"
  
  # Create models and config subdirectories
  mkdir -p "$LOCALAI_DIR/models"
  mkdir -p "$LOCALAI_DIR/config"
  
  # Copy documentation
  if [ -d "docs" ]; then
    cp -r docs/* "$LOCALAI_DIR/"
  fi
  
  # Copy requirements.txt
  cp requirements.txt "$LOCALAI_DIR/"
  
  # Copy README.md
  cp README.md "$LOCALAI_DIR/"
  
  success "LocalAI directory structure set up at $LOCALAI_DIR"
}

# Copy and prepare scripts
copy_scripts() {
  info "Copying scripts to LocalAI directory..."
  
  # Get the directory where this script is located
  DEPLOY_DIR="$(dirname "$(readlink -f "$0")")"
  info "Deploy directory: $DEPLOY_DIR"
  
  # Find and copy setup script
  if [ -f "$DEPLOY_DIR/scripts/setup/setup-localai.sh" ]; then
    cp "$DEPLOY_DIR/scripts/setup/setup-localai.sh" "$LOCALAI_DIR/"
    info "Copied setup script from scripts/setup/"
  elif [ -f "$DEPLOY_DIR/setup-localai.sh" ]; then
    cp "$DEPLOY_DIR/setup-localai.sh" "$LOCALAI_DIR/"
    info "Copied setup script from root directory"
  else
    error "Could not find setup-localai.sh script"
  fi
  
  # Find and copy model scripts
  MODEL_SCRIPT_SOURCE=""
  if [ -f "$DEPLOY_DIR/scripts/models/download-cpu-optimized-models.sh" ]; then
    MODEL_SCRIPT_SOURCE="$DEPLOY_DIR/scripts/models/download-cpu-optimized-models.sh"
    info "Found model script at: $MODEL_SCRIPT_SOURCE"
  elif [ -f "$DEPLOY_DIR/download-cpu-optimized-models.sh" ]; then
    MODEL_SCRIPT_SOURCE="$DEPLOY_DIR/download-cpu-optimized-models.sh"
    info "Found model script at: $MODEL_SCRIPT_SOURCE"
  else
    error "Could not find download-cpu-optimized-models.sh in any location"
  fi
  
  # Copy the model script
  if [ -n "$MODEL_SCRIPT_SOURCE" ]; then
    info "Copying model script from: $MODEL_SCRIPT_SOURCE"
    cp "$MODEL_SCRIPT_SOURCE" "$LOCALAI_DIR/download-cpu-optimized-models.sh"
    chmod +x "$LOCALAI_DIR/download-cpu-optimized-models.sh"
    success "Copied and made executable: download-cpu-optimized-models.sh"
  fi
  
  # Copy additional scripts if they exist
  if [ -f "$DEPLOY_DIR/scripts/models/create-aliases.sh" ]; then
    cp "$DEPLOY_DIR/scripts/models/create-aliases.sh" "$LOCALAI_DIR/"
    chmod +x "$LOCALAI_DIR/create-aliases.sh"
    success "Copied and made executable: create-aliases.sh"
  fi
  
  if [ -f "$DEPLOY_DIR/scripts/models/auto-update-models.py" ]; then
    cp "$DEPLOY_DIR/scripts/models/auto-update-models.py" "$LOCALAI_DIR/"
    chmod +x "$LOCALAI_DIR/auto-update-models.py"
    success "Copied and made executable: auto-update-models.py"
  fi
  
  success "Scripts copied and made executable"
  
  # Verify the files were copied correctly
  info "Verifying copied files:"
  ls -l "$LOCALAI_DIR/"*.sh "$LOCALAI_DIR/"*.py 2>/dev/null || warn "No scripts found in $LOCALAI_DIR"
}

# Check internet connectivity
check_connectivity() {
  info "Checking internet connectivity..."
  
  if ! curl --connect-timeout 5 -s --head https://huggingface.co >/dev/null; then
    warn "Cannot reach HuggingFace.co - check your internet connection"
    if ! curl --connect-timeout 5 -s --head https://www.google.com >/dev/null; then
      error "No internet connectivity detected. Please check your network connection."
    else
      warn "General internet connectivity works, but HuggingFace.co cannot be reached."
      warn "This may affect model downloads. Check your firewall settings."
      read -p "Continue anyway? (y/n) " -n 1 -r
      echo
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
      fi
    fi
  fi
  
  if ! curl --connect-timeout 5 -s --head https://registry.hub.docker.com >/dev/null; then
    warn "Cannot reach Docker Hub - check your internet connection"
    warn "This may affect Docker image downloads. Check your firewall settings."
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      exit 1
    fi
  fi
  
  success "Internet connectivity confirmed"
}

# Run setup script
run_setup() {
  info "Running LocalAI setup script..."
  
  # Enter the LocalAI directory
  cd "$LOCALAI_DIR"
  
  # Run the setup script
  if [ -f "./setup-localai.sh" ]; then
    ./setup-localai.sh
    
    if [ $? -eq 0 ]; then
      success "Setup completed successfully!"
    else
      error "Setup script failed with exit code $?"
    fi
  else
    error "Could not find setup-localai.sh in $LOCALAI_DIR"
  fi
}

# Print completion message
print_completion() {
  echo -e "${GREEN}"
  echo "================================================================"
  echo "             LocalAI Deployment Complete!                      "
  echo "================================================================"
  echo -e "${NC}"
  echo "LocalAI has been deployed to $LOCALAI_DIR"
  echo ""
  echo "Next steps:"
  echo "1. To download and configure models:"
  echo "   cd $LOCALAI_DIR && sudo ./download-cpu-optimized-models.sh"
  echo ""
  echo "2. To discover trending models:"
  echo "   cd $LOCALAI_DIR && sudo python3 auto-update-models.py"
  echo ""
  echo "3. To create OpenAI-compatible model aliases:"
  echo "   cd $LOCALAI_DIR && sudo ./create-aliases.sh"
  echo ""
  echo "For more information, see the documentation files in $LOCALAI_DIR"
  echo ""
  
  # Check if a non-root user was used with sudo
  SUDO_USER=$(logname 2>/dev/null || echo $SUDO_USER)
  if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
    echo "Remember to log out and back in for Docker group changes to take effect for user $SUDO_USER"
  fi
}

# Main function
main() {
  echo -e "${GREEN}"
  echo "================================================================"
  echo "             LocalAI Deployment Script                      "
  echo "================================================================"
  echo -e "${NC}"
  
  check_system_requirements
  check_connectivity
  install_dependencies
  setup_localai_directory
  copy_scripts
  run_setup
  print_completion
}

# Run the main function
main
