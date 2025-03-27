#!/usr/bin/env python3
"""
Script to automatically find and download the latest trending CPU-optimized models from Hugging Face.
This script will:
1. Query the Hugging Face API to find recent GGUF models
2. Filter for Q4_K_M models (best for CPU)
3. Download the most popular/relevant models for LocalAI
"""

import os
import json
import argparse
import subprocess
import requests
from huggingface_hub import HfApi, ModelFilter
from tqdm import tqdm

# Constants
CONFIG_DIR = "/opt/localai/config"
MODELS_DIR = "/opt/localai/models"
QUANTIZATION = "Q4_K_M"  # Best balance for CPU performance
DEFAULT_NUM_MODELS = 5

def setup_argument_parser():
    """Set up command line arguments."""
    parser = argparse.ArgumentParser(description='Find and download trending CPU-optimized models from Hugging Face')
    parser.add_argument('--num-models', type=int, default=DEFAULT_NUM_MODELS, 
                       help=f'Number of models to download (default: {DEFAULT_NUM_MODELS})')
    parser.add_argument('--small-only', action='store_true',
                       help='Only fetch small models (1-3B parameters)')
    parser.add_argument('--output-dir', type=str, default=MODELS_DIR,
                       help=f'Directory to save models (default: {MODELS_DIR})')
    parser.add_argument('--config-dir', type=str, default=CONFIG_DIR,
                       help=f'Directory for model configurations (default: {CONFIG_DIR})')
    parser.add_argument('--create-aliases', action='store_true',
                       help='Create OpenAI-compatible model aliases')
    parser.add_argument('--list-only', action='store_true',
                       help='Only list trending models without downloading')
    parser.add_argument('--include-categories', type=str, 
                       help='Comma-separated categories to include (e.g., "llama,mistral,gemma")')
    return parser.parse_args()

def get_trending_gguf_models(max_models=10, small_only=False, categories=None):
    """Find trending GGUF models on Hugging Face."""
    api = HfApi()
    print(f"Searching for trending GGUF models...")
    
    # Define search filters
    filter_params = ModelFilter(library="gguf")
    
    # Get trending models
    models = list(api.list_models(
        filter=filter_params, 
        sort="downloads", 
        direction=-1,
        limit=100
    ))
    
    # Filter results further
    filtered_models = []
    for model in models:
        # Check if model ID contains any of the specified categories
        if categories:
            if not any(cat.lower() in model.id.lower() for cat in categories):
                continue
        
        # Filter for small models if specified
        if small_only:
            # Skip large models (rough estimation based on model name)
            if any(x in model.id.lower() for x in ["70b", "30b", "40b", "65b", "13b"]):
                continue
            # Include 1-8B models
            if not any(x in model.id.lower() for x in ["1b", "2b", "3b", "5b", "7b", "8b"]):
                continue
        
        filtered_models.append(model)
        if len(filtered_models) >= max_models:
            break
    
    return filtered_models

def find_best_gguf_file(model_id):
    """Find the best Q4_K_M GGUF file for a given model."""
    api = HfApi()
    
    try:
        # List all files in the model repository
        files = api.list_repo_files(model_id)
        
        # First try to find a Q4_K_M file (best balance for CPU)
        q4_files = [f for f in files if f.endswith(".gguf") and "Q4_K_M" in f]
        if q4_files:
            return sorted(q4_files)[0]  # Return the first Q4_K_M file
        
        # If no Q4_K_M file, try to find any .gguf file
        gguf_files = [f for f in files if f.endswith(".gguf")]
        if gguf_files:
            # Prioritize quantized files for CPU efficiency
            for pattern in ["Q4_0", "Q4_K", "Q3_K", "Q5_K", "Q2_K", "Q8_0"]:
                matches = [f for f in gguf_files if pattern in f]
                if matches:
                    return sorted(matches)[0]
            return sorted(gguf_files)[0]  # Return any GGUF file if no quantized ones
    
    except Exception as e:
        print(f"Error accessing repository {model_id}: {e}")
    
    return None

