extends Node
## Game clock. 1 game hour = 2 real minutes at 1x (factor 30). Speeds: 0 = pause, 1x, 3x, 10x.
## Simulation code uses the (already time-scaled) _process delta; this node owns Engine.time_scale.

const GAME_SECONDS_PER_REAL_SECOND := 30.0
const SPEEDS := [0.0, 1.0, 3.0, 10.0]

var day: int = 1                 # day counter, 1 = first day
var minutes: float = 7.0 * 60.0  # minutes since midnight
var day_of_year: int = 105       # mid April as default season (good light)
var speed_index: int = 1
var running: bool = false        # false while in menus / loading
var _last_minute: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func start(start_day: int = 1, start_minutes: float = 7.0 * 60.0) -> void:
	day = start_day
	minutes = start_minutes
	running = true
	set_speed(1)


func stop() -> void:
	running = false
	Engine.time_scale = 1.0
	if is_inside_tree():
		get_tree().paused = false


func set_speed(index: int) -> void:
	speed_index = clampi(index, 0, SPEEDS.size() - 1)
	if speed_index == 0:
		get_tree().paused = true
		Engine.time_scale = 1.0
	else:
		get_tree().paused = false
		Engine.time_scale = SPEEDS[speed_index]
	Events.speed_changed.emit(speed_index)


func toggle_pause() -> void:
	set_speed(1 if speed_index == 0 else 0)


func is_paused() -> bool:
	return speed_index == 0


func _process(delta: float) -> void:
	if not running or speed_index == 0:
		return
	# delta is already scaled by Engine.time_scale
	minutes += delta * GAME_SECONDS_PER_REAL_SECOND / 60.0
	while minutes >= 1440.0:
		minutes -= 1440.0
		day += 1
		day_of_year = (day_of_year % 365) + 1
	var m := int(minutes)
	if m != _last_minute:
		_last_minute = m
		Events.time_tick.emit(day, minutes)


## Total game minutes since start of day 1 (monotonic, used for deadlines and durations).
func total_minutes() -> float:
	return float(day - 1) * 1440.0 + minutes


## Convert a real-time-at-1x duration to game minutes and back.
static func game_minutes_to_sim_seconds(game_min: float) -> float:
	return game_min * 60.0 / GAME_SECONDS_PER_REAL_SECOND


func hour() -> float:
	return minutes / 60.0


func time_string() -> String:
	var h := int(minutes / 60.0)
	var mi := int(minutes) % 60
	return "%02d:%02d" % [h, mi]


func date_string() -> String:
	# Map day_of_year to a calendar date (non-leap year) for display.
	var months := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	var names := ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"]
	var d := day_of_year
	var mo := 0
	while mo < 12 and d > months[mo]:
		d -= months[mo]
		mo += 1
	var weekdays := ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
	return "%s %d. %s · Tag %d" % [weekdays[(day - 1) % 7], d, names[mini(mo, 11)], day]


## Solar position (elevation, azimuth in radians) for latitude/longitude at current game time.
## Azimuth: 0 = north, PI/2 = east. Uses a compact NOAA-style approximation (local solar time ~ clock).
func sun_position(lat_deg: float) -> Vector2:
	return sun_position_at(lat_deg, hour())


## Solar position for an explicit clock hour (DayNight uses it for the debug light override).
func sun_position_at(lat_deg: float, clock_hour: float) -> Vector2:
	var decl := deg_to_rad(23.44) * sin(TAU * (284.0 + day_of_year) / 365.0)
	var lat := deg_to_rad(lat_deg)
	# treat clock as local solar time shifted by +1h (CET-ish summer offset) for nicer evenings
	var solar_hour := clock_hour - 1.0
	var ha := deg_to_rad(15.0 * (solar_hour - 12.0))
	var sin_el := sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(ha)
	var el := asin(clampf(sin_el, -1.0, 1.0))
	var cos_az := (sin(decl) - sin(el) * sin(lat)) / maxf(0.0001, cos(el) * cos(lat))
	var az := acos(clampf(cos_az, -1.0, 1.0))
	if ha > 0.0:
		az = TAU - az
	return Vector2(el, az)
