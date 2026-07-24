extends Area2D
## Arrow fired by bow-type weapons.

var speed := 640.0
var direction := 1
var damage := 10.0
var shooter: Character
var special := ""


func _ready() -> void:
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(24, 6)
	col.shape = shape
	add_child(col)

	var visual := Polygon2D.new()
	visual.polygon = PackedVector2Array([
		Vector2(-12, -2), Vector2(6, -2), Vector2(12, 0), Vector2(6, 2), Vector2(-12, 2)
	])
	visual.color = Color(0.95, 0.85, 0.4) if special != "ice" else Color(0.5, 0.8, 1.0)
	visual.scale.x = direction
	add_child(visual)

	body_entered.connect(_on_body_entered)
	get_tree().create_timer(3.0).timeout.connect(queue_free)


func _physics_process(delta: float) -> void:
	position.x += speed * direction * delta


func _on_body_entered(body: Node) -> void:
	if body == shooter:
		return
	if body is Character:
		body.take_damage(damage, shooter, false)
		queue_free()
	elif body is StaticBody2D:
		queue_free()
