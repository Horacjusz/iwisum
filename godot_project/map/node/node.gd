extends Node2D

var COLOR = Color.BLACK

var roads = []
var stops = []
var virtual_edges = []  # Edges to other stops on transit lines
var schedule := {}

@onready var node_visualization: Sprite2D = $NodeVisualization

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	self.z_index = 1
	queue_redraw()
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
	
func redraw() :
	queue_redraw()
	
func _draw() :
	node_visualization.redraw()

func set_schedule_data(schedule_data: Dictionary, map_nodes: Array = []) -> void:
	schedule = {}
	if schedule_data.has("lines") and schedule_data["lines"] is Dictionary:
		schedule_data = schedule_data["lines"]

	for line_key in schedule_data.keys():
		var line_data = schedule_data.get(line_key, {})
		if line_data is Dictionary:
			schedule[str(line_key)] = {
				"arrivals": _normalize_events(line_data.get("arrivals", []), "from_node", "from_index", map_nodes),
				"departures": _normalize_events(line_data.get("departures", []), "to_node", "to_index", map_nodes),
			}
		else:
			schedule[str(line_key)] = {
				"arrivals": _normalize_events(line_data, "from_node", "from_index", map_nodes),
				"departures": [],
			}

func record_arrival(line_number: int, tick: int, from_node = null, start_tick = null) -> void:
	_record_event(line_number, "arrivals", tick, from_node, "from_node", start_tick)

func record_departure(line_number: int, tick: int, to_node = null, start_tick = null) -> void:
	_record_event(line_number, "departures", tick, to_node, "to_node", start_tick)

func _record_event(line_number: int, event_type: String, tick: int, node_ref = null, node_ref_key: String = "", start_tick = null) -> void:
	# Ignore events that reference no node (spawn / terminal) — don't record them in schedules
	if node_ref_key != "" and node_ref == null:
		return

	var line_entry = _ensure_line_entry(line_number)
	var events: Array = line_entry.get(event_type, [])
	var event_data = {"tick": int(tick)}
	if start_tick != null:
		event_data["start_tick"] = int(start_tick)
	if node_ref_key != "":
		event_data[node_ref_key] = node_ref

	for existing in events:
		if _events_match(existing, event_data, node_ref_key):
			return

	events.append(event_data)
	events.sort_custom(func(a, b): return int(a.get("tick", 0)) < int(b.get("tick", 0)))
	line_entry[event_type] = events
	schedule[str(line_number)] = line_entry

func _ensure_line_entry(line_number: int) -> Dictionary:
	var line_key = str(line_number)
	if not schedule.has(line_key) or not (schedule[line_key] is Dictionary):
		schedule[line_key] = {"arrivals": [], "departures": []}
	return schedule[line_key]

func _normalize_events(events, node_ref_key: String, node_index_key: String, map_nodes: Array) -> Array:
	var normalized := []
	if events is Array == false:
		return normalized

	for event in events:
		if event is Dictionary:
			var tick = int(event.get("tick", event.get("time", 0)))
			var start_tick = null
			if event.has("start_tick"):
				start_tick = int(event.get("start_tick"))
			var node_ref = event.get(node_ref_key, null)
			if node_ref == null and event.has(node_index_key):
				var node_index = int(event.get(node_index_key, -1))
				if node_index >= 0 and node_index < map_nodes.size():
					node_ref = map_nodes[node_index]
			normalized.append({"tick": tick, "start_tick": start_tick, node_ref_key: node_ref})
		else:
			normalized.append({"tick": int(event), "start_tick": int(event), node_ref_key: null})

	normalized.sort_custom(func(a, b): return int(a.get("tick", 0)) < int(b.get("tick", 0)))
	return normalized

func _events_match(a: Dictionary, b: Dictionary, node_ref_key: String) -> bool:
	if int(a.get("tick", -1)) != int(b.get("tick", -2)):
		return false
	# Compare start_tick only if both events explicitly have it
	var a_has_start = a.has("start_tick")
	var b_has_start = b.has("start_tick")
	if a_has_start and b_has_start:
		if int(a.get("start_tick", -1)) != int(b.get("start_tick", -2)):
			return false
	if node_ref_key == "":
		return true
	return a.get(node_ref_key, null) == b.get(node_ref_key, null)

func add_road(road) :
	var other = road.end
	if road.start != self : return
	if other == self : return
	if roads.has(road) : return
	roads.append(road)
