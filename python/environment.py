from enum import Enum
import random
import numpy as np

from loader import load_map, load_rewards

DEFAULT_REWARDS_FILENAME = "environment_rewards.yaml"
MIN_TIME = 0
MAX_TIME = 1440

# action enum
class Action(Enum):
    UP = "UP"
    DOWN = "DOWN"
    LEFT = "LEFT"
    RIGHT = "RIGHT"
    WAIT = "WAIT"

class Grid :

    def __init__(self, map_info) :
        self.nodes = {}
        for road_info in map_info['roads'] :
            self.add_road(road_info)

    def distance(self, from_node, to_node) :
        # run quick bfs to find distance between nodes
        visited = set()
        queue = [(from_node, 0)]

        while queue :
            current_node, dist = queue.pop(0)
            if current_node == to_node :
                return dist
            if current_node in visited :
                continue
            visited.add(current_node)

            for neighbour in self.nodes[current_node].values() :
                next_node, move_cost = neighbour
                if next_node is not None and next_node not in visited :
                    queue.append((next_node, dist + 1))

        return float('inf')


    def add_road(self, road_info) :
        start_node = int(road_info['from'])
        end_node = int(road_info['to'])
        road_length = float(road_info['distance'])

        if start_node not in self.nodes :
            self.nodes[start_node] = {
                Action.UP: (None, float('inf')),
                Action.DOWN: (None, float('inf')),
                Action.LEFT: (None, float('inf')),
                Action.RIGHT: (None, float('inf')),
                Action.WAIT: (start_node, 0),
            }
        if end_node not in self.nodes :
            self.nodes[end_node] = {
                Action.UP: (None, float('inf')),
                Action.DOWN: (None, float('inf')),
                Action.LEFT: (None, float('inf')),
                Action.RIGHT: (None, float('inf')),
                Action.WAIT: (end_node, 0),
            }
        
        if end_node == start_node + 1 :
            self.nodes[start_node][Action.RIGHT] = (end_node, road_length)
            self.nodes[end_node][Action.LEFT] = (start_node, road_length)
        elif end_node == start_node - 1 :
            self.nodes[start_node][Action.LEFT] = (end_node, road_length)
            self.nodes[end_node][Action.RIGHT] = (start_node, road_length)
        elif end_node < start_node :
            self.nodes[start_node][Action.UP] = (end_node, road_length)
            self.nodes[end_node][Action.DOWN] = (start_node, road_length)
        elif end_node > start_node :
            self.nodes[start_node][Action.DOWN] = (end_node, road_length)
            self.nodes[end_node][Action.UP] = (start_node, road_length)

class Agent :
    
    def __init__(self, position, target, parent, time = None) :
        self._initial_position = position
        self.position = position
        self.target = target
        self.parent = parent
        self._start_time = time if time is not None else random.randint(MIN_TIME, MAX_TIME)
        self.time = self._start_time
        self.distance_traveled = 0

        self.path = [self.position]
        self.actions = []

    def normalize_action(self, action) :
        if action not in Action :
            action = Action.WAIT
        if self.parent.grid.nodes[self.position][action][0] is None :
            action = Action.WAIT
        return action

    def observe(self) :
        return {
            "position": self.position,
            "target": self.target,
            "time": self.time,
        }

    def act(self, move) :
        action, cost = move
        action = self.normalize_action(action)
        if action == Action.WAIT :
            cost = 1
        self.actions.append(action)
        next_position, move_cost = self.parent.grid.nodes[self.position][action]
        self.position = next_position
        self.path.append(self.position)
        self.distance_traveled += move_cost
        self.time += cost
        self.time %= MAX_TIME

    def summarize(self) :
        print("Summary:")
        print(f"    Initial position: {self._initial_position}")
        print(f"    Target position: {self.target}")
        print(f"    Time: {self.time - self._start_time} minutes")
        print(f"    Distance traveled: {self.distance_traveled}")
        print(f"    Actions taken:\n        {[action.value for action in self.actions]}")
        print(f"    Path taken:\n        {self.path}")

    def get_values(self) :
        return {
            "position": self.position,
            "initial_position": self._initial_position,
            "target": self.target,
            "time": self.time,
            "start_time": self._start_time,
            "distance_traveled": self.distance_traveled,
            "actions": self.actions,
            "path": self.path,
        }

