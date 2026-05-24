extends Node2D

const VEHICLE = preload("res://map/line/vehicle.tscn")
const VEHICLE_SCRIPT = preload("res://map/line/vehicle.gd")

const STOP_PROBABILITY = 1
const STOP_DURATION = 2
const NIGHT_LINE_PROBABILITY = 0.2
# x / y means that on average x buses leave every y minutes
const LEAVE_FREQUENCY = 1.0 / 30
const TRAM_PROBABILITY = 0.2
const TRAM_CAPACITY_MULTIPLIER = 3

enum DIRECTIONS {
	FORWARD,
	BACKWARD
}

var start
var end
var COLOR = Color.BLUE
var TRAM_LINE = false
var NUMBER = 0

var path = []
var stops = []
var vehicles = []
var schedule = {}
var rng := RandomNumberGenerator.new()
var default_speed = VEHICLE_SCRIPT.BASE_SPEED
var night_line = false
var is_imported = false

func _ready() -> void:
	rng.randomize()

func tick(delta: float) -> void:
	var directions = schedule.get(Globals.TICK, [])
	if directions.size() == 0:
		return
	spawn_agent(directions)

func spawn_agent(directions: Array) -> void:
	var vehicle_capacity = VEHICLE_SCRIPT.DEFAULT_CAPACITY
	if TRAM_LINE:
		vehicle_capacity *= TRAM_CAPACITY_MULTIPLIER
	
	for direction in directions:
		var vehicle = VEHICLE.instantiate()
		vehicle.COLOR = COLOR
		vehicle.speed = default_speed
		vehicle.capacity = vehicle_capacity
		vehicle.stop_duration = STOP_DURATION
		vehicle.line = self
		vehicle.direction = direction
		
		if direction == DIRECTIONS.FORWARD:
			vehicle.path = path.duplicate()
			vehicle.stops = stops.duplicate()
			vehicle.global_position = start.global_position
		elif direction == DIRECTIONS.BACKWARD:
			vehicle.path = path.duplicate()
			vehicle.path.reverse()
			vehicle.stops = stops.duplicate()
			vehicle.stops.reverse()
			vehicle.global_position = end.global_position
		else:
			continue
		
		add_child(vehicle)
		vehicles.append(vehicle)

func create_schedule(frequency = LEAVE_FREQUENCY) -> void:
	var start_hour = 0
	var end_hour = 1440
	
	if rng.randf() < NIGHT_LINE_PROBABILITY:
		night_line = true
		end_hour = 480
		TRAM_LINE = false
	else:
		start_hour = 420
	
	schedule[start_hour] = [DIRECTIONS.FORWARD, DIRECTIONS.BACKWARD]
	
	for i in range(start_hour + 1, end_hour):
		if rng.randf() >= frequency:
			continue
		
		var second_time = max(min(i + rng.randi_range(-5, 5), end_hour - 1), start_hour + 1)
		var forward_table = schedule.get(i, [])
		if DIRECTIONS.FORWARD not in forward_table:
			forward_table.append(DIRECTIONS.FORWARD)
			schedule[i] = forward_table
		
		var backward_table = schedule.get(second_time, [])
		if DIRECTIONS.BACKWARD not in backward_table:
			backward_table.append(DIRECTIONS.BACKWARD)
			schedule[second_time] = backward_table

func bfs(start_node, end_node, no_go_zone = []) -> Dictionary:
	var queue = [start_node]
	var visited = {}
	var parent = {}
	visited[start_node] = true
	parent[start_node] = null
	
	for node in no_go_zone:
		visited[node] = true
	
	while queue.size() > 0:
		var current = queue.pop_front()
		if current == end_node:
			break
		
		for road in current.roads:
			var neighbour = road.end
			if not visited.has(neighbour):
				visited[neighbour] = true
				parent[neighbour] = current
				queue.append(neighbour)
	
	return parent

func initialize(start_node, through_node, end_node) -> void:
	NUMBER = Globals.get_line_number()
	COLOR = Globals.get_line_color(NUMBER)
	if rng.randf() < TRAM_PROBABILITY:
		TRAM_LINE = true
	_refresh_default_speed()
	create_schedule()
	start = start_node
	end = end_node
	path = _create_line_path(start_node, through_node, end_node)
	_create_stops(start_node, through_node, end_node)
	_register_line_on_roads()


func initialize_from_data(map_nodes: Array, line_data: Dictionary) -> void:
	is_imported = true
	NUMBER = int(line_data.get("number", 0))
	COLOR = Color(line_data.get("color", "#000000"))
	TRAM_LINE = bool(line_data.get("tram_line", false))
	night_line = bool(line_data.get("night_line", false))
	if line_data.has("default_speed"):
		default_speed = float(line_data.get("default_speed", VEHICLE_SCRIPT.BASE_SPEED))
	else:
		_refresh_default_speed()
	schedule = {}

	var schedule_data = line_data.get("schedule", {})
	for key in schedule_data.keys():
		schedule[int(key)] = schedule_data[key]

	path.clear()
	for index in line_data.get("path", []):
		var idx = int(index)
		if idx >= 0 and idx < map_nodes.size():
			path.append(map_nodes[idx])

	stops.clear()
	for index in line_data.get("stops", []):
		var idx = int(index)
		if idx >= 0 and idx < map_nodes.size():
			var stop_node = map_nodes[idx]
			if stop_node not in stops:
				stops.append(stop_node)
			if self not in stop_node.stops:
				stop_node.stops.append(self)

	if path.size() > 0:
		start = path[0]
		end = path[path.size() - 1]

	_register_line_on_roads()

