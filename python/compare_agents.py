"""
Comparison script: Trained Agent vs Random Baseline
Evaluates both agents to show the actual improvement from training
"""

import numpy as np
import torch
import argparse
from pathlib import Path
from typing import Dict, List
import json

from environment import Environment, Action
from train_dqn import DQNAgent, StateEncoder


class RandomAgent:
    """Baseline agent that selects random valid actions"""
    
    def __init__(self):
        self.name = "Random Baseline"
    
    def select_action(self, state, valid_actions, training=False):
        """Select random action from valid actions"""
        return np.random.choice(valid_actions)


class AgentComparator:
    """Compare trained agent vs random baseline"""
    
    def __init__(self, env: Environment, state_encoder: StateEncoder):
        self.env = env
        self.state_encoder = state_encoder
        
        self.action_list = [Action.UP, Action.DOWN, Action.LEFT, Action.RIGHT, Action.WAIT]
        self.action_to_idx = {action: idx for idx, action in enumerate(self.action_list)}
        self.idx_to_action = {idx: action for action, idx in self.action_to_idx.items()}
    
    def get_valid_actions(self, position: int) -> List[int]:
        """Get list of valid action indices for current position"""
        valid_actions = []
        for action in self.action_list:
            next_node, _ = self.env.grid.nodes[position][action]
            if next_node is not None:
                valid_actions.append(self.action_to_idx[action])
        return valid_actions
    
    def evaluate_agent(self, agent, num_episodes: int = 100, verbose: bool = False) -> Dict:
        """Evaluate agent over multiple episodes"""
        results = {
            'rewards': [],
            'lengths': [],
            'successes': [],
            'travel_times': [],
            'distances': [],
            'initial_distances': []
        }
        
        for episode in range(num_episodes):
            self.env.reset()
            
            # Store initial distance for analysis
            initial_distance = self.env.grid.distance(
                self.env.agent.position, 
                self.env.agent.target
            )
            results['initial_distances'].append(initial_distance)
            
            info = self.env.get_info()
            state = self.state_encoder.encode(info['observation'], info['departures'])
            
            episode_reward = 0
            episode_length = 0
            
            while not self.env.finished and not self.env.interrupted:
                valid_actions = self.get_valid_actions(self.env.agent.position)
                action_idx = agent.select_action(state, valid_actions, training=False)
                action = self.idx_to_action[action_idx]
                
                reward = self.env.update(action)
                episode_reward += reward
                episode_length += 1
                
                info = self.env.get_info()
                state = self.state_encoder.encode(info['observation'], info['departures'])
            
            results['rewards'].append(episode_reward)
            results['lengths'].append(episode_length)
            results['successes'].append(1 if self.env.finished else 0)
            results['travel_times'].append(self.env.agent.travel_time)
            results['distances'].append(self.env.agent.distance_traveled)
            
            if verbose and (episode + 1) % 10 == 0:
                print(f"  Episode {episode + 1}/{num_episodes} completed")
        
        return results
    
    def print_comparison(self, trained_results: Dict, random_results: Dict):
        """Print detailed comparison between agents"""
        
        print("\n" + "="*80)
        print("AGENT COMPARISON RESULTS")
        print("="*80)
        
        # Calculate statistics
        metrics = [
            ('Average Reward', 'rewards'),
            ('Average Episode Length', 'lengths'),
            ('Success Rate (%)', 'successes'),
            ('Average Travel Time (min)', 'travel_times'),
            ('Average Distance Traveled', 'distances'),
            ('Average Initial Distance', 'initial_distances')
        ]
        
        print(f"\n{'Metric':<35} {'Random':<15} {'Trained':<15} {'Improvement':<15}")
        print("-" * 80)
        
        for metric_name, metric_key in metrics:
            random_val = np.mean(random_results[metric_key])
            trained_val = np.mean(trained_results[metric_key])
            
            if metric_key == 'successes':
                random_val *= 100
                trained_val *= 100
                improvement = trained_val - random_val
                print(f"{metric_name:<35} {random_val:>6.1f}%        {trained_val:>6.1f}%        {improvement:>+6.1f}%")
            else:
                if random_val != 0:
                    improvement_pct = ((trained_val - random_val) / abs(random_val)) * 100
                    print(f"{metric_name:<35} {random_val:>12.2f}   {trained_val:>12.2f}   {improvement_pct:>+6.1f}%")
                else:
                    print(f"{metric_name:<35} {random_val:>12.2f}   {trained_val:>12.2f}   N/A")
        
        print("\n" + "="*80)
        print("DETAILED STATISTICS")
        print("="*80)
        
        # Detailed breakdown
        for agent_name, results in [("Random Agent", random_results), ("Trained Agent", trained_results)]:
            print(f"\n{agent_name}:")
            print(f"  Reward:        μ={np.mean(results['rewards']):>8.2f}  σ={np.std(results['rewards']):>8.2f}  "
                  f"min={np.min(results['rewards']):>8.2f}  max={np.max(results['rewards']):>8.2f}")
            print(f"  Length:        μ={np.mean(results['lengths']):>8.2f}  σ={np.std(results['lengths']):>8.2f}  "
                  f"min={np.min(results['lengths']):>8.0f}  max={np.max(results['lengths']):>8.0f}")
            print(f"  Success Rate:  {np.mean(results['successes'])*100:>6.1f}%")
            print(f"  Travel Time:   μ={np.mean(results['travel_times']):>8.2f}  σ={np.std(results['travel_times']):>8.2f}")
        
        print("\n" + "="*80)
        
        # Key insights
        print("\nKEY INSIGHTS:")
        print("-" * 80)
        
        random_success = np.mean(random_results['successes']) * 100
        trained_success = np.mean(trained_results['successes']) * 100
        
        if trained_success > random_success + 10:
            print("✓ Training significantly improved success rate")
        elif trained_success > random_success:
            print("⚠ Training slightly improved success rate")
        else:
            print("✗ Training did not improve success rate - needs investigation")
        
        random_length = np.mean(random_results['lengths'])
        trained_length = np.mean(trained_results['lengths'])
        
        if trained_length < random_length * 0.7:
            print("✓ Trained agent is much more efficient (shorter episodes)")
        elif trained_length < random_length:
            print("⚠ Trained agent is somewhat more efficient")
        else:
            print("✗ Trained agent is not more efficient - needs investigation")
        
        random_reward = np.mean(random_results['rewards'])
        trained_reward = np.mean(trained_results['rewards'])
        
        if trained_reward > random_reward * 2:
            print("✓ Trained agent achieves much higher rewards")
        elif trained_reward > random_reward:
            print("⚠ Trained agent achieves higher rewards")
        else:
            print("✗ Trained agent does not achieve higher rewards - needs investigation")
        
        print("\n" + "="*80)


