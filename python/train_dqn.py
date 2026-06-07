import random
import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim
from collections import deque, namedtuple
import json
import os
from datetime import datetime
from pathlib import Path
import matplotlib.pyplot as plt
from typing import Dict, List, Tuple, Optional

from environment import Environment, Action

Experience = namedtuple('Experience', ['state', 'action', 'reward', 'next_state', 'done'])


class StateEncoder:
    
    def __init__(self, grid_nodes: Dict):
        self.grid_nodes = grid_nodes
        self.node_list = sorted(list(grid_nodes.keys()))
        self.node_to_idx = {node: idx for idx, node in enumerate(self.node_list)}
        self.num_nodes = len(self.node_list)
        
    def encode(self, observation: Dict, departures: Dict) -> np.ndarray:
        position = observation['position']
        target = observation['target']
        time = observation['time']

        position_vec = np.zeros(self.num_nodes, dtype=np.float32)
        position_vec[self.node_to_idx[position]] = 1.0

        target_vec = np.zeros(self.num_nodes, dtype=np.float32)
        target_vec[self.node_to_idx[target]] = 1.0

        time_normalized = np.array([time / 1440.0], dtype=np.float32)

        distance = self._manhattan_distance(position, target)
        max_distance = self.num_nodes
        distance_normalized = np.array([distance / max_distance], dtype=np.float32)

        departure_features = self._encode_departures(departures, time)

        state_vector = np.concatenate([
            position_vec,
            target_vec,
            time_normalized,
            distance_normalized,
            departure_features
        ])
        
        return state_vector
    
    def _manhattan_distance(self, pos1: int, pos2: int) -> float:
        return abs(pos1 - pos2)
    
    def _encode_departures(self, departures: Dict, current_time: int) -> np.ndarray:
        features = []

        line_counts = {}
        for line, deps in departures.items():
            count = sum(1 for d in deps if current_time <= d['tick'] < current_time + 60)
            line_counts[line] = count

        top_lines = sorted(line_counts.items(), key=lambda x: x[1], reverse=True)[:5]
        
        for _, count in top_lines:
            features.append(count / 10.0)  # Normalize

        while len(features) < 5:
            features.append(0.0)
        
        return np.array(features, dtype=np.float32)
    
    @property
    def state_size(self) -> int:
        return self.num_nodes * 2 + 1 + 1 + 5


class DQNetwork(nn.Module):
    
    def __init__(self, state_size: int, action_size: int, hidden_sizes: List[int] = [256, 256, 128]):
        super(DQNetwork, self).__init__()
        
        layers = []
        input_size = state_size
        
        for hidden_size in hidden_sizes:
            layers.append(nn.Linear(input_size, hidden_size))
            layers.append(nn.ReLU())
            layers.append(nn.Dropout(0.2))
            input_size = hidden_size
        
        layers.append(nn.Linear(input_size, action_size))
        
        self.network = nn.Sequential(*layers)
        
    def forward(self, state: torch.Tensor) -> torch.Tensor:
        return self.network(state)


class ReplayBuffer:
    
    def __init__(self, capacity: int = 100000):
        self.buffer = deque(maxlen=capacity)
    
    def push(self, experience: Experience):
        self.buffer.append(experience)
    
    def sample(self, batch_size: int) -> List[Experience]:
        return random.sample(self.buffer, batch_size)
    
    def __len__(self) -> int:
        return len(self.buffer)


