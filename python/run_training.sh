#!/bin/bash

# Quick start script for DQN training
# This script sets up the environment and starts training

echo "=========================================="
echo "DQN Training for Public Transport Navigation"
echo "=========================================="
echo ""

# Check if Python is available
if ! command -v python3 &> /dev/null; then
    echo "Error: Python 3 is not installed"
    exit 1
fi

# Check if required packages are installed
echo "Checking dependencies..."
python3 -c "import torch" 2>/dev/null
if [ $? -ne 0 ]; then
    echo "PyTorch not found. Installing dependencies..."
    pip install -r requirements.txt
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install dependencies"
        exit 1
    fi
else
    echo "Dependencies OK"
fi

echo ""
echo "Starting training..."
echo "- Checkpoints will be saved to: checkpoints/"
echo "- Best model will be saved to: checkpoints_backup/best_model.pt"
echo "- Press Ctrl+C to stop training (progress will be saved)"
echo ""
echo "=========================================="
echo ""

# Start training
python3 train_dqn.py

echo ""
echo "=========================================="
echo "Training completed or interrupted"
echo "=========================================="
