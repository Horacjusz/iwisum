#!/bin/bash

# Quick comparison script for trained vs random agent
# Usage: ./run_comparison.sh [model_path] [num_episodes]

MODEL_PATH=${1:-"checkpoints/best_model.pt"}
NUM_EPISODES=${2:-100}

echo "=========================================="
echo "Agent Comparison Script"
echo "=========================================="
echo "Model: $MODEL_PATH"
echo "Episodes: $NUM_EPISODES"
echo ""

# Check if model exists
if [ ! -f "$MODEL_PATH" ]; then
    echo "ERROR: Model not found at $MODEL_PATH"
    echo "Please train a model first with: ./run_training.sh"
    exit 1
fi

# Run comparison
python compare_agents.py \
    --model "$MODEL_PATH" \
    --episodes "$NUM_EPISODES" \
    --max-steps 100 \
    --save-results "comparison_results.json"

echo ""
echo "=========================================="
echo "Comparison complete!"
echo "Results saved to: comparison_results.json"
echo "=========================================="

