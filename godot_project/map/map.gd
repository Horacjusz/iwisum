extends Node2D

@onready var main: Node2D = $".."

# Edge class for transit connections between stops
class Edge:
	var start_node: Node2D
	var end_node: Node2D
	var distance: float
	var travel_time: float
	var cost: float
	var line_info: Dictionary  # {line_number: int, line_ref: Node2D, direction: int}
	
	func _init(start: Node2D, end: Node2D, dist: float, time: float, info: Dictionary) -> void:
		start_node = start
		end_node = end
		distance = dist
		travel_time = time
		cost = time  # Initially cost equals travel time
		line_info = info

const NODE = preload("res://map/node/node.tscn")
const ROAD = preload("res://map/road/road.tscn")
const AREA = preload("res://map/area/area.tscn")
const LINE = preload("res://map/line/line.tscn")
const PASSENGER = preload("res://agents/passenger/passenger.tscn")
const PASSENGER_SCRIPT = preload("res://agents/passenger/passenger.gd")
const VEHICLE_SCRIPT = preload("res://map/line/vehicle.gd")
const LINE_SCRIPT = preload("res://map/line/line.gd")

var nodes: Array[Node2D] = []
var roads := {}
var lines: Array[Node2D] = []
var rng := RandomNumberGenerator.new()

var prev_click = null

var spawn_accumulator = 0.0

enum MODEL_ACTIONS {
	UP,
	DOWN,
	RIGHT,
	LEFT,
	WAIT
}

func _ready() -> void:
	rng.randomize()


func initialize(filepath = null) -> Dictionary:
	var info := {
		"import_requested": filepath != null,
		"import_success": false,
		"generated_random": false,
		"message": "",
	}

	_clear_map()
	rng.randomize()
	if filepath != null and _can_import_json(filepath):
		if import_map_from_json(str(filepath)):
			info["import_success"] = true
			info["message"] = "Map imported successfully"
			return info
		print("Import failed, generating random map instead")
		info["message"] = "Import failed, generated random map"
	elif filepath != null:
		info["message"] = "Selected file is not a valid JSON map, generated random map"

	populate_with_nodes()
	connect_manhattan_neighbours()
	generate_lines()
	_generate_virtual_edges()
	info["generated_random"] = true
	if info["message"] == "":
		info["message"] = "Random map generated"
	return info


func _can_import_json(filepath: String) -> bool:
	if not filepath.to_lower().ends_with(".json"):
		return false
	return (
		FileAccess.file_exists(filepath)
		or FileAccess.file_exists("res://exported maps/" + filepath)
		or FileAccess.file_exists("res://exported_maps/" + filepath)
	)


func _clear_map() -> void:
	for n in nodes:
		n.queue_free()
	nodes.clear()

	for key in roads.keys():
		var r = roads[key]
		r.queue_free()
	roads.clear()

	for l in lines:
		l.queue_free()
	lines.clear()

func generate_lines() -> void:
	for i in range(main.NUM_LINES):
		var start = rng.randi_range(0, nodes.size() - 1)
		var through = rng.randi_range(0, nodes.size() - 1)
		var end = rng.randi_range(0, nodes.size() - 1)
		
		while through == start:
			through = rng.randi_range(0, nodes.size() - 1)
		while end == through or end == start:
			end = rng.randi_range(0, nodes.size() - 1)
		
		var line = LINE.instantiate()
		line.initialize(nodes[start], nodes[through], nodes[end])
		add_child(line)
		lines.append(line)

func populate_with_nodes() -> void:
	var size = get_viewport().get_visible_rect().size
	
	var margin_size = size - Vector2(
		Globals.MARGINS[0] + Globals.MARGINS[2],
		Globals.MARGINS[1] + Globals.MARGINS[3]
	)
	
	var jump = Vector2(
		margin_size.x / (main.NODES_X - 1),
		margin_size.y / (main.NODES_Y - 1)
	)
	

	
	for i in range(main.NODES_X) :
		for j in range(main.NODES_Y) :
			var current_node = NODE.instantiate() as Node2D
			add_child(current_node)
			current_node.position = Vector2(
				Globals.MARGINS[0] + i * jump.x,
				Globals.MARGINS[1] + j * jump.y
			)
			nodes.append(current_node)
			
		
	
	#for i in range(main.MAX_NODES):
		#var current_node = NODE.instantiate() as Node2D
		#add_child(current_node)
		#current_node.position = Vector2(
			#rng.randf_range(Globals.MARGINS[0], size.x - Globals.MARGINS[2]),
			#rng.randf_range(Globals.MARGINS[1], size.y - Globals.MARGINS[3])
		#)
		#nodes.append(current_node)

