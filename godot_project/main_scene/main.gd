extends Node2D

@onready var map: Node2D = $Map
@onready var timer: Timer = $Timer
@onready var hud: Control = $Camera2D/HUD

# Make sure NODES_X and NODES_Y are at least 2 each
const NODES_X = 10
const NODES_Y = 10
var MAX_NODES = NODES_X * NODES_Y
const NUM_LINES = 30

var execute_tick = true
var elapsed_time = 0
var simulation_started = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Globals.TICK = 0
	hud.simulation_mode_selected.connect(_on_simulation_mode_selected)
	hud.export_map_requested.connect(_on_export_map_requested)
	execute_tick = false
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if not simulation_started:
		return
	elapsed_time += delta
	if not execute_tick : return
	map.tick(elapsed_time)
	execute_tick = false
	timer.start(1.0 / Globals.TICKSPEED)
	elapsed_time = 0
	Globals.TICK += 1
	pass

#func _notification(what: int) -> void:
	#if what == NOTIFICATION_WM_CLOSE_REQUEST:
		## Your cleanup / save / final action here
		#print("Window close requested")
		#map.export_map_to_json()
		#
		#get_tree().quit()

func _on_timer_timeout() -> void:
	if simulation_started:
		execute_tick = true
	pass # Replace with function body.


func _on_simulation_mode_selected(file_path) -> void:
	var init_info: Dictionary = map.initialize(file_path)
	if init_info.get("import_requested", false) and not init_info.get("import_success", false):
		hud.show_status_message(str(init_info.get("message", "Import failed, generated random map")), true)
	else:
		hud.show_status_message(str(init_info.get("message", "Map initialized")), false)
	simulation_started = true
	execute_tick = true
	pass # Replace with function body.


func _on_export_map_requested() -> void:
	map.export_map_to_json()
	hud.show_status_message("Map exported to res://exported maps/map_export.json", false)