class DQNAgent:
    
    def __init__(
        self,
        state_size: int,
        action_size: int,
        learning_rate: float = 0.0001,
        gamma: float = 0.99,
        epsilon_start: float = 1.0,
        epsilon_end: float = 0.01,
        epsilon_decay: float = 0.995,
        buffer_size: int = 100000,
        batch_size: int = 64,
        target_update_freq: int = 1000,
        device: str = 'cuda' if torch.cuda.is_available() else 'cpu'
    ):
        self.state_size = state_size
        self.action_size = action_size
        self.gamma = gamma
        self.epsilon = epsilon_start
        self.epsilon_end = epsilon_end
        self.epsilon_decay = epsilon_decay
        self.batch_size = batch_size
        self.target_update_freq = target_update_freq
        self.device = device

        self.policy_net = DQNetwork(state_size, action_size).to(device)
        self.target_net = DQNetwork(state_size, action_size).to(device)
        self.target_net.load_state_dict(self.policy_net.state_dict())
        self.target_net.eval()

        self.optimizer = optim.Adam(self.policy_net.parameters(), lr=learning_rate)

        self.memory = ReplayBuffer(buffer_size)

        self.steps = 0
        
    def select_action(self, state: np.ndarray, valid_actions: List[int], training: bool = True) -> int:
        if training and random.random() < self.epsilon:
            return random.choice(valid_actions)

        with torch.no_grad():
            state_tensor = torch.FloatTensor(state).unsqueeze(0).to(self.device)
            q_values = self.policy_net(state_tensor).cpu().numpy()[0]

            masked_q_values = np.full(self.action_size, -np.inf)
            masked_q_values[valid_actions] = q_values[valid_actions]
            
            return int(np.argmax(masked_q_values))
    
    def store_experience(self, state: np.ndarray, action: int, reward: float, 
                        next_state: np.ndarray, done: bool):
        self.memory.push(Experience(state, action, reward, next_state, done))
    
    def train_step(self) -> Optional[float]:
        if len(self.memory) < self.batch_size:
            return None

        experiences = self.memory.sample(self.batch_size)
        batch = Experience(*zip(*experiences))

        state_batch = torch.FloatTensor(np.array(batch.state)).to(self.device)
        action_batch = torch.LongTensor(batch.action).unsqueeze(1).to(self.device)
        reward_batch = torch.FloatTensor(batch.reward).to(self.device)
        next_state_batch = torch.FloatTensor(np.array(batch.next_state)).to(self.device)
        done_batch = torch.FloatTensor(batch.done).to(self.device)

        current_q_values = self.policy_net(state_batch).gather(1, action_batch)

        with torch.no_grad():
            next_q_values = self.target_net(next_state_batch).max(1)[0]
            target_q_values = reward_batch + (1 - done_batch) * self.gamma * next_q_values

        loss = nn.MSELoss()(current_q_values.squeeze(), target_q_values)

        self.optimizer.zero_grad()
        loss.backward()
        torch.nn.utils.clip_grad_norm_(self.policy_net.parameters(), 1.0)
        self.optimizer.step()

        self.steps += 1
        if self.steps % self.target_update_freq == 0:
            self.target_net.load_state_dict(self.policy_net.state_dict())

        self.epsilon = max(self.epsilon_end, self.epsilon * self.epsilon_decay)
        
        return loss.item()
    
    def save(self, filepath: str):
        torch.save({
            'policy_net_state_dict': self.policy_net.state_dict(),
            'target_net_state_dict': self.target_net.state_dict(),
            'optimizer_state_dict': self.optimizer.state_dict(),
            'epsilon': self.epsilon,
            'steps': self.steps,
        }, filepath)
    
    def load(self, filepath: str):
        checkpoint = torch.load(filepath, map_location=self.device)
        self.policy_net.load_state_dict(checkpoint['policy_net_state_dict'])
        self.target_net.load_state_dict(checkpoint['target_net_state_dict'])
        self.optimizer.load_state_dict(checkpoint['optimizer_state_dict'])
        self.epsilon = checkpoint['epsilon']
        self.steps = checkpoint['steps']