func spawn_passenger(spawn_position = null, target_position = null) -> void:
	if nodes.is_empty():
		return

	var size = get_viewport().get_visible_rect().size
	var randomize_positions = spawn_position == null or target_position == null
	
	if randomize_positions:
		spawn_position = Vector2(
			rng.randf_range(Globals.MARGINS[0], size.x - Globals.MARGINS[2]),
			rng.randf_range(Globals.MARGINS[1], size.y - Globals.MARGINS[3])
		)
		target_position = Vector2(
			rng.randf_range(Globals.MARGINS[0], size.x - Globals.MARGINS[2]),
			rng.randf_range(Globals.MARGINS[1], size.y - Globals.MARGINS[3])
		)
	
	var start_node = get_closest_node(spawn_position)
	var end_node = get_closest_node(target_position)
	if start_node == null or end_node == null:
		return
	
	if randomize_positions:
		while start_node == end_node:
			target_position = Vector2(
				rng.randf_range(Globals.MARGINS[0], size.x - Globals.MARGINS[2]),
				rng.randf_range(Globals.MARGINS[1], size.y - Globals.MARGINS[3])
			)
			end_node = get_closest_node(target_position)
	
	var passenger = PASSENGER.instantiate()
	add_child(passenger)
	passenger.initialize(self, spawn_position, target_position, start_node, end_node)

func get_closest_node(target_position: Vector2) -> Node2D:
	if nodes.is_empty():
		return null

	var closest = nodes[0]
	for node in nodes:
		if closest.global_position.distance_to(target_position) > node.global_position.distance_to(target_position):
			closest = node
	return closest

func ask_model(passenger, current_node, target_node) -> int:
	return AskModel.ask_model(passenger)

func get_next_node_for_action(current_node, action: int):
	if current_node == null:
		return null
	if action == MODEL_ACTIONS.WAIT:
		return current_node

	for road in current_node.roads:
		var neighbour = road.end
		if _node_matches_action_direction(current_node, neighbour, action):
			return neighbour

	return current_node

func find_departing_vehicle(from_node, to_node):
	if from_node == null or to_node == null:
		return null

	for line in lines:
		for vehicle in line.vehicles:
			if not is_instance_valid(vehicle):
				continue
			if not vehicle.has_free_seat():
				continue
			if not vehicle.is_stopped_at(from_node):
				continue
			if vehicle.go_time != Globals.TICK:
				continue
			if vehicle.path_position >= vehicle.path.size():
				continue
			if vehicle.path[vehicle.path_position] != to_node:
				continue
			if to_node not in vehicle.stops:
				continue
			return vehicle

	return null

func _node_matches_action_direction(from_node, to_node, action: int) -> bool:
	var delta = to_node.global_position - from_node.global_position
	var epsilon := 0.001

	match action:
		MODEL_ACTIONS.UP:
			return delta.y < -epsilon and abs(delta.x) <= epsilon
		MODEL_ACTIONS.DOWN:
			return delta.y > epsilon and abs(delta.x) <= epsilon
		MODEL_ACTIONS.RIGHT:
			return delta.x > epsilon and abs(delta.y) <= epsilon
		MODEL_ACTIONS.LEFT:
			return delta.x < -epsilon and abs(delta.y) <= epsilon

	return false

func get_road_path(start, end, blocked_nodes: Array = []) -> Array:
	if start == end:
		return []
	
	var queue = [start]
	var visited = {}
	var parent = {}
	visited[start] = true
	parent[start] = null
	
	for node in blocked_nodes:
		visited[node] = true
	
	while queue.size() > 0:
		var current = queue.pop_front()
		if current == end:
			return _reconstruct_path(parent, end)
		
		for road in current.roads:
			var neighbour = road.end
			if not visited.has(neighbour):
				visited[neighbour] = true
				parent[neighbour] = current
				queue.append(neighbour)
	
	return []

