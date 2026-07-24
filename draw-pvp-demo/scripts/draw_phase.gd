extends Control
## Phase 1: draw your gear on three canvases, then start the battle.

signal drawing_finished(loadouts: Dictionary)

const SLOT_NAMES := {
	LoadoutData.Slot.WEAPON: "武器",
	LoadoutData.Slot.ARMOR: "护甲",
	LoadoutData.Slot.ACCESSORY: "饰品",
}
const SLOT_HINTS := {
	LoadoutData.Slot.WEAPON: "横长=长枪 密集=剑 稀疏=弓",
	LoadoutData.Slot.ARMOR: "密/深=重甲 红=荆棘 蓝=格挡 绿=回复",
	LoadoutData.Slot.ACCESSORY: "颜色决定加成 瘦高=+闪避",
}
const BRUSH_COLORS := [
	["红(火/荆棘)", Color(0.88, 0.24, 0.24)],
	["蓝(冰/格挡)", Color(0.28, 0.55, 0.95)],
	["绿(回复)", Color(0.30, 0.80, 0.38)],
	["深色(重甲)", Color(0.16, 0.16, 0.22)],
	["黄(中性)", Color(0.95, 0.85, 0.32)],
]

var _canvases := {} # slot -> DrawCanvas
var _color_buttons: Array[Button] = []


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.13, 0.19)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 60
	vbox.offset_right = -60
	vbox.offset_top = 24
	vbox.offset_bottom = -24
	vbox.add_theme_constant_override("separation", 14)
	add_child(vbox)

	var title := Label.new()
	title.text = "作画对决 — 画出你的装备!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	vbox.add_child(title)

	# Three canvas slots.
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 40)
	vbox.add_child(row)
	for slot in SLOT_NAMES:
		row.add_child(_build_slot(slot))

	# Brush palette.
	var palette := HBoxContainer.new()
	palette.alignment = BoxContainer.ALIGNMENT_CENTER
	palette.add_theme_constant_override("separation", 10)
	vbox.add_child(palette)
	var palette_label := Label.new()
	palette_label.text = "画笔颜色: "
	palette.add_child(palette_label)
	for entry in BRUSH_COLORS:
		var btn := Button.new()
		btn.text = entry[0]
		btn.add_theme_color_override("font_color", entry[1].lightened(0.3))
		btn.pressed.connect(_on_color_picked.bind(entry[1], btn))
		palette.add_child(btn)
		_color_buttons.append(btn)
	_color_buttons[0].text = "✓" + _color_buttons[0].text

	var hint := Label.new()
	hint.text = "笔画越密 -> 攻击/护甲越高，越稀疏 -> 速度越快。画完点击开始，AI 会将你的画作渲染成装备!"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.7, 0.72, 0.8))
	vbox.add_child(hint)

	var start := Button.new()
	start.text = "开始战斗"
	start.add_theme_font_size_override("font_size", 26)
	start.custom_minimum_size = Vector2(220, 54)
	start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start.pressed.connect(_on_start_pressed)
	vbox.add_child(start)


func _build_slot(slot: int) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)

	var label := Label.new()
	label.text = SLOT_NAMES[slot]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	col.add_child(label)

	var canvas := DrawCanvas.new()
	_canvases[slot] = canvas
	col.add_child(canvas)

	var hint := Label.new()
	hint.text = SLOT_HINTS[slot]
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.6, 0.63, 0.72))
	col.add_child(hint)

	var clear := Button.new()
	clear.text = "清空"
	clear.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	clear.pressed.connect(canvas.clear)
	col.add_child(clear)
	return col


func _on_color_picked(color: Color, source: Button) -> void:
	for canvas in _canvases.values():
		canvas.brush_color = color
	for btn in _color_buttons:
		btn.text = btn.text.trim_prefix("✓")
	source.text = "✓" + source.text


func _on_start_pressed() -> void:
	var loadouts := {}
	for slot in _canvases:
		var img: Image = _canvases[slot].get_image()
		var data := DrawAnalyzer.analyze(img, slot)
		if img.get_used_rect().size.x > 0:
			data.texture = RenderEffect.render(img)
		loadouts[slot] = data
	drawing_finished.emit(loadouts)
