extends Node2D

@onready var map: Node2D = $Map
@onready var timer: Timer = $Timer
@onready var hud: Control = $Camera2D/HUD

const DEFAULT_MAP_FILE = "res://exported_maps/map_export.json"

var execute_tick = true
var elapsed_time = 0
var simulation_started = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Globals.TICK = 0
	hud.export_map_requested.connect(_on_export_map_requested)
	execute_tick = false
	_load_default_map()

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


func _load_default_map() -> void:
	var init_info: Dictionary = map.initialize(DEFAULT_MAP_FILE)
	if not init_info.get("import_success", false):
		hud.show_status_message(str(init_info.get("message", "Map import failed")), true)
		simulation_started = false
		execute_tick = false
		return
	else:
		hud.show_status_message(str(init_info.get("message", "Map initialized")), false)
	simulation_started = true
	execute_tick = true
	pass # Replace with function body.


func _on_export_map_requested() -> void:
	map.export_map_to_json()
	hud.show_status_message("Map exported to res://exported_maps/map_export.json", false)