func _reconstruct_path(parent: Dictionary, end) -> Array:
	if not parent.has(end):
		return []
	
	var path = []
	var current = end
	while current != null:
		path.append(current)
		current = parent[current]
	path.reverse()
	return path

func find_direct_transit_plan(start_node, end_node) -> Dictionary:
	var best_plan := {}
	var best_score = INF
	
	for line in lines:
		for entry_stop in line.stops:
			for exit_stop in line.stops:
				if entry_stop == exit_stop:
					continue
				
				var direction = line.get_direction_between_stops(entry_stop, exit_stop)
				if direction == -1:
					continue
				
				var walk_to_entry = get_road_path(start_node, entry_stop)
				var walk_from_exit = get_road_path(exit_stop, end_node)
				if start_node != entry_stop and walk_to_entry.is_empty():
					continue
				if exit_stop != end_node and walk_from_exit.is_empty():
					continue
				
				var ride_path = line.get_path_between_stops(entry_stop, exit_stop, direction)
				# Estimate times (in simulation minutes): walking time, riding time and stop penalties
				var walk_to_entry_time = 0.0
				if walk_to_entry.size() > 0:
					walk_to_entry_time = get_path_distance(walk_to_entry) / get_passenger_walk_speed()

				var walk_from_exit_time = 0.0
				if walk_from_exit.size() > 0:
					walk_from_exit_time = get_path_distance(walk_from_exit) / get_passenger_walk_speed()

				var ride_distance = get_path_distance(ride_path)
				var ride_time = 0.0
				if ride_distance > 0:
					ride_time = ride_distance / line.default_speed

				# Count stops along ride_path to add stop duration penalties
				var stops_count = 0
				for node in ride_path:
					if node in line.stops:
						stops_count += 1
				var stop_penalty = stops_count * line.STOP_DURATION

				# Compute passenger arrival tick at entry stop (after walking)
				var walk_to_entry_minutes = int(ceil(walk_to_entry_time))
				var passenger_arrival_tick = (Globals.TICK + walk_to_entry_minutes) % 1440

				# Compute wait time until next vehicle arrives at entry stop after passenger arrival
				var wait_time = line.get_next_arrival_wait(entry_stop, direction, passenger_arrival_tick)
				if wait_time == INF:
					continue

				var score = walk_to_entry_time + wait_time + ride_time + stop_penalty + walk_from_exit_time
				if score < best_score:
					best_score = score
					best_plan = {
						"line": line,
						"direction": direction,
						"entry_stop": entry_stop,
						"exit_stop": exit_stop,
						"walk_to_entry": walk_to_entry,
						"walk_from_exit": walk_from_exit,
						"ride_path": ride_path,
					}
	
	return best_plan

func get_path_distance(path: Array) -> float:
	var distance := 0.0
	for i in range(1, path.size()):
		distance += path[i - 1].global_position.distance_to(path[i].global_position)
	return distance

func connect_manhattan_neighbours() -> void:
	if main.NODES_X <= 0 or main.NODES_Y <= 0:
		return

	for i in range(main.NODES_X):
		for j in range(main.NODES_Y):
			var current_index = i * main.NODES_Y + j
			var current_node = nodes[current_index]

			# Connect only right and down neighbours.
			# add_connection() creates both directions, so this avoids duplicates.
			if i + 1 < main.NODES_X:
				var right_index = (i + 1) * main.NODES_Y + j
				add_connection(current_node, nodes[right_index])

			if j + 1 < main.NODES_Y:
				var down_index = i * main.NODES_Y + (j + 1)
				add_connection(current_node, nodes[down_index])

func add_connection(start, end) -> void:
	var road = ROAD.instantiate() as Node2D
	road.start = start
	road.end = end
	add_child(road)
	roads[[start, end]] = road
	
	road = ROAD.instantiate() as Node2D
	road.start = end
	road.end = start
	add_child(road)
	roads[[end, start]] = road

