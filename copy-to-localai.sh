#!/bin/bash
# chmod +x copy-to-localai.sh to make this script executable
# Simple script to copy the fixed model download script to its destination

set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or with sudo"
  exit 1
fi

# Copy the fixed script
cp ./scripts/models/download-cpu-optimized-models-fixed.sh /opt/localai/download-cpu-optimized-models.sh
chmod +x /opt/localai/download-cpu-optimized-models.sh

echo "Fixed script has been deployed to /opt/localai/download-cpu-optimized-models.sh"
echo "You can now run it with: cd /opt/localai && sudo ./download-cpu-optimized-models.sh"
