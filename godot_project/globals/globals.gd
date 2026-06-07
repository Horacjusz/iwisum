extends Node

const MIN_TICKSPEED = 1.0/6.0
const MAX_TICKSPEED = 30

# how many minutes pass every second
var TICKSPEED := 10.0:
	set(value) :
		TICKSPEED = clamp(value, MIN_TICKSPEED, MAX_TICKSPEED)

const MARGINS = [
	50,   # left margin
	50,   # top margin
	500,  # right margin
	50,   # bottom margin
]

var TICK: int:
	set(value):
		TICK = value % 1440
