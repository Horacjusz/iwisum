# Quick Start Guide - DQN Training

## Installation (One-time setup)

```bash
cd python
pip install -r requirements.txt
```

This installs:
- PyTorch
- NumPy
- Matplotlib
- TensorBoard (optional, for advanced monitoring)

## Running Training

### Option 1: Using the shell script (Recommended)
```bash
cd python
./run_training.sh
```

### Option 2: Direct Python execution
```bash
cd python
python train_dqn.py
```

## What Happens During Training

1. **Initialization** (~5 seconds)
   - Loads the map and environment
   - Creates the neural network
   - Sets up training infrastructure

2. **Training Loop** (2-10 hours for 10,000 episodes)
   - Agent explores the environment
   - Learns from experience
   - Progress logged every 10 episodes
   - Checkpoints saved every 100 episodes

3. **Output**
   - `checkpoints/` - Regular checkpoints every 100 episodes
   - `checkpoints_backup/best_model.pt` - Best performing model
   - `checkpoints/training_curves.png` - Visualization of training progress

## Monitoring Progress

Watch the console output:
```
Episode    100 | Avg Reward:    -5.23 | Avg Length:   45.2 | Success Rate:  12.0% | Loss:   0.0234 | Epsilon: 0.9512
```

**Key Metrics:**
- **Avg Reward**: Higher is better (should increase over time)
- **Success Rate**: Percentage of episodes where agent reaches target before reaching time limit (should increase over time)
- **Avg Length**: Steps per episode (should decrease as agent learns)
- **Epsilon**: Exploration rate (decreases over time)

## Testing Trained Agent

After training, evaluate the agent:

```bash
# Test the best model on 100 episodes
python evaluate_agent.py --checkpoint checkpoints_backup/best_model.pt --episodes 100

# Watch a single episode in detail
python evaluate_agent.py --checkpoint checkpoints_backup/best_model.pt --episodes 1 --verbose
```
