from __future__ import annotations
from enum import Enum
from typing import Any

try :
    from environment import Action
except ModuleNotFoundError:

    class Action(Enum):
        UP = "UP"
        DOWN = "DOWN"
        LEFT = "LEFT"
        RIGHT = "RIGHT"
        WAIT = "WAIT"

action_array = [
    Action.UP,
    Action.WAIT,
    Action.LEFT,
    Action.WAIT,
    Action.DOWN,
    Action.WAIT,
    Action.RIGHT,
    Action.WAIT,
    Action.WAIT,
    Action.WAIT,
]

action_indices_by_passenger: dict[Any, int] = {}

def ask_model(observation: dict[str, Any] | None = None) -> Action:
    if observation is None:
        observation = {}

    passenger_id = observation.get("id", "__anonymous__")
    action_index = action_indices_by_passenger.get(passenger_id, 0)
    action = action_array[action_index]
    action_indices_by_passenger[passenger_id] = (action_index + 1) % len(action_array)
    return action


def validate_observation(observation: Any) -> bool:
    if not isinstance(observation, dict):
        return False

    required_fields = ("position", "target", "time")
    return all(field in observation for field in required_fields)
