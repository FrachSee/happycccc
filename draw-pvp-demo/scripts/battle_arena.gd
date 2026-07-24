extends Node2D
## Phase 2: side-view arena. Spawns both fighters, drives HUD and result screen.

signal restart_requested

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const AI_SCENE := preload("res://scenes/ai_opponent.tscn")

const FLOOR_Y := 620.0

var player: Character
var ai: Character

var _player_hp_bar: ProgressBar
var _player_armor_bar: ProgressBar
var _ai_hp_bar: ProgressBar
var _ai_armor_bar: ProgressBar
var _player_skill_labels: Array[Label] = []
var _ai_skill_labels: Array[Label] = []
var _hud: CanvasLayer
var _finished := false


func setup(player_loadouts: Dictionary, ai_loadouts: Dictionary) -> void:
	_build_arena()

	player = PLAYER_SCENE.instantiate()
	add_child(player)
	player.global_position = Vector2(300, FLOOR_Y - 40)
	player.setup(player_loadouts, true, Color(0.35, 0.65, 0.95))

	ai = AI_SCENE.instantiate()
	add_child(ai)
	ai.global_position = Vector2(980, FLOOR_Y - 40)
	ai.setup(ai_loadouts, false, Color(0.9, 0.4, 0.4))

	player.enemy = ai
	ai.enemy = player
	var controller: AIController = ai.get_node("AIController")
	controller.me = ai
	controller.target = player

	_build_hud(player_loadouts, ai_loadouts)
	player.stats_changed.connect(_update_bars)
	ai.stats_changed.connect(_update_bars)
	player.died.connect(_on_fighter_died)
	ai.died.connect(_on_fighter_died)
	_update_bars()


func _build_arena() -> void:
	var camera := Camera2D.new()
	camera.position = Vector2(640, 360)
	add_child(camera)
	camera.make_current()

	# Gradient dusk sky (vertex-colored quad).
	var sky := Polygon2D.new()
	sky.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(1280, 0), Vector2(1280, 720), Vector2(0, 720)
	])
	sky.vertex_colors = PackedColorArray([
		Color(0.06, 0.07, 0.16), Color(0.09, 0.07, 0.18),
		Color(0.30, 0.16, 0.28), Color(0.26, 0.14, 0.24),
	])
	sky.z_index = -20
	add_child(sky)

	# Moon and stars.
	var moon := Polygon2D.new()
	var moon_points := PackedVector2Array()
	for i in range(24):
		var a := TAU * i / 24.0
		moon_points.append(Vector2(cos(a), sin(a)) * 46.0)
	moon.polygon = moon_points
	moon.color = Color(0.94, 0.92, 0.82, 0.9)
	moon.position = Vector2(1050, 120)
	moon.z_index = -19
	add_child(moon)
	var star_rng := RandomNumberGenerator.new()
	star_rng.seed = 42
	for i in range(40):
		var star := ColorRect.new()
		star.size = Vector2(2, 2)
		star.color = Color(1, 1, 1, star_rng.randf_range(0.25, 0.8))
		star.position = Vector2(star_rng.randf_range(0, 1280), star_rng.randf_range(0, 420))
		star.z_index = -19
		add_child(star)

	# Distant hill silhouettes (two cheap parallax-style layers).
	_add_ridge(Color(0.13, 0.10, 0.22), 470.0, 90.0, 7)
	_add_ridge(Color(0.18, 0.12, 0.24), 530.0, 55.0, 9)

	# Ground with tile seams and a lit top edge.
	var floor_visual := ColorRect.new()
	floor_visual.color = Color(0.24, 0.19, 0.28)
	floor_visual.position = Vector2(0, FLOOR_Y)
	floor_visual.size = Vector2(1280, 720 - FLOOR_Y)
	add_child(floor_visual)
	var edge := ColorRect.new()
	edge.color = Color(0.45, 0.35, 0.5)
	edge.position = Vector2(0, FLOOR_Y)
	edge.size = Vector2(1280, 5)
	add_child(edge)
	for x in range(0, 1280, 80):
		var seam := ColorRect.new()
		seam.color = Color(0.16, 0.12, 0.2)
		seam.position = Vector2(x, FLOOR_Y + 5)
		seam.size = Vector2(3, 720 - FLOOR_Y - 5)
		add_child(seam)

	_add_static_box(Vector2(640, FLOOR_Y + 50), Vector2(1280, 100)) # floor
	_add_static_box(Vector2(-20, 360), Vector2(40, 720)) # left wall
	_add_static_box(Vector2(1300, 360), Vector2(40, 720)) # right wall


func _add_ridge(color: Color, base_y: float, height: float, peaks: int) -> void:
	var ridge := Polygon2D.new()
	var points := PackedVector2Array()
	points.append(Vector2(0, FLOOR_Y))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(base_y) + peaks
	for i in range(peaks + 1):
		var x := 1280.0 * i / peaks
		points.append(Vector2(x, base_y - rng.randf_range(0.2, 1.0) * height))
	points.append(Vector2(1280, FLOOR_Y))
	ridge.polygon = points
	ridge.color = color
	ridge.z_index = -18
	add_child(ridge)


