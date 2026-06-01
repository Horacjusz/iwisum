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

def ask_model(observation: dict[str, Any] | None = None) -> Action:
    if observation is None:
        observation = {}

    return Action.UP


def validate_observation(observation: Any) -> bool:
    if not isinstance(observation, dict):
        return False

    required_fields = ("position", "target", "time")
    return all(field in observation for field in required_fields)
