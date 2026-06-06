"""
Evaluation script for trained DQN agents

This script loads a trained model and evaluates its performance
on the public transport navigation task.
"""

import numpy as np
import torch
from pathlib import Path
import json
from typing import Dict, List

from environment import Environment, Action
from train_dqn import DQNAgent, StateEncoder


class AgentEvaluator:
    """Evaluates trained agent performance"""
    
    def __init__(self, env: Environment, agent: DQNAgent, state_encoder: StateEncoder):
        self.env = env
        self.agent = agent
        self.state_encoder = state_encoder
        
        # Action mapping
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
    
    def evaluate_episode(self, verbose: bool = True) -> Dict:
        """Evaluate agent on one episode"""
        self.env.reset()
        
        # Get initial state
        info = self.env.get_info()
        state = self.state_encoder.encode(info['observation'], info['departures'])
        
        episode_reward = 0
        episode_length = 0
        actions_taken = []
        
        if verbose:
            print(f"\nStarting position: {self.env.agent.position}")
            print(f"Target position: {self.env.agent.target}")
            print(f"Initial distance: {self.env.grid.distance(self.env.agent.position, self.env.agent.target)}")
            print("-" * 60)
        
        while not self.env.finished and not self.env.interrupted:
            # Get valid actions
            valid_actions = self.get_valid_actions(self.env.agent.position)
            
            # Select action (greedy, no exploration)
            action_idx = self.agent.select_action(state, valid_actions, training=False)
            action = self.idx_to_action[action_idx]
            actions_taken.append(action.value)
            
            if verbose:
                print(f"Step {episode_length + 1}: Position {self.env.agent.position} -> Action {action.value}", end="")
            
            # Take action
            reward = self.env.update(action)
            episode_reward += reward
            episode_length += 1
            
            if verbose:
                print(f" -> New position {self.env.agent.position} (Reward: {reward:.2f})")
            
            # Get next state
            info = self.env.get_info()
            state = self.state_encoder.encode(info['observation'], info['departures'])
        
        success = self.env.finished
        
        if verbose:
            print("-" * 60)
            if success:
                print(f"✓ SUCCESS! Reached target in {episode_length} steps")
            else:
                print(f"✗ FAILED! Interrupted after {episode_length} steps")
            print(f"Total reward: {episode_reward:.2f}")
            print(f"Travel time: {self.env.agent.travel_time} minutes")
            print(f"Distance traveled: {self.env.agent.distance_traveled:.2f}")
        
        return {
            'success': success,
            'reward': episode_reward,
            'length': episode_length,
            'travel_time': self.env.agent.travel_time,
            'distance_traveled': self.env.agent.distance_traveled,
            'actions': actions_taken,
            'path': self.env.agent.path,
            'initial_position': self.env.agent._initial_position,
            'target_position': self.env.agent.target,
        }
    
    def evaluate_multiple(self, num_episodes: int = 100, verbose: bool = False) -> Dict:
        """Evaluate agent over multiple episodes"""
        print(f"\nEvaluating agent over {num_episodes} episodes...")
        print("=" * 60)
        
        results = []
        for i in range(num_episodes):
            if (i + 1) % 10 == 0:
                print(f"Episode {i + 1}/{num_episodes}")
            
            result = self.evaluate_episode(verbose=verbose)
            results.append(result)
        
        # Compute statistics
        successes = [r['success'] for r in results]
        rewards = [r['reward'] for r in results]
        lengths = [r['length'] for r in results]
        travel_times = [r['travel_time'] for r in results]
        distances = [r['distance_traveled'] for r in results]
        
        success_rate = np.mean(successes) * 100
        avg_reward = np.mean(rewards)
        avg_length = np.mean(lengths)
        avg_travel_time = np.mean(travel_times)
        avg_distance = np.mean(distances)
        
        # Statistics for successful episodes only
        successful_results = [r for r in results if r['success']]
        if successful_results:
            avg_success_length = np.mean([r['length'] for r in successful_results])
            avg_success_time = np.mean([r['travel_time'] for r in successful_results])
            avg_success_distance = np.mean([r['distance_traveled'] for r in successful_results])
        else:
            avg_success_length = 0
            avg_success_time = 0
            avg_success_distance = 0
        
        print("\n" + "=" * 60)
        print("EVALUATION RESULTS")
        print("=" * 60)
        print(f"Success Rate:           {success_rate:.1f}%")
        print(f"Average Reward:         {avg_reward:.2f}")
        print(f"Average Episode Length: {avg_length:.1f} steps")
        print(f"Average Travel Time:    {avg_travel_time:.1f} minutes")
        print(f"Average Distance:       {avg_distance:.2f}")
        print()
        print("Successful Episodes Only:")
        print(f"  Average Length:       {avg_success_length:.1f} steps")
        print(f"  Average Travel Time:  {avg_success_time:.1f} minutes")
        print(f"  Average Distance:     {avg_success_distance:.2f}")
        print("=" * 60)
        
        return {
            'num_episodes': num_episodes,
            'success_rate': success_rate,
            'avg_reward': avg_reward,
            'avg_length': avg_length,
            'avg_travel_time': avg_travel_time,
            'avg_distance': avg_distance,
            'avg_success_length': avg_success_length,
            'avg_success_time': avg_success_time,
            'avg_success_distance': avg_success_distance,
            'all_results': results,
        }


