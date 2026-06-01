extends Node2D

@onready var area_2d: Area2D = $Area2D

const BASE_SPEED = 50
const TRAM_SPEED_MULTIPLIER = 1.1

var COLOR
var path = []
var stops = []
var speed = BASE_SPEED
var stop_duration = 0
var line = null
var direction = -1

var path_position := 0
var next_position: Vector2
var moving = true
var go_time = -1
var stopped_at_node = null
var last_departure_tick = -1
var passengers = []

func _ready() -> void:
	z_index = 2
	area_2d.hide()
	
	if path.is_empty():
		queue_free()
		return
	
	position = path[0].position
	path_position = 1
	
	if path_position >= path.size():
		queue_free()
		return
	
	next_position = path[path_position].position

	# If the vehicle is spawned on a stop (start of the path), make it initially stopped
	# so waiting passengers at that stop can board immediately.
	if path.size() > 0 and path[0] in stops:
		stopped_at_node = path[0]
		go_time = (Globals.TICK + stop_duration) % 1440
		moving = false
		area_2d.show()
	else:
		last_departure_tick = Globals.TICK

func _process(delta: float) -> void:
	if moving:
		_move_vehicle(delta)
	else:
		_wait_at_stop()

func _move_vehicle(delta: float) -> void:
	var step = speed * delta * Globals.TICKSPEED
	position = position.move_toward(next_position, step)
	_update_passenger_positions()
	
	if position != next_position:
		return
	
	var arrived_node = path[path_position]
	var previous_node = path[path_position - 1]
	path_position += 1

	if arrived_node in stops:
		stopped_at_node = arrived_node
		if line != null:
			stopped_at_node.record_arrival(line.NUMBER, Globals.TICK, previous_node, last_departure_tick)
	
	if path_position >= path.size():
		_release_all_passengers()
		queue_free()
		return
	
	next_position = path[path_position].position

	if arrived_node in stops:
		go_time = (Globals.TICK + stop_duration) % 1440
		moving = false
		area_2d.show()

func _wait_at_stop() -> void:
	_update_passenger_positions()
	if Globals.TICK == go_time:
		if line != null and stopped_at_node != null:
			var next_node = null
			if path_position < path.size():
				next_node = path[path_position]
			last_departure_tick = Globals.TICK
			stopped_at_node.record_departure(line.NUMBER, Globals.TICK, next_node, last_departure_tick)
		moving = true
		stopped_at_node = null
		area_2d.hide()

func is_stopped_at(stop_node) -> bool:
	return not moving and stopped_at_node == stop_node

func board(passenger) -> bool:
	if passenger in passengers:
		return true
	passengers.append(passenger)
	passenger.current_vehicle = self
	return true

func unboard(passenger) -> void:
	if passenger in passengers:
		passengers.erase(passenger)
	passenger.current_vehicle = null
	passenger.show()
	passenger.global_position = global_position

func _update_passenger_positions() -> void:
	for passenger in passengers:
		passenger.global_position = global_position

func _release_all_passengers() -> void:
	for passenger in passengers.duplicate():
		unboard(passenger)
