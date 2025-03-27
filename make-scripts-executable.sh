#!/bin/bash
# Helper script to make all scripts executable

# Make the fixed download script executable
chmod +x scripts/models/download-cpu-optimized-models-fixed.sh
echo "Made download-cpu-optimized-models-fixed.sh executable."

# Make the copy script executable too
chmod +x copy-to-localai.sh
echo "Made copy-to-localai.sh executable."

# Make deploy.sh executable if it's not already
chmod +x deploy.sh
echo "Made deploy.sh executable."

echo "All scripts are now executable. You can now run:"
echo "sudo ./deploy.sh"
echo "This will deploy LocalAI with the fixed download script."
