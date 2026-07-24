extends Area2D
## Projectile: bow arrows, skill shots, arrow rain and ground waves.

var speed := 640.0
var direction := 1
var damage := 10.0
var shooter: Character
var special := "" # "" / ice / power / wave
var pierce := false
var velocity := Vector2.ZERO # set for rain arrows / waves; else horizontal

var _hit: Array = []


func _ready() -> void:
	if velocity == Vector2.ZERO:
		velocity = Vector2(speed * direction, 0)
	rotation = velocity.angle()

	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(24, 6)
	col.shape = shape
	add_child(col)

	var visual := Polygon2D.new()
	visual.polygon = PackedVector2Array([
		Vector2(-12, -2), Vector2(6, -2), Vector2(12, 0), Vector2(6, 2), Vector2(-12, 2)
	])
	match special:
		"ice":
			visual.color = Color(0.5, 0.8, 1.0)
		"power":
			visual.color = Color(1.0, 0.85, 0.3)
			visual.scale = Vector2(1.6, 1.6)
		"wave":
			visual.color = Color(1.0, 0.55, 0.25, 0.85)
			visual.polygon = PackedVector2Array([
				Vector2(-16, 6), Vector2(-6, -10), Vector2(4, 2),
				Vector2(12, -8), Vector2(18, 6)
			])
			shape.size = Vector2(34, 16)
		_:
			visual.color = Color(0.95, 0.85, 0.4)
	add_child(visual)

	# Small fading trail so shots read in motion.
	var trail := CPUParticles2D.new()
	trail.amount = 10
	trail.lifetime = 0.25
	trail.local_coords = false
	trail.scale_amount_min = 1.5
	trail.scale_amount_max = 2.5
	trail.gravity = Vector2.ZERO
	trail.color = Color(visual.color.r, visual.color.g, visual.color.b, 0.4)
	add_child(trail)

	body_entered.connect(_on_body_entered)
	get_tree().create_timer(3.0).timeout.connect(queue_free)


func _physics_process(delta: float) -> void:
	position += velocity * delta


func _on_body_entered(body: Node) -> void:
	if body == shooter or _hit.has(body):
		return
	if body is Character:
		_hit.append(body)
		body.take_damage(damage, shooter, false)
		if special == "ice":
			body.slow_timer = 1.4
		VFX.burst(get_parent(), global_position, Color(1, 0.9, 0.7), 8, 150.0, 0.3)
		if not pierce:
			queue_free()
	elif body is StaticBody2D:
		if special == "wave":
			return # waves slide along the ground
		queue_free()