func _refresh_default_speed() -> void:
	default_speed = VEHICLE_SCRIPT.BASE_SPEED
	if TRAM_LINE:
		default_speed *= VEHICLE_SCRIPT.TRAM_SPEED_MULTIPLIER

func _create_line_path(start_node, through_node, end_node) -> Array:
	var result = []
	var parent = bfs(start_node, through_node)
	var first_part = _reconstruct_path(parent, through_node)
	
	parent = bfs(through_node, end_node, first_part.slice(0, max(first_part.size() - 1, 0)))
	var second_part = _reconstruct_path(parent, end_node)
	
	if second_part.size() > 0:
		second_part.pop_front()
	
	result.append_array(first_part)
	result.append_array(second_part)
	return result

func _reconstruct_path(parent: Dictionary, end_node) -> Array:
	if not parent.has(end_node):
		return []
	
	var result = []
	var current = end_node
	while current != null:
		result.append(current)
		current = parent[current]
	result.reverse()
	return result

func _create_stops(start_node, through_node, end_node) -> void:
	stops.clear()
	var stop_probability = STOP_PROBABILITY
	if night_line :
		stop_probability /= 5
	for current in path:
		if current == start_node or current == through_node or current == end_node or rng.randf() < STOP_PROBABILITY:
			if current not in stops:
				stops.append(current)
				current.stops.append(self)

func _register_line_on_roads() -> void:
	for i in range(1, path.size()):
		var previous = path[i - 1]
		var current = path[i]
		for road in previous.roads:
			if road.end == current and self not in road.lines:
				road.lines.append(self)
				road.queue_redraw()
		for road in current.roads:
			if road.end == previous and self not in road.lines:
				road.lines.append(self)
				road.queue_redraw()

func get_direction_between_stops(entry_stop, exit_stop) -> int:
	if entry_stop not in stops or exit_stop not in stops:
		return -1
	
	var entry_index = path.find(entry_stop)
	var exit_index = path.find(exit_stop)
	if entry_index == -1 or exit_index == -1:
		return -1
	if entry_index < exit_index:
		return DIRECTIONS.FORWARD
	if entry_index > exit_index:
		return DIRECTIONS.BACKWARD
	return -1

func get_path_between_stops(entry_stop, exit_stop, direction: int) -> Array:
	var entry_index = path.find(entry_stop)
	var exit_index = path.find(exit_stop)
	if entry_index == -1 or exit_index == -1:
		return []
	
	if direction == DIRECTIONS.FORWARD and entry_index < exit_index:
		return path.slice(entry_index, exit_index + 1)
	if direction == DIRECTIONS.BACKWARD and entry_index > exit_index:
		var result = path.slice(exit_index, entry_index + 1)
		result.reverse()
		return result
	
	return []

func vehicle_can_take_passenger(vehicle, entry_stop, exit_stop) -> bool:
	if vehicle.line != self:
		return false
	if vehicle.direction != get_direction_between_stops(entry_stop, exit_stop):
		return false
	if not vehicle.is_stopped_at(entry_stop):
		return false
	if not vehicle.has_free_seat():
		return false
	
	var vehicle_index = vehicle.path_position - 1
	var exit_index_in_vehicle_path = vehicle.path.find(exit_stop)
	return exit_index_in_vehicle_path > vehicle_index

func _get_sorted_departure_times(direction: int) -> Array:
	var times := []
	for t in schedule.keys():
		var dirs = schedule[t]
		if direction in dirs:
			times.append(t)
	times.sort()
	return times

func _travel_minutes_from_spawn_to_stop(direction: int, stop_node) -> float:
	var route := []
	if direction == DIRECTIONS.FORWARD:
		route = path
	else:
		route = path.duplicate()
		route.reverse()

	var stop_index = route.find(stop_node)
	if stop_index == -1:
		return INF

	var distance = 0.0
	for i in range(1, stop_index + 1):
		distance += route[i - 1].global_position.distance_to(route[i].global_position)

	var travel_time = distance / default_speed

	# count stops encountered up to and including this stop
	var stops_count = 0
	for i in range(0, stop_index + 1):
		if route[i] in stops:
			stops_count += 1

	var stop_time = stops_count * STOP_DURATION
	return travel_time + stop_time

func get_next_arrival_wait(entry_stop, direction: int, earliest_tick: int) -> float:
	# earliest_tick is the simulation tick (minute) when the passenger will be at the entry stop
	var depart_times = _get_sorted_departure_times(direction)
	if depart_times.size() == 0:
		return INF

	var travel_minutes = int(ceil(_travel_minutes_from_spawn_to_stop(direction, entry_stop)))

	var min_wait = INF
	for depart in depart_times:
		var arrival = (depart + travel_minutes) % 1440
		var wait = (arrival - earliest_tick + 1440) % 1440
		if wait < min_wait:
			min_wait = wait

	return min_wait
