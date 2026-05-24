import random

from environment import Environment




def train_epoch(env) :

    env.reset()

    print(env.actions)

    while not env.finished and not env.interrupted :
        # env.finished marks succesful end of episode (reaching target)
        # env.interrupted marks end of episode caused by reaching max moves limit
        # (agent was walking for more than 24h in simulation),
        # modifiable while creating environment with max_moves parameter

        info = env.get_info()
        # info contains "observation" and "departures" for current node that agent is at
        # both are dictionaries, you can print them to see their structure and contents

        action = random.choice(env.actions)
        # you can also import Action enum from Environment via
        # from environment import Action
        # and then use Action.UP, Action.DOWN, Action.LEFT, Action.RIGHT and Action.WAIT

        reward = env.update(action)
        # reward is a float value that the environment returns after processing the action
        # when agent reaches its target, update will print agent summary # easily changable
    
    agent_values = env.agent.get_values()
    # agents values is a dictionary containint all important agent data
    # with it you can even backtrack the path and increase rewards


if __name__ == "__main__" :

    env = Environment("map_export.json", seed=42)

    train_epoch(env)