import argparse
from pathlib import Path
import sys
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from flask import Flask, jsonify, request

from environment import Action
from ask_model import ask_model, validate_observation


DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8000

# Protocol shared with Godot's MODEL_ACTIONS enum:
# UP = 0, DOWN = 1, RIGHT = 2, LEFT = 3, WAIT = 4.
ACTION_CODES = {
    Action.UP: 0,
    Action.DOWN: 1,
    Action.RIGHT: 2,
    Action.LEFT: 3,
    Action.WAIT: 4,
}


def init() -> None:
    pass


def action_payload(action: Action) -> dict[str, Any]:
    return {
        "action": ACTION_CODES[action],
        "action_name": action.value,
    }


def create_app() -> Flask:
    app = Flask(__name__)
    init()

    @app.get("/health")
    def health():
        return jsonify({"status": "ok"})

    @app.post("/ask_model")
    def ask_model_endpoint():
        observation = request.get_json(silent=True) or {}
        if not validate_observation(observation):
            return jsonify({"error": "Invalid observation"}), 400
        return jsonify(action_payload(ask_model(observation)))

    @app.post("/ask_model_batch")
    def ask_model_batch_endpoint():
        payload = request.get_json(silent=True) or {}
        passengers = payload.get("passengers", [])
        if not isinstance(passengers, list):
            return jsonify({"error": "Field 'passengers' must be a list"}), 400

        actions = []
        for passenger in passengers:
            if not validate_observation(passenger):
                continue

            action = ask_model(passenger)
            response = action_payload(action)
            if "id" in passenger:
                response["id"] = passenger["id"]
            actions.append(response)

        return jsonify({"actions": actions})

    return app


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="IWISUM model decision service")
    parser.add_argument("--host", default=DEFAULT_HOST)
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--debug", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    app = create_app()
    app.run(host=args.host, port=args.port, debug=args.debug)


if __name__ == "__main__":
    main()
