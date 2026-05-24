extends Control

signal simulation_mode_selected(file_path)
signal export_map_requested()

@onready var color_rect: ColorRect = $MenuBackground
@onready var tick_speed: HSlider = $MenuBackground/Menu/TickSpeedContainer/Slider
@onready var tick_speed_value_label: Label = $MenuBackground/Menu/TickSpeedContainer/ValueLabel
@onready var passenger_spawn_rate: HSlider = $MenuBackground/Menu/PassengerSpawnRateContainer/Slider
@onready var passenger_spawn_rate_value_label: Label = $MenuBackground/Menu/PassengerSpawnRateContainer/ValueLabel
@onready var status_label: Label = $MenuBackground/Menu/StatusLabel
@onready var start_panel: PanelContainer = $StartPanel
@onready var file_dialog: FileDialog = $ImportFileDialog


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	color_rect.position.x = 1920 - Globals.MARGINS[2] + Globals.MARGINS[0]
	color_rect.size.x = Globals.MARGINS[2] - Globals.MARGINS[0]
	start_panel.visible = true
	_setup_import_dialog_dir()
	_on_tick_speed_value_changed(tick_speed.value)
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	tick_speed_value_label.text = str(Globals.TICKSPEED)
	passenger_spawn_rate_value_label.text = str(Globals.PASSENGER_SPAWN_RATE)
	pass


func _on_tick_speed_value_changed(value: float) -> void:
	Globals.TICKSPEED = ((Globals.MAX_TICKSPEED - Globals.MIN_TICKSPEED) / tick_speed.max_value) * value + Globals.MIN_TICKSPEED
	pass # Replace with function body.

func _on_passenger_spawn_rate_value_changed(value: float) -> void:
	Globals.PASSENGER_SPAWN_RATE = ((Globals.MAX_PASSENGER_SPAWNRATE - Globals.MIN_PASSENGER_SPAWNRATE) / passenger_spawn_rate.max_value) * value + Globals.MIN_PASSENGER_SPAWNRATE
	pass # Replace with function body.

func _setup_import_dialog_dir() -> void:
	if DirAccess.dir_exists_absolute("res://exported maps"):
		file_dialog.current_dir = "res://exported maps"
	elif DirAccess.dir_exists_absolute("res://exported_maps"):
		file_dialog.current_dir = "res://exported_maps"
	else:
		file_dialog.current_dir = "res://"


func _on_generate_button_pressed() -> void:
	start_panel.visible = false
	emit_signal("simulation_mode_selected", null)


func _on_import_button_pressed() -> void:
	file_dialog.popup_centered_ratio(0.75)


func _on_import_file_dialog_file_selected(path: String) -> void:
	start_panel.visible = false
	emit_signal("simulation_mode_selected", path)


func _on_export_map_button_pressed() -> void:
	emit_signal("export_map_requested")


func show_status_message(message: String, is_error: bool = false) -> void:
	status_label.text = message
	if is_error:
		status_label.modulate = Color(1.0, 0.6, 0.6, 1.0)
	else:
		status_label.modulate = Color(0.7, 1.0, 0.7, 1.0)
