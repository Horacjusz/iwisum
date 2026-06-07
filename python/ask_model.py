"""
Model inference module for IWISUM simulation.
This module loads the trained DQN model and provides action predictions for passengers.
"""

from __future__ import annotations
from enum import Enum
from typing import Any, Dict, List, Optional
from pathlib import Path
import numpy as np
import torch
import torch.nn as nn

# Try to import from environment, fallback to local definition
try:
    from environment import Action, Environment
    from loader import load_map
except ModuleNotFoundError:
    class Action(Enum):
        UP = "UP"
        DOWN = "DOWN"
        LEFT = "LEFT"
        RIGHT = "RIGHT"
        WAIT = "WAIT"


# Neural network architecture (must match training)
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


# State encoder (must match training)
class StateEncoder:
    def __init__(self, grid_nodes: Dict):
        self.grid_nodes = grid_nodes
        self.node_list = sorted(list(grid_nodes.keys()))
        self.node_to_idx = {node: idx for idx, node in enumerate(self.node_list)}
        self.num_nodes = len(self.node_list)
        
    def encode(self, observation: Dict) -> np.ndarray:
        """Encode observation into state vector for the model."""
        position = observation['position']
        target = observation['target']
        time = observation['time']

        # One-hot encode position
        position_vec = np.zeros(self.num_nodes, dtype=np.float32)
        position_vec[self.node_to_idx[position]] = 1.0

        # One-hot encode target
        target_vec = np.zeros(self.num_nodes, dtype=np.float32)
        target_vec[self.node_to_idx[target]] = 1.0

        # Normalize time (0-1440 minutes -> 0-1)
        time_normalized = np.array([time / 1440.0], dtype=np.float32)

        # Calculate and normalize distance
        distance = abs(position - target)  # Manhattan distance
        max_distance = self.num_nodes
        distance_normalized = np.array([distance / max_distance], dtype=np.float32)

        # Departure features (simplified - no departure info from Godot yet)
        departure_features = np.zeros(5, dtype=np.float32)

        # Concatenate all features
        state_vector = np.concatenate([
            position_vec,
            target_vec,
            time_normalized,
            distance_normalized,
            departure_features
        ])
        
        return state_vector
    
    @property
    def state_size(self) -> int:
        return self.num_nodes * 2 + 1 + 1 + 5


# Global model state
_model: Optional[DQNetwork] = None
_state_encoder: Optional[StateEncoder] = None
_device: str = 'cpu'
_action_list = [Action.UP, Action.DOWN, Action.LEFT, Action.RIGHT, Action.WAIT]
_action_to_idx = {action: idx for idx, action in enumerate(_action_list)}
_idx_to_action = {idx: action for action, idx in _action_to_idx.items()}


def initialize_model(
    model_path: Optional[str] = None,
    map_filename: str = "map_export.json",
    device: str = 'cpu'
) -> bool:
    """
    Initialize the trained model for inference.
    
    Args:
        model_path: Path to the trained model checkpoint. If None, uses best_model.pt
        map_filename: Name of the map file to load grid structure
        device: Device to run inference on ('cpu' or 'cuda')
    
    Returns:
        True if initialization successful, False otherwise
    """
    global _model, _state_encoder, _device
    
    try:
        # Set device
        _device = device
        
        # Load map to get grid structure
        script_dir = Path(__file__).parent
        maps_dir = script_dir / ".." / "maps"
        map_path = maps_dir / map_filename
        
        if not map_path.exists():
            print(f"Warning: Map file not found at {map_path}, trying alternative locations...")
            # Try alternative location
            alt_map_path = script_dir / ".." / "godot_project" / "exported_maps" / map_filename
            if alt_map_path.exists():
                map_path = alt_map_path
            else:
                print(f"Error: Could not find map file")
                return False
        
        # Load map using loader
        from loader import load_map
        map_info = load_map(map_filename)
        
        # Build grid structure
        from environment import Grid
        grid = Grid(map_info)
        
        # Initialize state encoder
        _state_encoder = StateEncoder(grid.nodes)
        
        # Determine model path
        if model_path is None:
            # Try best model first, then latest checkpoint
            model_path = script_dir / "checkpoints_backup" / "best_model.pt"
            if not model_path.exists():
                model_path = script_dir / "checkpoints" / "checkpoint_ep10000.pt"
            if not model_path.exists():
                # Find latest checkpoint
                checkpoints_dir = script_dir / "checkpoints"
                if checkpoints_dir.exists():
                    checkpoints = sorted(checkpoints_dir.glob("checkpoint_ep*.pt"))
                    if checkpoints:
                        model_path = checkpoints[-1]
                    else:
                        print("Error: No model checkpoints found")
                        return False
        else:
            model_path = Path(model_path)
        
        if not model_path.exists():
            print(f"Error: Model file not found at {model_path}")
            return False
        
        # Initialize model
        state_size = _state_encoder.state_size
        action_size = len(_action_list)
        _model = DQNetwork(state_size, action_size).to(_device)
        
        # Load trained weights
        checkpoint = torch.load(model_path, map_location=_device)
        if 'policy_net_state_dict' in checkpoint:
            _model.load_state_dict(checkpoint['policy_net_state_dict'])
        else:
            _model.load_state_dict(checkpoint)
        
        _model.eval()  # Set to evaluation mode
        
        print(f"Model loaded successfully from {model_path}")
        print(f"State size: {state_size}, Action size: {action_size}")
        print(f"Number of nodes: {_state_encoder.num_nodes}")
        
        return True
        
    except Exception as e:
        print(f"Error initializing model: {e}")
        import traceback
        traceback.print_exc()
        return False


def ask_model(observation: dict[str, Any] | None = None) -> Action:
    """
    Get action prediction from the trained model.
    
    Args:
        observation: Dictionary containing:
            - position: Current node index
            - target: Target node index
            - time: Current simulation time
    
    Returns:
        Action enum value (UP, DOWN, LEFT, RIGHT, or WAIT)
    """
    global _model, _state_encoder, _device
    
    # Validate observation
    if observation is None or not validate_observation(observation):
        return Action.WAIT
    
    # Initialize model if not already done
    if _model is None or _state_encoder is None:
        print("Model not initialized, initializing now...")
        if not initialize_model():
            print("Failed to initialize model, returning WAIT action")
            return Action.WAIT
    
    try:
        # Encode state
        state = _state_encoder.encode(observation)
        
        # Get model prediction
        with torch.no_grad():
            state_tensor = torch.FloatTensor(state).unsqueeze(0).to(_device)
            q_values = _model(state_tensor).cpu().numpy()[0]
        
        # Select action with highest Q-value
        action_idx = int(np.argmax(q_values))
        action = _idx_to_action[action_idx]
        
        return action
        
    except Exception as e:
        print(f"Error in ask_model: {e}")
        import traceback
        traceback.print_exc()
        return Action.WAIT


def validate_observation(observation: Any) -> bool:
    """
    Validate that observation contains required fields.
    
    Args:
        observation: Observation to validate
    
    Returns:
        True if valid, False otherwise
    """
    if not isinstance(observation, dict):
        return False

    required_fields = ("position", "target", "time")
    return all(field in observation for field in required_fields)


# Auto-initialize on module import (optional, can be disabled)
def _auto_initialize():
    """Attempt to auto-initialize the model when module is imported."""
    try:
        initialize_model()
    except Exception as e:
        print(f"Auto-initialization failed (this is OK if called from service): {e}")


# Uncomment to enable auto-initialization
# _auto_initialize()