class TrainingManager:
    
    def __init__(
        self,
        env: Environment,
        agent: DQNAgent,
        state_encoder: StateEncoder,
        checkpoint_dir: str = 'checkpoints',
        backup_dir: str = 'checkpoints_backup',
        log_interval: int = 10,
        save_interval: int = 100
    ):
        self.env = env
        self.agent = agent
        self.state_encoder = state_encoder
        self.checkpoint_dir = Path(checkpoint_dir)
        self.backup_dir = Path(backup_dir)
        self.log_interval = log_interval
        self.save_interval = save_interval

        self.checkpoint_dir.mkdir(exist_ok=True)
        self.backup_dir.mkdir(exist_ok=True)

        self.episode_rewards = []
        self.episode_lengths = []
        self.episode_success = []
        self.losses = []
        self.best_avg_reward = -np.inf

        self.action_list = [Action.UP, Action.DOWN, Action.LEFT, Action.RIGHT, Action.WAIT]
        self.action_to_idx = {action: idx for idx, action in enumerate(self.action_list)}
        self.idx_to_action = {idx: action for action, idx in self.action_to_idx.items()}
    
    def get_valid_actions(self, position: int) -> List[int]:
        valid_actions = []
        for action in self.action_list:
            next_node, _ = self.env.grid.nodes[position][action]
            if next_node is not None:
                valid_actions.append(self.action_to_idx[action])
        return valid_actions
    
    def train_episode(self) -> Tuple[float, int, bool]:
        self.env.reset()

        info = self.env.get_info()
        state = self.state_encoder.encode(info['observation'], info['departures'])
        
        episode_reward = 0
        episode_length = 0
        
        while not self.env.finished and not self.env.interrupted:
            valid_actions = self.get_valid_actions(self.env.agent.position)

            action_idx = self.agent.select_action(state, valid_actions, training=True)
            action = self.idx_to_action[action_idx]

            reward = self.env.update(action)
            episode_reward += reward
            episode_length += 1

            info = self.env.get_info()
            next_state = self.state_encoder.encode(info['observation'], info['departures'])

            done = self.env.finished or self.env.interrupted
            self.agent.store_experience(state, action_idx, reward, next_state, done)

            loss = self.agent.train_step()
            if loss is not None:
                self.losses.append(loss)
            
            state = next_state
        
        success = self.env.finished
        return episode_reward, episode_length, success
    
    def train(self, num_episodes: int, resume: bool = False):
        start_episode = 0

        if resume:
            start_episode = self.load_checkpoint()
        
        print(f"Starting training from episode {start_episode}")
        print(f"Device: {self.agent.device}")
        print(f"State size: {self.agent.state_size}")
        print(f"Action size: {self.agent.action_size}")
        print("-" * 80)
        
        for episode in range(start_episode, num_episodes):
            episode_reward, episode_length, success = self.train_episode()

            self.episode_rewards.append(episode_reward)
            self.episode_lengths.append(episode_length)
            self.episode_success.append(1 if success else 0)

            if (episode + 1) % self.log_interval == 0:
                self._log_progress(episode + 1)

            if (episode + 1) % self.save_interval == 0:
                self._save_checkpoint(episode + 1)
        
        print("\nTraining completed!")
        self._save_final_results()
    
    def _log_progress(self, episode: int):
        recent_rewards = self.episode_rewards[-self.log_interval:]
        recent_lengths = self.episode_lengths[-self.log_interval:]
        recent_success = self.episode_success[-self.log_interval:]
        recent_losses = self.losses[-100:] if self.losses else [0]
        
        avg_reward = np.mean(recent_rewards)
        avg_length = np.mean(recent_lengths)
        success_rate = np.mean(recent_success) * 100
        avg_loss = np.mean(recent_losses)
        
        print(f"Episode {episode:6d} | "
              f"Avg Reward: {avg_reward:8.2f} | "
              f"Avg Length: {avg_length:6.1f} | "
              f"Success Rate: {success_rate:5.1f}% | "
              f"Loss: {avg_loss:8.4f} | "
              f"Epsilon: {self.agent.epsilon:.4f}")

        if avg_reward > self.best_avg_reward:
            self.best_avg_reward = avg_reward
            self._save_best_model()
    
    def _save_checkpoint(self, episode: int):
        checkpoint_path = self.checkpoint_dir / f'checkpoint_ep{episode}.pt'

        self.agent.save(checkpoint_path)

        metrics_path = self.checkpoint_dir / f'metrics_ep{episode}.json'
        metrics = {
            'episode': episode,
            'episode_rewards': self.episode_rewards,
            'episode_lengths': self.episode_lengths,
            'episode_success': self.episode_success,
            'best_avg_reward': self.best_avg_reward,
        }
        with open(metrics_path, 'w') as f:
            json.dump(metrics, f, indent=2)
        
        print(f"Checkpoint saved: {checkpoint_path}")
    
    def _save_best_model(self):
        best_model_path = self.backup_dir / 'best_model.pt'
        self.agent.save(best_model_path)

        metadata_path = self.backup_dir / 'best_model_info.json'
        metadata = {
            'best_avg_reward': self.best_avg_reward,
            'episode': len(self.episode_rewards),
            'timestamp': datetime.now().isoformat(),
        }
        with open(metadata_path, 'w') as f:
            json.dump(metadata, f, indent=2)
        
        print(f"New best model saved! Avg Reward: {self.best_avg_reward:.2f}")
    
    def _save_final_results(self):
        final_path = self.checkpoint_dir / 'final_model.pt'
        self.agent.save(final_path)
        
        # Save all metrics
        metrics_path = self.checkpoint_dir / 'final_metrics.json'
        metrics = {
            'episode_rewards': self.episode_rewards,
            'episode_lengths': self.episode_lengths,
            'episode_success': self.episode_success,
            'best_avg_reward': self.best_avg_reward,
        }
        with open(metrics_path, 'w') as f:
            json.dump(metrics, f, indent=2)

        self._plot_training_curves()
    
    def _plot_training_curves(self):
        fig, axes = plt.subplots(2, 2, figsize=(15, 10))
        
        # Rewards
        axes[0, 0].plot(self.episode_rewards, alpha=0.3, label='Episode Reward')
        if len(self.episode_rewards) >= 100:
            smoothed = np.convolve(self.episode_rewards, np.ones(100)/100, mode='valid')
            axes[0, 0].plot(smoothed, label='Moving Average (100 ep)')
        axes[0, 0].set_xlabel('Episode')
        axes[0, 0].set_ylabel('Reward')
        axes[0, 0].set_title('Episode Rewards')
        axes[0, 0].legend()
        axes[0, 0].grid(True)
        
        # Episode lengths
        axes[0, 1].plot(self.episode_lengths, alpha=0.3, label='Episode Length')
        if len(self.episode_lengths) >= 100:
            smoothed = np.convolve(self.episode_lengths, np.ones(100)/100, mode='valid')
            axes[0, 1].plot(smoothed, label='Moving Average (100 ep)')
        axes[0, 1].set_xlabel('Episode')
        axes[0, 1].set_ylabel('Steps')
        axes[0, 1].set_title('Episode Lengths')
        axes[0, 1].legend()
        axes[0, 1].grid(True)

        if len(self.episode_success) >= 100:
            success_rate = np.convolve(self.episode_success, np.ones(100)/100, mode='valid') * 100
            axes[1, 0].plot(success_rate)
        axes[1, 0].set_xlabel('Episode')
        axes[1, 0].set_ylabel('Success Rate (%)')
        axes[1, 0].set_title('Success Rate (100 ep moving average)')
        axes[1, 0].grid(True)
        
        # Loss
        if self.losses:
            axes[1, 1].plot(self.losses, alpha=0.3, label='Loss')
            if len(self.losses) >= 100:
                smoothed = np.convolve(self.losses, np.ones(100)/100, mode='valid')
                axes[1, 1].plot(smoothed, label='Moving Average (100 steps)')
            axes[1, 1].set_xlabel('Training Step')
            axes[1, 1].set_ylabel('Loss')
            axes[1, 1].set_title('Training Loss')
            axes[1, 1].legend()
            axes[1, 1].grid(True)
        
        plt.tight_layout()
        plot_path = self.checkpoint_dir / 'training_curves.png'
        plt.savefig(plot_path, dpi=150)
        print(f"Training curves saved: {plot_path}")
        plt.close()
    
    def load_checkpoint(self, episode: Optional[int] = None) -> int:
        if episode is None:
            # Find latest checkpoint
            checkpoints = list(self.checkpoint_dir.glob('checkpoint_ep*.pt'))
            if not checkpoints:
                print("No checkpoints found, starting from scratch")
                return 0

            latest = max(checkpoints, key=lambda p: int(p.stem.split('ep')[1]))
            episode = int(latest.stem.split('ep')[1])
        
        checkpoint_path = self.checkpoint_dir / f'checkpoint_ep{episode}.pt'
        metrics_path = self.checkpoint_dir / f'metrics_ep{episode}.json'
        
        if not checkpoint_path.exists():
            print(f"Checkpoint not found: {checkpoint_path}")
            return 0

        self.agent.load(checkpoint_path)

        if metrics_path.exists():
            with open(metrics_path, 'r') as f:
                metrics = json.load(f)
            self.episode_rewards = metrics['episode_rewards']
            self.episode_lengths = metrics['episode_lengths']
            self.episode_success = metrics['episode_success']
            self.best_avg_reward = metrics['best_avg_reward']
        
        print(f"Resumed from episode {episode}")
        return episode