func _generate_virtual_edges() -> void:
	# For each line, create edges between consecutive stops in both directions
	for line in lines:
		var line_number = line.NUMBER
		var line_ref = line
		
		# Forward direction
		var stops_forward = line.stops
		for i in range(stops_forward.size() - 1):
			var stop_a = stops_forward[i]
			var stop_b = stops_forward[i + 1]
			_add_virtual_edge(stop_a, stop_b, line_number, line_ref, line.DIRECTIONS.FORWARD)
		
		# Backward direction
		var stops_backward = stops_forward.duplicate()
		stops_backward.reverse()
		for i in range(stops_backward.size() - 1):
			var stop_a = stops_backward[i]
			var stop_b = stops_backward[i + 1]
			_add_virtual_edge(stop_a, stop_b, line_number, line_ref, line.DIRECTIONS.BACKWARD)


func export_map_to_json(file_name: String = "map_export.json") -> void:
	var export_dir = "res://exported maps"
	var dir_access := DirAccess.open("res://")
	if dir_access and not dir_access.dir_exists("exported maps"):
		dir_access.make_dir("exported maps")

	# Build node list
	var nodes_export := []
	for i in range(nodes.size()):
		var n = nodes[i]
		nodes_export.append({"index": i, "x": n.position.x, "y": n.position.y, "schedule": _serialize_node_schedule(n.schedule)})

	# Build roads (undirected unique edges)
	var roads_export := []
	for i in range(nodes.size()):
		var n = nodes[i]
		for road in n.roads:
			if road.start != n:
				continue
			var j = nodes.find(road.end)
			if j == -1:
				continue
			# to avoid duplicates, only export where i < j
			if i < j:
				roads_export.append({"from": i, "to": j, "distance": road.start.global_position.distance_to(road.end.global_position)})

	# Build line list (enough data to recreate lines 1:1)
	var lines_export := []
	for line in lines:
		var path_indices := []
		for node_ref in line.path:
			path_indices.append(nodes.find(node_ref))

		var stop_indices := []
		for stop_ref in line.stops:
			stop_indices.append(nodes.find(stop_ref))

		var schedule_export := {}
		for key in line.schedule.keys():
			schedule_export[str(key)] = line.schedule[key]

		lines_export.append({
			"number": line.NUMBER,
			"color": line.COLOR.to_html(false),
			"tram_line": line.TRAM_LINE,
			"night_line": line.night_line,
			"default_speed": line.default_speed,
			"path": path_indices,
			"stops": stop_indices,
			"schedule": schedule_export,
		})

	var data := {
		"nodes": nodes_export,
		"roads": roads_export,
		"lines": lines_export,
		"settings": {
			"passenger_walk_speed": get_passenger_walk_speed(),
			"vehicle_base_speed": get_vehicle_base_speed(),
			"tram_speed_multiplier": get_tram_speed_multiplier(),
			"vehicle_capacity": get_vehicle_capacity(),
			"stop_duration": get_stop_duration(),
		},
	}

	var file_path = export_dir + "/" + file_name
	var f = FileAccess.open(file_path, FileAccess.WRITE)
	if not f:
		print("Failed to open file for writing: ", file_path)
		return
	var json_text = JSON.stringify(data)
	f.store_string(json_text)
	f.close()
	print("Map exported to: ", file_path)


func import_map_from_json(file_name: String) -> bool:
	var file_path = file_name
	if not FileAccess.file_exists(file_path):
		file_path = "res://exported maps/" + file_name
	if not FileAccess.file_exists(file_path):
		file_path = "res://exported_maps/" + file_name
	var f = FileAccess.open(file_path, FileAccess.READ)
	if not f:
		print("Failed to open file for reading: ", file_path)
		return false
	var content = f.get_as_text()
	f.close()
	var json := JSON.new()
	var parse_error = json.parse(content)
	if parse_error != OK:
		print("Failed to parse JSON: ", json.get_error_message(), " at line ", json.get_error_line())
		return false
	var data = json.data

	_clear_map()

	# Create nodes
	for node_data in data.get("nodes", []):
		var new_node = NODE.instantiate()
		add_child(new_node)
		new_node.position = Vector2(node_data.get("x", 0), node_data.get("y", 0))
		nodes.append(new_node)

	# Create roads
	for r in data.get("roads", []):
		var a = int(r.get("from"))
		var b = int(r.get("to"))
		if a >=0 and a < nodes.size() and b >=0 and b < nodes.size():
			add_connection(nodes[a], nodes[b])

	# Set schedules on nodes
	for i in range(len(data.get("nodes", []))):
		var target = nodes[i]
		target.set_schedule_data(data.get("nodes")[i].get("schedule", {}), nodes)

	# Recreate lines exactly from saved line data
	for line_data in data.get("lines", []):
		var line = LINE.instantiate()
		line.is_imported = true
		add_child(line)
		line.initialize_from_data(nodes, line_data)
		lines.append(line)

	# Rebuild virtual edges from recreated lines (line_ref stays valid)
	for n in nodes:
		n.virtual_edges.clear()
	_generate_virtual_edges()

	print("Map imported from: ", file_path)
	return true

