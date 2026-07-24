extends Node
## Flow controller (root of main.tscn): draw phase -> battle -> restart.
## Also procedurally "draws" the AI opponent's gear so the same
## analyzer/render pipeline is used for both sides.

const DRAW_PHASE_SCENE := preload("res://scenes/draw_phase.tscn")
const BATTLE_SCENE := preload("res://scenes/battle.tscn")
const CANVAS_SIZE := 220

var _current: Node
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_start_draw_phase()


func _start_draw_phase() -> void:
	_swap_to(DRAW_PHASE_SCENE.instantiate())
	_current.drawing_finished.connect(_on_drawing_finished)


func _on_drawing_finished(player_loadouts: Dictionary) -> void:
	var ai_loadouts := _generate_ai_loadouts()
	var battle := BATTLE_SCENE.instantiate()
	_swap_to(battle)
	battle.setup(player_loadouts, ai_loadouts)
	battle.restart_requested.connect(_start_draw_phase)


func _swap_to(node: Node) -> void:
	if is_instance_valid(_current):
		_current.queue_free()
	_current = node
	add_child(node)


# --- Procedural AI "drawings" -------------------------------------------

func _generate_ai_loadouts() -> Dictionary:
	var out := {}
	for slot in [LoadoutData.Slot.WEAPON, LoadoutData.Slot.ARMOR, LoadoutData.Slot.ACCESSORY]:
		var img := _random_drawing(slot)
		var data := DrawAnalyzer.analyze(img, slot)
		data.texture = WeaponSpriteFactory.texture_for_slot(img, slot)
		out[slot] = data
	return out


func _random_drawing(slot: int) -> Image:
	var img := Image.create(CANVAS_SIZE, CANVAS_SIZE, false, Image.FORMAT_RGBA8)
	var colors := [
		Color(0.88, 0.24, 0.24), Color(0.28, 0.55, 0.95),
		Color(0.30, 0.80, 0.38), Color(0.16, 0.16, 0.22),
		Color(0.95, 0.85, 0.32),
	]
	var color: Color = colors[_rng.randi_range(0, colors.size() - 1)]
	match slot:
		LoadoutData.Slot.WEAPON:
			match _rng.randi_range(0, 2):
				0: # long bar -> spear
					_fill_rect(img, Rect2i(20, 95, 180, 26), color)
				1: # dense blob -> sword
					_fill_rect(img, Rect2i(80, 40, 60, 140), color)
					_fill_rect(img, Rect2i(50, 130, 120, 24), color)
				2: # sparse arc -> bow
					_fill_circle(img, Vector2i(110, 110), 70, color)
					_fill_circle(img, Vector2i(110, 110), 58, Color(0, 0, 0, 0))
		LoadoutData.Slot.ARMOR:
			var size := _rng.randi_range(60, 150)
			_fill_rect(img, Rect2i(110 - size / 2, 110 - size / 2, size, size), color)
		LoadoutData.Slot.ACCESSORY:
			_fill_circle(img, Vector2i(110, 110), _rng.randi_range(25, 55), color)
	return img


func _fill_rect(img: Image, rect: Rect2i, color: Color) -> void:
	for y in range(maxi(rect.position.y, 0), mini(rect.end.y, CANVAS_SIZE)):
		for x in range(maxi(rect.position.x, 0), mini(rect.end.x, CANVAS_SIZE)):
			img.set_pixel(x, y, color)


func _fill_circle(img: Image, center: Vector2i, radius: int, color: Color) -> void:
	for y in range(maxi(center.y - radius, 0), mini(center.y + radius + 1, CANVAS_SIZE)):
		for x in range(maxi(center.x - radius, 0), mini(center.x + radius + 1, CANVAS_SIZE)):
			var d := Vector2i(x, y) - center
			if d.x * d.x + d.y * d.y <= radius * radius:
				img.set_pixel(x, y, color)