def main():
    # Configuration
    MAP_FILE = "map_export.json"
    NUM_EPISODES = 10000
    RESUME_TRAINING = False

    LEARNING_RATE = 0.0001
    GAMMA = 0.99
    EPSILON_START = 1.0
    EPSILON_END = 0.01
    EPSILON_DECAY = 0.9995
    BUFFER_SIZE = 100000
    BATCH_SIZE = 64
    TARGET_UPDATE_FREQ = 1000

    print("Initializing environment...")
    env = Environment(MAP_FILE, max_moves=1440, seed=42)

    print("Creating state encoder...")
    state_encoder = StateEncoder(env.grid.nodes)
    state_size = state_encoder.state_size
    action_size = len([Action.UP, Action.DOWN, Action.LEFT, Action.RIGHT, Action.WAIT])
    
    print(f"State size: {state_size}")
    print(f"Action size: {action_size}")

    print("Creating DQN agent...")
    agent = DQNAgent(
        state_size=state_size,
        action_size=action_size,
        learning_rate=LEARNING_RATE,
        gamma=GAMMA,
        epsilon_start=EPSILON_START,
        epsilon_end=EPSILON_END,
        epsilon_decay=EPSILON_DECAY,
        buffer_size=BUFFER_SIZE,
        batch_size=BATCH_SIZE,
        target_update_freq=TARGET_UPDATE_FREQ
    )

    print("Creating training manager...")
    trainer = TrainingManager(
        env=env,
        agent=agent,
        state_encoder=state_encoder,
        checkpoint_dir='checkpoints',
        backup_dir='checkpoints_backup',
        log_interval=10,
        save_interval=100
    )

    print("\n" + "="*80)
    print("STARTING TRAINING")
    print("="*80 + "\n")
    
    try:
        trainer.train(num_episodes=NUM_EPISODES, resume=RESUME_TRAINING)
    except KeyboardInterrupt:
        print("\n\nTraining interrupted by user")
        print("Saving current progress...")
        trainer._save_checkpoint(len(trainer.episode_rewards))
        print("Progress saved!")


if __name__ == "__main__":
    main()