func _add_virtual_edge(start: Node2D, end: Node2D, line_number: int, line_ref: Node2D, direction: int) -> void:
	var distance = start.global_position.distance_to(end.global_position)
	var vehicle_speed = line_ref.default_speed
	
	# Travel time = distance / speed (no stop duration here, that's per-stop)
	var travel_time = distance / vehicle_speed
	
	var line_info = {
		"line_number": line_number,
		"line_ref": line_ref,
		"direction": direction
	}
	
	var edge = Edge.new(start, end, distance, travel_time, line_info)
	start.virtual_edges.append(edge)

func get_passenger_walk_speed() -> float:
	return PASSENGER_SCRIPT.WALK_SPEED

func _serialize_node_schedule(schedule_data: Dictionary) -> Dictionary:
	var serialized := {}
	for line_key in schedule_data.keys():
		var line_data = schedule_data[line_key]
		if not (line_data is Dictionary):
			continue
		serialized[str(line_key)] = {
			"arrivals": _serialize_schedule_events(line_data.get("arrivals", []), "from_node"),
			"departures": _serialize_schedule_events(line_data.get("departures", []), "to_node"),
		}
	return serialized

func _serialize_schedule_events(events: Array, node_ref_key: String) -> Array:
	var serialized_events := []
	for event in events:
		if not (event is Dictionary):
			continue
		var serialized_event := {"tick": int(event.get("tick", 0))}
		if event.has("start_tick"):
			serialized_event["start_tick"] = int(event.get("start_tick"))
		var node_ref = event.get(node_ref_key, null)
		serialized_event[node_ref_key.replace("_node", "_index")] = nodes.find(node_ref) if node_ref != null else -1
		serialized_events.append(serialized_event)
	return serialized_events

func get_vehicle_base_speed() -> float:
	return VEHICLE_SCRIPT.BASE_SPEED

func get_tram_speed_multiplier() -> float:
	return VEHICLE_SCRIPT.TRAM_SPEED_MULTIPLIER

func get_vehicle_capacity() -> int:
	return VEHICLE_SCRIPT.DEFAULT_CAPACITY

func get_stop_duration() -> int:
	return LINE_SCRIPT.STOP_DURATION

func get_number_of_passenger_spawns() :
	var limit = exp(-Globals.PASSENGER_SPAWN_RATE)
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	var k = 0
	var p = 1
	while p > limit :
		k += 1
		p *= rng.randf()
	
	return k - 1

func tick(delta) -> void:
	print("Current tick: ", "%4d " % Globals.TICK, delta)
	for line in lines:
		line.tick(delta)

	for child in get_children():
		if child.get_script() == PASSENGER_SCRIPT:
			child.tick()

	#for i in range(get_number_of_passenger_spawns()) :
		#spawn_passenger()

func _process(delta: float) -> void:
	var mouse_pos = get_viewport().get_mouse_position()
	
	var viewport_size = get_viewport().get_visible_rect().size
	
	var inside_margins = (
		mouse_pos.x >= Globals.MARGINS[0]
		and mouse_pos.y >= Globals.MARGINS[1]
		and mouse_pos.x <= viewport_size.x - Globals.MARGINS[2]
		and mouse_pos.y <= viewport_size.y - Globals.MARGINS[3]
	)
	
	if Input.is_action_just_pressed("click"):
		if inside_margins:
			print("Clicked: ", mouse_pos)
			if prev_click == null:
				prev_click = mouse_pos
			else:
				print("Spawning passenger")
				spawn_passenger(prev_click, mouse_pos)
				prev_click = null
