extends Node2D

const WALK_SPEED = 5

enum STATES {
	GOING_TO_START_NODE,
	AT_NODE,
	WALKING_TO_NODE,
	RIDING,
	ARRIVED
}

var COLOR = Color.WHITE
var city_map = null
var spawn_position: Vector2
var target_position: Vector2
var start_node = null
var end_node = null

var state = STATES.GOING_TO_START_NODE
var current_node = null
var next_node = null
var next_position: Vector2
var current_vehicle = null
var last_decision_tick := -1

func initialize(map_ref, spawn: Vector2, target: Vector2, start, end) -> void:
	city_map = map_ref
	spawn_position = spawn
	target_position = target
	start_node = start
	end_node = end
	current_node = start_node
	global_position = spawn_position

	if start_node == null or end_node == null:
		state = STATES.ARRIVED
		return

	if global_position == start_node.global_position:
		state = STATES.AT_NODE
	else:
		next_node = start_node
		next_position = start_node.global_position
		state = STATES.GOING_TO_START_NODE

func _ready() -> void:
	z_index = 3

func tick() -> void:
	if state != STATES.AT_NODE:
		return
	if last_decision_tick == Globals.TICK:
		return

	last_decision_tick = Globals.TICK
	_make_next_step_decision()

func _process(delta: float) -> void:
	match state:
		STATES.GOING_TO_START_NODE:
			_walk_to_next_node(delta)
		STATES.WALKING_TO_NODE:
			_walk_to_next_node(delta)
		STATES.RIDING:
			_try_exit_vehicle()
		STATES.ARRIVED:
			queue_free()

	queue_redraw()

func _make_next_step_decision() -> void:
	if current_node == end_node:
		state = STATES.ARRIVED
		return

	var action = city_map.ask_model(self, current_node, end_node)
	var requested_node = city_map.get_next_node_for_action(current_node, action)
	if requested_node == null or requested_node == current_node:
		return

	next_node = requested_node
	var departing_vehicle = city_map.find_departing_vehicle(current_node, next_node)
	if departing_vehicle != null and departing_vehicle.board(self):
		current_vehicle = departing_vehicle
		z_index = 4
		state = STATES.RIDING
		return

	next_position = next_node.global_position
	state = STATES.WALKING_TO_NODE

func _walk_to_next_node(delta: float) -> void:
	var step = WALK_SPEED * delta * Globals.TICKSPEED
	global_position = global_position.move_toward(next_position, step)

	if global_position != next_position:
		return

	current_node = next_node
	state = STATES.AT_NODE

func _try_exit_vehicle() -> void:
	if current_vehicle == null or not is_instance_valid(current_vehicle):
		current_node = city_map.get_closest_node(global_position)
		next_node = current_node
		z_index = 3
		state = STATES.AT_NODE
		return

	if current_vehicle.is_stopped_at(next_node):
		current_vehicle.unboard(self)
		current_node = next_node
		z_index = 3
		state = STATES.AT_NODE
