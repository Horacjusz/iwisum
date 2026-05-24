from pathlib import Path
import json
import yaml

SCRIPT_DIR = Path(__file__).parent
MAPS_DIR = SCRIPT_DIR / ".." / "maps"
MAPS_DIR = MAPS_DIR.resolve()

def load_map(filename) :
    map_path = MAPS_DIR / filename
    if not map_path.is_file() :
        raise FileNotFoundError(f"Map file not found: {map_path}")

    with open(map_path, "r") as f :
        map_data = json.load(f)

    return map_data

def load_rewards(filename) :
    rewards_path = SCRIPT_DIR / filename
    if not rewards_path.is_file() :
        raise FileNotFoundError(f"Rewards file not found: {rewards_path}")
    
    # rewards path should contain YAML file. load it
    with open(rewards_path, "r") as f :
        rewards_data = yaml.safe_load(f)
    return rewards_data