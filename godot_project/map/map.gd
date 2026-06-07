extends Node2D

const NODE = preload("res://map/node/node.tscn")
const ROAD = preload("res://map/road/road.tscn")
const LINE = preload("res://map/line/line.tscn")
const PASSENGER = preload("res://agents/passenger/passenger.tscn")
const PASSENGER_SCRIPT = preload("res://agents/passenger/passenger.gd")
const VEHICLE_SCRIPT = preload("res://map/line/vehicle.gd")
const LINE_SCRIPT = preload("res://map/line/line.gd")

var nodes: Array[Node2D] = []
var roads := {}
var lines: Array[Node2D] = []

var prev_click = null
var next_passenger_id := 0

enum MODEL_ACTIONS {
	UP,
	DOWN,
	RIGHT,
	LEFT,
	WAIT
}

func initialize(filepath = null) -> Dictionary:
	var info := {
		"import_requested": filepath != null,
		"import_success": false,
		"message": "",
	}

	_clear_map()
	if filepath != null and _can_import_json(filepath):
		if import_map_from_json(str(filepath)):
			info["import_success"] = true
			info["message"] = "Map imported successfully"
			return info
		info["message"] = "Import failed"
	elif filepath != null:
		info["message"] = "Selected file is not a valid JSON map"
	else:
		info["message"] = "Select a JSON map file"

	return info


func _can_import_json(filepath: String) -> bool:
	if not filepath.to_lower().ends_with(".json"):
		return false
	return (
		FileAccess.file_exists(filepath)
		or FileAccess.file_exists("res://exported_maps/" + filepath)
		or FileAccess.file_exists("res://exported maps/" + filepath)
	)


func _clear_map() -> void:
	prev_click = null
	next_passenger_id = 0

	for child in get_children():
		if child.get_script() == PASSENGER_SCRIPT:
			child.queue_free()

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

func spawn_passenger(spawn_position = null, target_position = null) -> void:
	if nodes.is_empty():
		return
	if spawn_position == null or target_position == null:
		return
	
	var start_node = get_closest_node(spawn_position)
	var end_node = get_closest_node(target_position)
	if start_node == null or end_node == null:
		return
	if start_node == end_node:
		return
	
	var passenger = PASSENGER.instantiate()
	passenger.passenger_id = next_passenger_id
	next_passenger_id += 1
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

func ask_model(passenger) -> int:
	return AskModel.ask_model(passenger)

func find_departing_vehicle(from_node, to_node):
	if from_node == null or to_node == null:
		return null
	
	for vehicle in from_node.vehicles :
		if vehicle.go_time == Globals.TICK :
			if vehicle.get_next_node() == to_node :
				return vehicle

	return null

func get_next_stop_for_vehicle(vehicle):
	if not is_instance_valid(vehicle):
		return null

	for index in range(vehicle.path_position, vehicle.path.size()):
		var path_node = vehicle.path[index]
		if path_node in vehicle.stops:
			return path_node

	return null

func _vehicle_departs_to_node(vehicle, from_node, to_node) -> bool:
	if not is_instance_valid(vehicle):
		return false
	if not vehicle.is_stopped_at(from_node):
		return false
	if vehicle.go_time != Globals.TICK:
		return false
	if vehicle.path_position >= vehicle.path.size():
		return false
	if vehicle.path[vehicle.path_position] != to_node:
		return false
	return true

func _node_matches_action_direction(from_node, to_node, action: int) -> bool:
	var delta = to_node.global_position - from_node.global_position
	var epsilon := 0.001

	match action:
		MODEL_ACTIONS.UP:
			return delta.y < epsilon and abs(delta.x) <= epsilon
		MODEL_ACTIONS.DOWN:
			return delta.y > -epsilon and abs(delta.x) <= epsilon
		MODEL_ACTIONS.RIGHT:
			return delta.x > epsilon and abs(delta.y) <= epsilon
		MODEL_ACTIONS.LEFT:
			return delta.x < -epsilon and abs(delta.y) <= epsilon

	return false

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

func export_map_to_json(file_name: String = "map_export.json") -> void:
	var export_dir = "res://exported_maps"
	var dir_access := DirAccess.open("res://")
	if dir_access and not dir_access.dir_exists("exported_maps"):
		dir_access.make_dir("exported_maps")

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
		file_path = "res://exported_maps/" + file_name
	if not FileAccess.file_exists(file_path):
		file_path = "res://exported maps/" + file_name
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
	var data = _normalize_import_indices(json.data)

	_clear_map()

	# Create nodes
	for node_data in data.get("nodes", []):
		var new_node = NODE.instantiate()
		new_node.id = nodes.size()
		new_node.map = self
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
		add_child(line)
		line.initialize_from_data(nodes, line_data)
		lines.append(line)

	print("Map imported from: ", file_path)
	return true

