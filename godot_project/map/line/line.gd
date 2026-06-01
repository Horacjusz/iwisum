extends Node2D

const VEHICLE = preload("res://map/line/vehicle.tscn")
const VEHICLE_SCRIPT = preload("res://map/line/vehicle.gd")

const STOP_DURATION = 2

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
var default_speed = VEHICLE_SCRIPT.BASE_SPEED
var night_line = false

func tick(delta: float) -> void:
	var directions = schedule.get(Globals.TICK, [])
	if directions.size() == 0:
		return
	spawn_agent(directions)

func spawn_agent(directions: Array) -> void:
	for direction in directions:
		var direction_int = int(direction)
		var vehicle = VEHICLE.instantiate()
		vehicle.COLOR = COLOR
		vehicle.speed = default_speed
		vehicle.stop_duration = STOP_DURATION
		vehicle.line = self
		vehicle.direction = direction_int
		
		if direction_int == DIRECTIONS.FORWARD:
			vehicle.path = path.duplicate()
			vehicle.stops = stops.duplicate()
			vehicle.global_position = start.global_position
		elif direction_int == DIRECTIONS.BACKWARD:
			vehicle.path = path.duplicate()
			vehicle.path.reverse()
			vehicle.stops = stops.duplicate()
			vehicle.stops.reverse()
			vehicle.global_position = end.global_position
		else:
			continue
		
		add_child(vehicle)
		vehicles.append(vehicle)

func initialize_from_data(map_nodes: Array, line_data: Dictionary) -> void:
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
