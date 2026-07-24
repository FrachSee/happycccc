class_name VFX
## Lightweight one-shot visual effects: particle bursts, slash arcs,
## floating skill names, auras, screen shake, hit flashes.


static func burst(parent: Node, pos: Vector2, color: Color, amount := 16,
		speed := 220.0, life := 0.5, dir := Vector2.UP, spread := 180.0) -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 1.0
	p.direction = dir
	p.spread = spread
	p.gravity = Vector2(0, 320)
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.5
	p.color = color
	parent.add_child(p)
	p.global_position = pos
	parent.get_tree().create_timer(life + 0.6).timeout.connect(
		func() -> void:
			if is_instance_valid(p):
				p.queue_free())


# Fading arc trail for melee swings (flip = facing).
static func slash_arc(parent: Node, pos: Vector2, radius: float, color: Color,
		flip := 1, angle_from := -1.9, angle_to := 0.7) -> void:
	var line := Line2D.new()
	line.width = 12.0
	line.default_color = color
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	var points := PackedVector2Array()
	for i in range(13):
		var a: float = lerpf(angle_from, angle_to, float(i) / 12.0)
		points.append(Vector2(cos(a) * flip, sin(a)) * radius)
	line.points = points
	line.z_index = 5
	parent.add_child(line)
	line.global_position = pos
	var tween := line.create_tween()
	tween.tween_property(line, "modulate:a", 0.0, 0.28)
	tween.tween_callback(line.queue_free)


static func popup(parent: Node, pos: Vector2, text: String, color := Color.WHITE) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 8)
	label.z_index = 60
	parent.add_child(label)
	label.global_position = pos + Vector2(-46, -84)
	var tween := label.create_tween()
	tween.tween_property(label, "position:y", label.position.y - 42.0, 0.7) \
		.set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.5).set_delay(0.25)
	tween.tween_callback(label.queue_free)


# Pulsing colored ring around a fighter while a skill is active.
static func aura(host: Node2D, color: Color, duration: float, radius := 44.0) -> void:
	var ring := Polygon2D.new()
	var points := PackedVector2Array()
	for i in range(24):
		var a := TAU * i / 24.0
		points.append(Vector2(cos(a), sin(a)) * radius)
	ring.polygon = points
	ring.color = Color(color.r, color.g, color.b, 0.22)
	ring.z_index = -1
	host.add_child(ring)
	var tween := ring.create_tween().set_loops()
	tween.tween_property(ring, "scale", Vector2(1.15, 1.15), 0.3)
	tween.tween_property(ring, "scale", Vector2(0.9, 0.9), 0.3)
	host.get_tree().create_timer(duration).timeout.connect(
		func() -> void:
			if is_instance_valid(ring):
				ring.queue_free())


static func shake(from_node: Node, strength := 6.0, duration := 0.25) -> void:
	var cam := from_node.get_viewport().get_camera_2d()
	if cam == null:
		return
	var tween := cam.create_tween()
	var steps := 5
	for i in range(steps):
		var falloff := 1.0 - float(i) / float(steps)
		tween.tween_property(cam, "offset",
			Vector2(randf_range(-1, 1), randf_range(-1, 1)) * strength * falloff,
			duration / steps)
	tween.tween_property(cam, "offset", Vector2.ZERO, duration / steps)


static func hit_flash(target: CanvasItem) -> void:
	var alpha := target.modulate.a
	target.modulate = Color(4.0, 4.0, 4.0, alpha)
	var tween := target.create_tween()
	tween.tween_property(target, "modulate", Color(1, 1, 1, alpha), 0.18)
