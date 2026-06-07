# DQN Training System Architecture

A comprehensive Deep Q-Network (DQN) reinforcement learning system for training agents to navigate optimally on a map from point A to point B.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [System Components](#system-components)
3. [How It Works - Step by Step](#how-it-works---step-by-step)

---

## Architecture Overview

### What This System Does

This system trains an AI agent to navigate from a starting position to a target position on a 10x10 grid map. The agent learns through trial and error, receiving rewards for good actions and penalties for bad ones.

### Core Technology Stack

- **Deep Q-Network (DQN)**: Neural network that learns optimal action selection
- **Experience Replay**: Memory buffer storing past experiences for stable learning
- **Target Network**: Separate network providing stable learning targets
- **Epsilon-Greedy Exploration**: Balances trying new actions vs using learned behavior

### Neural Network Architecture

```
Input Layer (state_size features)
    ↓
Hidden Layer 1: 256 neurons + ReLU + Dropout(0.2)
    ↓
Hidden Layer 2: 256 neurons + ReLU + Dropout(0.2)
    ↓
Hidden Layer 3: 128 neurons + ReLU
    ↓
Output Layer: 5 actions (UP, DOWN, LEFT, RIGHT, WAIT)
```

**Why this architecture?**
- 3 hidden layers provide enough capacity to learn complex navigation patterns
- Dropout (0.2) prevents overfitting by randomly disabling neurons during training
- ReLU activation enables learning non-linear patterns
- 5 output neurons correspond to 5 possible actions

### State Representation

The agent observes the environment through a feature vector containing:

```python
State Vector = [
    Current Position (one-hot encoded, 100 values for 10x10 grid),
    Target Position (one-hot encoded, 100 values),
    Normalized Time (1 value, 0.0-1.0),
    Distance to Target (1 value, normalized),
    Additional Features (7 values)
]
Total: ~208 features
```
### Action Space

The agent can choose from 5 discrete actions:
- **0 = UP**: Move to cell above
- **1 = DOWN**: Move to cell below
- **2 = LEFT**: Move to cell on the left
- **3 = RIGHT**: Move to cell on the right
- **4 = WAIT**: Stay in current position

### Reward System

The reward structure guides the agent's learning:

```yaml
Positive Rewards:
  - Reaching Target: +50 (strong success incentive)
  - Moving Closer: +1.0 (gradual guidance toward goal)

Negative Penalties:
  - Each Step: -0.5 (encourages efficiency)
  - Invalid Move: -5 (discourages illegal actions)
  - Collision: -10 (strong penalty for hitting obstacles)
  - Moving Away: -1.0 (discourages wrong direction)
```

### Training Algorithm (DQN)

```
1. Initialize:
   - Policy Network (learns optimal actions)
   - Target Network (provides stable learning targets)
   - Replay Buffer (stores 100,000 experiences)

2. For each episode:
   a. Reset environment (random start/target positions)
   
   b. For each step (max 100 steps):
      - Select action using ε-greedy policy:
        * With probability ε: random action (exploration)
        * With probability 1-ε: best action from network (exploitation)
      
      - Execute action in environment
      - Observe reward and next state
      - Store experience in replay buffer
      
      - Sample random batch of 64 experiences from buffer
      - Calculate loss: L = (Q(s,a) - (r + γ·max Q'(s',a')))²
        where:
        * Q(s,a) = predicted value from policy network
        * r = immediate reward
        * γ = 0.99 (discount factor for future rewards)
        * Q'(s',a') = predicted value from target network
      
      - Update policy network using gradient descent
      
      - Every 1000 steps: copy policy network → target network
   
   c. Decay ε (exploration rate): ε = ε × 0.9995
   
   d. Log metrics and save checkpoint if needed

3. After training:
   - Save best model
   - Generate training curves
   - Evaluate performance
```

**Key Concepts Explained:**

- **Experience Replay**: Instead of learning from experiences in order, we store them and sample randomly. This breaks correlations between consecutive experiences, making learning more stable.

- **Target Network**: We use two networks - one for learning (policy) and one for calculating targets (target). The target network is updated slowly, providing stable learning targets.

- **Epsilon-Greedy**: Early in training (ε=1.0), the agent explores randomly. As training progresses (ε→0.01), it increasingly uses learned knowledge.

- **Discount Factor (γ=0.99)**: Future rewards are worth 99% of immediate rewards. This makes the agent consider long-term consequences.

### Hyperparameters

```yaml
Learning:
  learning_rate: 0.001        # How fast the network learns
  gamma: 0.99                 # Importance of future rewards
  batch_size: 64              # Experiences per training step

Exploration:
  epsilon_start: 1.0          # Initial exploration rate (100%)
  epsilon_end: 0.01           # Final exploration rate (1%)
  epsilon_decay: 0.9995       # Decay rate per episode

Memory:
  buffer_size: 100000         # Max experiences stored
  
Network Updates:
  target_update: 1000         # Steps between target network updates

Environment:
  max_moves: 100              # Max steps per episode (for 10x10 map)
```
---

## System Components

### 1. Training Script (`train_dqn.py`)

**Main Classes:**

- **`StateEncoder`**: Converts environment observations into neural network input
  ```python
  observation = {"position": 42, "target": 75, "time": 120}
  state_vector = encoder.encode(observation)  # → [0,0,...,1,...,0,0,...,1,...,0.5,0.3,...]
  ```

- **`DQNetwork`**: Neural network that predicts Q-values for each action
  ```python
  state = torch.tensor(state_vector)
  q_values = network(state)  # → [0.5, 0.8, 0.3, 0.9, 0.1]
  best_action = q_values.argmax()  # → 3 (RIGHT has highest value)
  ```

- **`ReplayBuffer`**: Stores and samples experiences
  ```python
  buffer.push(state, action, reward, next_state, done)
  batch = buffer.sample(64)  # Random sample for training
  ```

- **`DQNAgent`**: Manages the learning process
  ```python
  action = agent.select_action(state, epsilon=0.1)  # Choose action
  agent.train_step(batch)  # Learn from experiences
  ```

- **`TrainingManager`**: Orchestrates the entire training pipeline
  ```python
  manager = TrainingManager(env, agent, config)
  manager.train(num_episodes=10000)  # Run training
  ```

### 2. Evaluation Script (`evaluate_agent.py`)

Tests trained agents and generates performance statistics:

```python
# Evaluate best model on 100 episodes
results = evaluate_agent(
    model_path="checkpoints_backup/best_model.pt",
    num_episodes=100
)

# Results include:
# - Success rate: 85%
# - Average episode length: 25 steps
# - Average reward: +35
```

### 3. Baseline Comparison (`compare_agents.py`)

Compares trained agent against random baseline:

```python
# Random agent (baseline)
class RandomAgent:
    def select_action(self, state):
        return random.randint(0, 4)  # Random action

# Compare performance
trained_results = evaluate(trained_agent)  # 85% success
random_results = evaluate(random_agent)    # 10% success
```

### 4. Configuration Files

**`training_config.yaml`**: Training hyperparameters
```yaml
environment:
  map_file: "../maps/map_export_small.json"
  max_moves: 100

training:
  episodes: 10000
  batch_size: 64
  learning_rate: 0.001
  # ... more parameters
```

**`environment_rewards.yaml`**: Reward structure
```yaml
rewards:
  REACHING_TARGET_REWARD: 50
  APPROACHING_TARGET_REWARD: 1.0

punishments:
  EXISTENCE_PUNISHMENT: -0.5
  ILLEGAL_MOVE_PUNISHMENT: -5
  COLLISION_PUNISHMENT: -10
  MOVING_AWAY_PUNISHMENT: -1.0
```

---

## How It Works - Step by Step

### Phase 1: Initialization (First 5 seconds)

1. **Load Environment**
   ```
   Loading map: map_export_small.json (10x10 grid)
   ✓ Map loaded: 100 nodes, 180 connections
   ```

2. **Create Neural Network**
   ```
   Building DQN:
   - Input size: 208 features
   - Hidden layers: [256, 256, 128]
   - Output size: 5 actions
   ✓ Network created: 142,341 parameters
   ```

3. **Initialize Training Components**
   ```
   Setting up:
   - Replay buffer: 100,000 capacity
   - Target network: copy of policy network
   - Optimizer: Adam (lr=0.001)
   ✓ Ready to train
   ```

### Phase 2: Training Loop (2-10 hours)

**Episode Structure:**

```
Episode 1:
├─ Step 1: Start at position 42, target 75
│  ├─ State: [0,0,...,1,...,0,0,...,1,...,0.0,0.3,...]
│  ├─ Action: RIGHT (random, ε=1.0)
│  ├─ Reward: +1.0 (moved closer)
│  └─ Store: (state, RIGHT, +1.0, next_state, False)
│
├─ Step 2: Now at position 43
│  ├─ Action: DOWN (random, ε=1.0)
│  ├─ Reward: -1.0 (moved away)
│  └─ Store experience
│
├─ ... (more steps)
│
└─ Step 15: Reached target!
   ├─ Reward: +50 (success!)
   ├─ Episode reward: +35
   └─ Episode length: 15 steps
```

**Learning Process:**

Every step after the first 64 experiences:

```
1. Sample 64 random experiences from buffer
2. For each experience:
   - Predict Q-values for current state
   - Calculate target: reward + 0.99 × max(Q-values for next state)
   - Compute loss: (predicted - target)²
3. Update network using backpropagation
4. Every 1000 steps: update target network
```

### Phase 3: Checkpointing (Every 100 episodes)

```
Episode 100 complete:
├─ Save checkpoint: checkpoints/checkpoint_ep100.pt
├─ Save metrics: checkpoints/metrics_ep100.json
└─ Check if best model:
   ├─ Current avg reward: +2.1
   ├─ Previous best: -5.2
   └─ ✓ New best! Save to: checkpoints_backup/best_model.pt
```

### Phase 4: Evaluation (After training)

```bash
$ python evaluate_agent.py --checkpoint checkpoints_backup/best_model.pt --episodes 100

Evaluating agent...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ 100/100

Results:
├─ Success Rate: 92%
├─ Average Episode Length: 15.3 steps
├─ Average Reward: +38.2
└─ Evaluation complete!
```
---