def main():
    parser = argparse.ArgumentParser(description='Compare trained agent vs random baseline')
    parser.add_argument('--model', type=str, default='checkpoints/best_model.pt',
                       help='Path to trained model')
    parser.add_argument('--map', type=str, default='map_export.json',
                       help='Map file to use')
    parser.add_argument('--episodes', type=int, default=100,
                       help='Number of evaluation episodes')
    parser.add_argument('--max-steps', type=int, default=200,
                       help='Maximum steps per episode')
    parser.add_argument('--seed', type=int, default=42,
                       help='Random seed')
    parser.add_argument('--save-results', type=str, default=None,
                       help='Save results to JSON file')
    
    args = parser.parse_args()
    
    print("="*80)
    print("AGENT COMPARISON: Trained vs Random Baseline")
    print("="*80)
    print(f"\nConfiguration:")
    print(f"  Model: {args.model}")
    print(f"  Map: {args.map}")
    print(f"  Episodes: {args.episodes}")
    print(f"  Max steps: {args.max_steps}")
    print(f"  Seed: {args.seed}")
    
    # Initialize environment
    print("\nInitializing environment...")
    env = Environment(args.map, max_moves=args.max_steps, seed=args.seed)
    
    # Create state encoder
    print("Creating state encoder...")
    state_encoder = StateEncoder(env.grid.nodes)
    
    # Initialize agents
    print("Loading trained agent...")
    trained_agent = DQNAgent(
        state_size=state_encoder.state_size,
        action_size=5,
        learning_rate=0.0001,
        gamma=0.99,
        epsilon_start=0.0,  # No exploration during evaluation
        epsilon_end=0.0,
        epsilon_decay=1.0,
        buffer_size=1000,
        batch_size=32,
        target_update_freq=1000
    )
    
    if Path(args.model).exists():
        trained_agent.load(args.model)
        print(f"✓ Loaded model from {args.model}")
    else:
        print(f"✗ Model not found: {args.model}")
        print("  Training a model first with: python train_dqn.py")
        return
    
    print("Creating random baseline agent...")
    random_agent = RandomAgent()
    
    # Create comparator
    comparator = AgentComparator(env, state_encoder)
    
    # Evaluate random agent
    print(f"\nEvaluating RANDOM agent ({args.episodes} episodes)...")
    random_results = comparator.evaluate_agent(random_agent, args.episodes, verbose=True)
    
    # Evaluate trained agent
    print(f"\nEvaluating TRAINED agent ({args.episodes} episodes)...")
    trained_results = comparator.evaluate_agent(trained_agent, args.episodes, verbose=True)
    
    # Print comparison
    comparator.print_comparison(trained_results, random_results)
    
    # Save results if requested
    if args.save_results:
        results = {
            'config': vars(args),
            'random': {k: [float(v) for v in vals] for k, vals in random_results.items()},
            'trained': {k: [float(v) for v in vals] for k, vals in trained_results.items()}
        }
        
        with open(args.save_results, 'w') as f:
            json.dump(results, f, indent=2)
        
        print(f"\n✓ Results saved to {args.save_results}")


if __name__ == "__main__":
    main()