def create_model_config(model_name, model_file, config_dir):
    """Create a configuration YAML file for a LocalAI model."""
    # Determine appropriate thread count based on CPU cores
    import multiprocessing
    cpu_cores = multiprocessing.cpu_count()
    recommended_threads = max(2, min(cpu_cores // 2, 8))
    
    config_path = os.path.join(config_dir, f"{model_name}.yaml")
    
    config_content = f"""name: {model_name}
backend: llama-cpp
parameters:
  model: /models/{model_file}
  context_size: 2048
  threads: {recommended_threads}
  f16: true
template:
  chat:
    template: |
      <s>{{{{- if .System }}}}
      {{{{.System}}}}
      {{{{- end }}}}
      {{{{- range $i, $message := .Messages }}}}
      {{{{- if eq $message.Role "user" }}}}
      [INST] {{{{ $message.Content }}}} [/INST]
      {{{{- else if eq $message.Role "assistant" }}}}
      {{{{ $message.Content }}}}
      {{{{- end }}}}
      {{{{- end }}}}
"""
    
    with open(config_path, "w") as f:
        f.write(config_content)
    
    print(f"Created configuration for {model_name}")
    return config_path

def download_model(model_id, file_name, model_dir):
    """Download a model file from Hugging Face using huggingface-cli."""
    destination = os.path.join(model_dir, os.path.basename(file_name))
    
    # Skip if the file already exists
    if os.path.exists(destination):
        print(f"Model file {os.path.basename(file_name)} already exists, skipping download.")
        return destination
    
    print(f"Downloading {file_name} from {model_id}...")
    cmd = [
        "huggingface-cli", "download", 
        model_id, file_name,
        "--local-dir", model_dir,
        "--local-dir-use-symlinks", "False"
    ]
    
    try:
        # Use subprocess to run the command
        subprocess.run(cmd, check=True)
        print(f"Successfully downloaded {file_name} to {model_dir}")
        return destination
    except subprocess.CalledProcessError as e:
        print(f"Error downloading model {model_id}/{file_name}: {e}")
        return None

def create_openai_aliases(config_dir, downloaded_models):
    """Create OpenAI-compatible aliases for downloaded models."""
    if not downloaded_models:
        print("No models available for creating aliases.")
        return
    
    print("Creating OpenAI-compatible aliases...")
    
    # Find a small model for gpt-3.5-turbo
    small_models = [m for m in downloaded_models if any(x in m.lower() for x in ["phi", "gemma-2", "mistral", "llama-3-1b"])]
    if small_models:
        small_model = small_models[0]
        alias_path = os.path.join(config_dir, "gpt-3.5-turbo.yaml")
        source_path = os.path.join(config_dir, f"{small_model}.yaml")
        
        if os.path.exists(source_path):
            with open(source_path, "r") as src_file:
                config = src_file.read()
            
            config = config.replace(f"name: {small_model}", "name: gpt-3.5-turbo")
            
            with open(alias_path, "w") as dst_file:
                dst_file.write(config)
            
            print(f"Created gpt-3.5-turbo alias pointing to {small_model}")
    
    # Find a larger model for gpt-4
    large_models = [m for m in downloaded_models if any(x in m.lower() for x in ["llama-3-8", "mistral-7", "llama-3.1-8"])]
    if large_models:
        large_model = large_models[0]
        alias_path = os.path.join(config_dir, "gpt-4.yaml")
        source_path = os.path.join(config_dir, f"{large_model}.yaml")
        
        if os.path.exists(source_path):
            with open(source_path, "r") as src_file:
                config = src_file.read()
            
            # Modify the configuration for gpt-4
            config = config.replace(f"name: {large_model}", "name: gpt-4")
            # Increase context size for gpt-4
            config = config.replace("context_size: 2048", "context_size: 4096")
            
            with open(alias_path, "w") as dst_file:
                dst_file.write(config)
            
            print(f"Created gpt-4 alias pointing to {large_model}")

def main():
    args = setup_argument_parser()
    
    # Ensure directories exist
    os.makedirs(args.output_dir, exist_ok=True)
    os.makedirs(args.config_dir, exist_ok=True)
    
    # Parse categories if provided
    categories = None
    if args.include_categories:
        categories = [c.strip() for c in args.include_categories.split(',')]
    
    # Find trending models
    models = get_trending_gguf_models(
        max_models=args.num_models, 
        small_only=args.small_only,
        categories=categories
    )
    
    print(f"\nFound {len(models)} trending GGUF models:")
    for i, model in enumerate(models):
        print(f"{i+1}. {model.id} (Downloads: {model.downloads})")
    
    if args.list_only:
        print("\nList-only mode - exiting without downloading.")
        return
    
    # Download and configure models
    downloaded_model_names = []
    
    for model in models:
        # Find the best GGUF file for this model
        file_name = find_best_gguf_file(model.id)
        if not file_name:
            print(f"No suitable GGUF file found for {model.id}, skipping.")
            continue
        
        # Create a simplified model name from the ID
        model_name = model.id.split('/')[-1].lower()
        if "llama" in model_name:
            model_name = f"llama-{model_name.split('llama')[-1]}"
        elif "mistral" in model_name:
            model_name = f"mistral-{model_name.split('mistral')[-1]}"
        
        # Clean up model name for LocalAI
        model_name = model_name.replace('-gguf', '')
        model_name = ''.join(c if c.isalnum() or c in ['-', '_'] else '-' for c in model_name)
        model_name = model_name.strip('-_')
        
        # Download the model
        downloaded_path = download_model(model.id, file_name, args.output_dir)
        if not downloaded_path:
            continue
        
        # Create LocalAI configuration for the model
        model_file = os.path.basename(file_name)
        config_path = create_model_config(model_name, model_file, args.config_dir)
        
        downloaded_model_names.append(model_name)
    
    # Create OpenAI-compatible aliases if requested
    if args.create_aliases and downloaded_model_names:
        create_openai_aliases(args.config_dir, downloaded_model_names)
    
    print("\nSummary:")
    print(f"- Downloaded {len(downloaded_model_names)} models")
    if downloaded_model_names:
        print("- Models:")
        for name in downloaded_model_names:
            print(f"  - {name}")
    
    print("\nTo use these models with LocalAI, restart the service:")
    print("cd /opt/localai && docker-compose restart localai")

if __name__ == "__main__":
    main()