class Environment :

    def __init__(self, map_filename, max_moves = MAX_TIME, seed = None) :
        if seed is not None :
            random.seed(seed)
            np.random.seed(seed)

        self.map_info = load_map(map_filename)
        self.rewards_info = load_rewards(DEFAULT_REWARDS_FILENAME)

        self.grid = Grid(self.map_info)

        self.agent = None
        self.finished = False
        self.interrupted = False

        self.actions = [Action.UP, Action.DOWN, Action.LEFT, Action.RIGHT, Action.WAIT]

        self.num_of_moves = 0
        self.max_moves = max_moves

        self.generate_agent()

    def reset(self) :
        self.generate_agent()
        self.finished = False
        self.interrupted = False
        self.num_of_moves = 0

    def generate_agent(self) :
        start_node = random.choice(list(self.grid.nodes.keys()))
        target_node = random.choice(list(self.grid.nodes.keys()))
        while target_node == start_node :
            target_node = random.choice(list(self.grid.nodes.keys()))

        self.agent = Agent(start_node, target_node, self, 2)
        self.finished = False

    def get_line_info(self, linenumber) :
        for line in self.map_info['lines'] :
            if int(line['number']) == int(linenumber) :
                return line
        return None
    
    def node_after_action(self, action) :
        next_node, distance = self.grid.nodes[self.agent.position][action]
        return next_node

    def get_action_cost(self, action) :
        if action == Action.WAIT :
            return 1
        
        departures = self.get_departures()
        break_out = False
        for line in departures :
            for departure in departures[line] :
                if departure['tick'] > self.agent.time :
                    break_out = True
                if departure['tick'] == self.agent.time :
                    # check if this line can take the agent in the direction of the action
                    next_node = self.node_after_action(action)

                    if next_node == departure['to_index'] :
                        arrivals = self.get_arrivals(next_node)[line]
                        for arrival in arrivals :
                            time_val = arrival['tick'] - self.agent.time
                            if (
                                (
                                    arrival['from_index'] == self.agent.position
                                ) and (
                                    arrival['start_tick'] == self.agent.time
                                ) and (
                                    time_val > 0
                                )
                            ) :
                                return time_val
                if break_out : break
            if break_out : break



        next_node, distance = self.grid.nodes[self.agent.position][action]
        if next_node is None :
            return 1
        
        walk_speed = self.map_info['settings']['passenger_walk_speed']
        time_cost = int(np.ceil(distance / walk_speed))

        return time_cost

    def update(self, action) :

        action = self.agent.normalize_action(action)

        reward = 0
        prev_agent_position = self.agent.position
        self.agent.act((action, self.get_action_cost(action)))
        

        prev_distance = self.grid.distance(prev_agent_position, self.agent.target)
        current_distance = self.grid.distance(self.agent.position, self.agent.target)
        multiplier = np.sign(prev_distance - current_distance)
        reward += multiplier * self.rewards_info['APPROACHING_TARGET_REWARD']

        reward += self.rewards_info['EXISTENCE_PUNISHMENT']

        if self.agent.position == self.agent.target :
            self.finished = True
            
            reward += self.rewards_info['REACHING_TARGET_REWARD']
            
            self.agent.summarize()

        self.num_of_moves += 1
        if self.num_of_moves >= self.max_moves :
            self.interrupted = True

            
        return reward

    def get_arrivals(self, node = None) :
        arrivals = {}
        if node is None :
            node = self.agent.position
        for line in self.map_info['nodes'][node]['schedule'] :
            arrivals[line] = self.map_info['nodes'][node]['schedule'][line]['arrivals']
        return arrivals

    def get_departures(self, node = None) :
        departures = {}
        if node is None :
            node = self.agent.position
        for line in self.map_info['nodes'][node]['schedule'] :
            departures[line] = self.map_info['nodes'][node]['schedule'][line]['departures']
        return departures

    def get_observation(self) :
        return self.agent.observe()
    
    def get_info(self) :
        return {
            "observation": self.get_observation(),
            "departures": self.get_departures(),
        }

if __name__ == "__main__" :

    env = Environment("map_export.json", seed=42)
    env.agent = Agent(0, 10, env, time=0)

    print(env.update(Action.DOWN))