def load_trained_agent(checkpoint_path: str, env: Environment, state_encoder: StateEncoder) -> DQNAgent:
    """Load a trained agent from checkpoint"""
    state_size = state_encoder.state_size
    action_size = len([Action.UP, Action.DOWN, Action.LEFT, Action.RIGHT, Action.WAIT])
    
    agent = DQNAgent(
        state_size=state_size,
        action_size=action_size,
    )
    
    agent.load(checkpoint_path)
    agent.policy_net.eval()  # Set to evaluation mode
    
    return agent


def main():
    """Main evaluation function"""
    import argparse
    
    parser = argparse.ArgumentParser(description='Evaluate trained DQN agent')
    parser.add_argument('--checkpoint', type=str, default='checkpoints_backup/best_model.pt',
                       help='Path to model checkpoint')
    parser.add_argument('--map', type=str, default='map_export.json',
                       help='Map file to use')
    parser.add_argument('--episodes', type=int, default=100,
                       help='Number of episodes to evaluate')
    parser.add_argument('--verbose', action='store_true',
                       help='Print detailed episode information')
    parser.add_argument('--seed', type=int, default=None,
                       help='Random seed for reproducibility')
    parser.add_argument('--save-results', type=str, default=None,
                       help='Path to save evaluation results JSON')
    
    args = parser.parse_args()
    
    # Create environment
    print("Initializing environment...")
    env = Environment(args.map, max_moves=1440, seed=args.seed)
    
    # Create state encoder
    print("Creating state encoder...")
    state_encoder = StateEncoder(env.grid.nodes)
    
    # Load trained agent
    print(f"Loading trained agent from {args.checkpoint}...")
    agent = load_trained_agent(args.checkpoint, env, state_encoder)
    
    # Create evaluator
    evaluator = AgentEvaluator(env, agent, state_encoder)
    
    # Evaluate
    if args.episodes == 1:
        # Single episode with verbose output
        result = evaluator.evaluate_episode(verbose=True)
    else:
        # Multiple episodes
        results = evaluator.evaluate_multiple(num_episodes=args.episodes, verbose=args.verbose)
        
        # Save results if requested
        if args.save_results:
            save_path = Path(args.save_results)
            save_path.parent.mkdir(parents=True, exist_ok=True)
            with open(save_path, 'w') as f:
                json.dump(results, f, indent=2)
            print(f"\nResults saved to {save_path}")


if __name__ == "__main__":
    main()

# Made with Bob
