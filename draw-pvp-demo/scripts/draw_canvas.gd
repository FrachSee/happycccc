class_name DrawCanvas
extends Panel
## A paintable canvas slot. Mouse strokes are rasterized straight into an
## Image, which is later analyzed by DrawAnalyzer and stylized by RenderEffect.

const CANVAS_SIZE := 220
const BRUSH_RADIUS := 6

var brush_color := Color(0.88, 0.24, 0.24)

var _image: Image
var _texture: ImageTexture
var _rect: TextureRect
var _drawing := false
var _last_pos := Vector2.ZERO


func _ready() -> void:
	custom_minimum_size = Vector2(CANVAS_SIZE, CANVAS_SIZE)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.93, 0.92, 0.88)
	sb.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", sb)

	_image = Image.create(CANVAS_SIZE, CANVAS_SIZE, false, Image.FORMAT_RGBA8)
	_texture = ImageTexture.create_from_image(_image)
	_rect = TextureRect.new()
	_rect.texture = _texture
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_drawing = event.pressed
		if event.pressed:
			_last_pos = event.position
			_paint_line(_last_pos, event.position)
	elif event is InputEventMouseMotion and _drawing:
		_paint_line(_last_pos, event.position)
		_last_pos = event.position


func _paint_line(from: Vector2, to: Vector2) -> void:
	var steps := int(maxf(1.0, from.distance_to(to) / 2.0))
	for i in range(steps + 1):
		_paint_dot(from.lerp(to, float(i) / float(steps)))
	_texture.update(_image)


func _paint_dot(pos: Vector2) -> void:
	var center := Vector2i(pos)
	for dy in range(-BRUSH_RADIUS, BRUSH_RADIUS + 1):
		for dx in range(-BRUSH_RADIUS, BRUSH_RADIUS + 1):
			if dx * dx + dy * dy > BRUSH_RADIUS * BRUSH_RADIUS:
				continue
			var p := center + Vector2i(dx, dy)
			if p.x >= 0 and p.x < CANVAS_SIZE and p.y >= 0 and p.y < CANVAS_SIZE:
				_image.set_pixelv(p, brush_color)


func clear() -> void:
	_image.fill(Color(0, 0, 0, 0))
	_texture.update(_image)


func get_image() -> Image:
	return _image