func _normalize_import_indices(data) -> Dictionary:
	if not (data is Dictionary):
		return {}

	var index_map := {}
	var indexed_nodes := []
	var source_nodes: Array = data.get("nodes", [])

	for old_position in range(source_nodes.size()):
		var node_data = source_nodes[old_position]
		if not (node_data is Dictionary):
			continue
		indexed_nodes.append({
			"old_position": old_position,
			"old_index": int(node_data.get("index", old_position)),
			"data": node_data,
		})

	indexed_nodes.sort_custom(func(a, b):
		var a_node: Dictionary = a["data"]
		var b_node: Dictionary = b["data"]
		var ay := float(a_node.get("y", 0.0))
		var by := float(b_node.get("y", 0.0))
		if not is_equal_approx(ay, by):
			return ay < by
		var ax := float(a_node.get("x", 0.0))
		var bx := float(b_node.get("x", 0.0))
		if not is_equal_approx(ax, bx):
			return ax < bx
		return int(a["old_index"]) < int(b["old_index"])
	)

	var normalized_nodes := []
	for new_index in range(indexed_nodes.size()):
		var indexed_node: Dictionary = indexed_nodes[new_index]
		var old_position := int(indexed_node["old_position"])
		var old_index := int(indexed_node["old_index"])
		index_map[old_position] = new_index
		index_map[old_index] = new_index

	for new_index in range(indexed_nodes.size()):
		var indexed_node: Dictionary = indexed_nodes[new_index]
		var normalized_node: Dictionary = indexed_node["data"].duplicate(true)
		normalized_node["index"] = new_index
		normalized_node["schedule"] = _remap_node_schedule(normalized_node.get("schedule", {}), index_map)
		normalized_nodes.append(normalized_node)

	var normalized: Dictionary = data.duplicate(true)
	normalized["nodes"] = normalized_nodes
	normalized["roads"] = _remap_roads(data.get("roads", []), index_map)
	normalized["lines"] = _remap_lines(data.get("lines", []), index_map)
	return normalized

func _remap_roads(source_roads: Array, index_map: Dictionary) -> Array:
	var remapped_roads := []
	for road_data in source_roads:
		if not (road_data is Dictionary):
			continue
		var old_from := int(road_data.get("from", -1))
		var old_to := int(road_data.get("to", -1))
		if not index_map.has(old_from) or not index_map.has(old_to):
			continue
		var remapped_road: Dictionary = road_data.duplicate(true)
		remapped_road["from"] = int(index_map[old_from])
		remapped_road["to"] = int(index_map[old_to])
		remapped_roads.append(remapped_road)
	return remapped_roads

func _remap_lines(source_lines: Array, index_map: Dictionary) -> Array:
	var remapped_lines := []
	for line_data in source_lines:
		if not (line_data is Dictionary):
			continue
		var remapped_line: Dictionary = line_data.duplicate(true)
		remapped_line["path"] = _remap_index_list(line_data.get("path", []), index_map)
		remapped_line["stops"] = _remap_index_list(line_data.get("stops", []), index_map)
		remapped_lines.append(remapped_line)
	return remapped_lines

func _remap_index_list(source_indices: Array, index_map: Dictionary) -> Array:
	var remapped_indices := []
	for source_index in source_indices:
		var old_index := int(source_index)
		if index_map.has(old_index):
			remapped_indices.append(int(index_map[old_index]))
	return remapped_indices

func _remap_node_schedule(schedule_data, index_map: Dictionary) -> Dictionary:
	if not (schedule_data is Dictionary):
		return {}

	if schedule_data.has("lines") and schedule_data["lines"] is Dictionary:
		schedule_data = schedule_data["lines"]

	var remapped_schedule := {}
	for line_key in schedule_data.keys():
		var line_data = schedule_data.get(line_key, {})
		if line_data is Dictionary:
			remapped_schedule[str(line_key)] = {
				"arrivals": _remap_schedule_events(line_data.get("arrivals", []), "from_index", index_map),
				"departures": _remap_schedule_events(line_data.get("departures", []), "to_index", index_map),
			}
		else:
			remapped_schedule[str(line_key)] = {
				"arrivals": _remap_schedule_events(line_data, "from_index", index_map),
				"departures": [],
			}
	return remapped_schedule

func _remap_schedule_events(events, node_index_key: String, index_map: Dictionary) -> Array:
	var remapped_events := []
	if not (events is Array):
		return remapped_events

	for event in events:
		if event is Dictionary:
			var remapped_event: Dictionary = event.duplicate(true)
			if remapped_event.has(node_index_key):
				var old_index := int(remapped_event.get(node_index_key, -1))
				remapped_event[node_index_key] = int(index_map[old_index]) if index_map.has(old_index) else -1
			remapped_events.append(remapped_event)
		else:
			remapped_events.append(event)
	return remapped_events

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

func get_stop_duration() -> int:
	return LINE_SCRIPT.STOP_DURATION

func tick(delta) -> void:
	print("Current tick: ", "%4d " % Globals.TICK, delta)
	for line in lines:
		line.tick(delta)

	for child in get_children():
		if child.get_script() == PASSENGER_SCRIPT:
			child.tick()
	
	spawn_passenger(Vector2(645.0, 723.0), Vector2(646.0, 612.0))

func _process(delta: float) -> void:
	if nodes.is_empty():
		prev_click = null
		return

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
			if prev_click == null:
				prev_click = mouse_pos
			else:
				spawn_passenger(prev_click, mouse_pos)
				prev_click = null
	