func _add_static_box(pos: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	body.position = pos
	add_child(body)


func _build_hud(player_loadouts: Dictionary, ai_loadouts: Dictionary) -> void:
	_hud = CanvasLayer.new()
	add_child(_hud)

	var p := _build_fighter_panel("玩家", player_loadouts, player, Vector2(30, 20), _player_skill_labels)
	_player_hp_bar = p[0]
	_player_armor_bar = p[1]
	var a := _build_fighter_panel("AI 对手", ai_loadouts, ai, Vector2(1280 - 30 - 420, 20), _ai_skill_labels)
	_ai_hp_bar = a[0]
	_ai_armor_bar = a[1]

	var controls := Label.new()
	controls.text = "A/D 移动  K/W/空格 跳跃  S 下蹲/速降  J 攻击  W+J/S+J 派生技  L 格挡(需蓝甲)  U/I/O 技能"
	controls.position = Vector2(0, 690)
	controls.size = Vector2(1280, 24)
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls.add_theme_color_override("font_color", Color(0.6, 0.63, 0.72))
	_hud.add_child(controls)


func _build_fighter_panel(fighter_name: String, loadouts: Dictionary, fighter: Character, pos: Vector2, skill_labels: Array[Label]) -> Array:
	var box := VBoxContainer.new()
	box.position = pos
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 4)
	_hud.add_child(box)

	var name_label := Label.new()
	name_label.text = fighter_name
	name_label.add_theme_font_size_override("font_size", 20)
	box.add_child(name_label)

	var hp_bar := _make_bar(Color(0.35, 0.8, 0.35))
	box.add_child(hp_bar)
	var armor_bar := _make_bar(Color(0.65, 0.65, 0.7))
	armor_bar.custom_minimum_size.y = 10
	box.add_child(armor_bar)

	var summary := Label.new()
	var lines := []
	for slot in loadouts:
		lines.append(loadouts[slot].summary)
	summary.text = "\n".join(lines)
	summary.add_theme_font_size_override("font_size", 13)
	summary.add_theme_color_override("font_color", Color(0.72, 0.75, 0.85))
	box.add_child(summary)

	# Skill cooldown row (keys U / I / O).
	var skill_row := HBoxContainer.new()
	skill_row.add_theme_constant_override("separation", 14)
	box.add_child(skill_row)
	for i in range(fighter.skills.size()):
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 14)
		skill_row.add_child(label)
		skill_labels.append(label)
	return [hp_bar, armor_bar]


func _process(_delta: float) -> void:
	if player:
		_update_skill_labels(player, _player_skill_labels)
	if ai:
		_update_skill_labels(ai, _ai_skill_labels)


func _update_skill_labels(fighter: Character, labels: Array[Label]) -> void:
	for i in range(mini(labels.size(), fighter.skills.size())):
		var skill: Dictionary = fighter.skills[i]
		var ready: bool = skill["cd_left"] <= 0.0
		labels[i].text = "[%s] %s %s" % [
			Skills.KEY_LABELS[i], skill["name"],
			"就绪" if ready else "%.1fs" % skill["cd_left"],
		]
		labels[i].add_theme_color_override(
			"font_color",
			Color(0.55, 0.95, 0.6) if ready else Color(0.55, 0.57, 0.65))


func _make_bar(fill_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(420, 20)
	bar.show_percentage = false
	bar.max_value = 100
	bar.value = 100
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.12, 0.8)
	bg.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bg)
	return bar


func _update_bars() -> void:
	_player_hp_bar.max_value = player.max_hp
	_player_hp_bar.value = player.hp
	_player_armor_bar.max_value = maxf(player.max_armor, 1.0)
	_player_armor_bar.value = player.armor
	_ai_hp_bar.max_value = ai.max_hp
	_ai_hp_bar.value = ai.hp
	_ai_armor_bar.max_value = maxf(ai.max_armor, 1.0)
	_ai_armor_bar.value = ai.armor


func _on_fighter_died(who: Character) -> void:
	if _finished:
		return
	_finished = true
	var player_won := who == ai
	_show_result(player_won)


func _show_result(player_won: bool) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.add_child(dim)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.add_theme_constant_override("separation", 20)
	_hud.add_child(box)

	var label := Label.new()
	label.text = "胜利! 你的画作大获全胜!" if player_won else "战败… 回去重新作画吧!"
	label.add_theme_font_size_override("font_size", 40)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)

	var btn := Button.new()
	btn.text = "再来一局 (重新作画)"
	btn.add_theme_font_size_override("font_size", 24)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(func() -> void: restart_requested.emit())
	box.add_child(btn)
