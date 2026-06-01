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

action_index = 0

def ask_model(observation: dict[str, Any] | None = None) -> Action:
    global action_index
    action = action_array[action_index]
    action_index += 1
    action_index %= len(action_array)
    return action


def validate_observation(observation: Any) -> bool:
    if not isinstance(observation, dict):
        return False

    required_fields = ("position", "target", "time")
    return all(field in observation for field in required_fields)