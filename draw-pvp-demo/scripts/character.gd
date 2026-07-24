class_name Character
extends CharacterBody2D
## Shared fighter logic for both the player and the AI opponent.
## Stats come from LoadoutData (analyzed drawings). Movement intents are
## written either from keyboard input (player) or by AIController.

signal stats_changed
signal died(who: Character)

const GRAVITY := 1800.0
const JUMP_VELOCITY := -650.0
const PROJECTILE_SCENE := preload("res://scenes/projectile.tscn")

var display_name := "玩家"
var is_player := true

var max_hp := 100.0
var hp := 100.0
var max_armor := 0.0
var armor := 0.0
var defense := 0.0
var move_speed := 240.0
var atk := 10.0
var reach := 85.0
var weapon_type := "sword"
var weapon_special := ""
var thorns := 0.0
var regen_rate := 0.0
var can_block := false

var facing := 1
var blocking := false
var attack_cooldown := 0.0
var attack_window := 0.0
var slow_timer := 0.0
var _hit_targets: Array = []

# One-shot intents are consumed each physics frame.
var intent_move := 0.0
var intent_jump := false
var intent_attack := false
var intent_block := false

var enemy: Character

var _rig: Node2D
var _body_poly: Polygon2D
var _armor_sprite: Sprite2D
var _weapon_sprite: Sprite2D
var _hitbox: Area2D
var _hitbox_shape: CollisionShape2D


func _ready() -> void:
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(36, 64)
	col.shape = shape
	add_child(col)

	_rig = Node2D.new()
	add_child(_rig)

	_body_poly = Polygon2D.new()
	_body_poly.polygon = PackedVector2Array([
		Vector2(-18, -32), Vector2(18, -32), Vector2(18, 32), Vector2(-18, 32)
	])
	_body_poly.color = Color(0.75, 0.75, 0.8)
	_rig.add_child(_body_poly)

	# Simple "head" so the figure reads as a character.
	var head := Polygon2D.new()
	var head_points := PackedVector2Array()
	for i in range(12):
		var a := TAU * i / 12.0
		head_points.append(Vector2(cos(a), sin(a)) * 11.0 + Vector2(0, -44))
	head.polygon = head_points
	head.color = Color(0.9, 0.82, 0.7)
	_rig.add_child(head)

	_armor_sprite = Sprite2D.new()
	_armor_sprite.scale = Vector2(0.24, 0.24)
	_armor_sprite.modulate = Color(1, 1, 1, 0.95)
	_rig.add_child(_armor_sprite)

	_weapon_sprite = Sprite2D.new()
	_weapon_sprite.position = Vector2(30, -10)
	_weapon_sprite.scale = Vector2(0.22, 0.22)
	_rig.add_child(_weapon_sprite)

	_hitbox = Area2D.new()
	_hitbox.monitoring = false
	_hitbox_shape = CollisionShape2D.new()
	var hb_shape := RectangleShape2D.new()
	hb_shape.size = Vector2(reach, 48)
	_hitbox_shape.shape = hb_shape
	_hitbox.add_child(_hitbox_shape)
	_rig.add_child(_hitbox)


# Called by the arena after instancing; loadouts: {Slot -> LoadoutData}.
func setup(loadouts: Dictionary, p_is_player: bool, body_color: Color) -> void:
	is_player = p_is_player
	display_name = "玩家" if is_player else "AI 对手"
	_body_poly.color = body_color

	var weapon: LoadoutData = loadouts[LoadoutData.Slot.WEAPON]
	var armor_data: LoadoutData = loadouts[LoadoutData.Slot.ARMOR]
	var acc: LoadoutData = loadouts[LoadoutData.Slot.ACCESSORY]

	weapon_type = weapon.weapon_type
	weapon_special = weapon.special
	atk = weapon.atk + acc.atk
	reach = weapon.reach
	defense = armor_data.defense + acc.defense
	max_hp = 100.0 + armor_data.hp_bonus + acc.hp_bonus
	hp = max_hp
	max_armor = armor_data.armor_hp + acc.armor_hp
	armor = max_armor
	move_speed = 230.0 + (weapon.spd + armor_data.spd + acc.spd) * 3.0

	thorns = armor_data.special_power if armor_data.special == "thorns" else 0.0
	can_block = armor_data.special == "shield"
	regen_rate = 0.0
	if armor_data.special == "regen":
		regen_rate += armor_data.special_power
	if acc.special == "regen":
		regen_rate += acc.special_power

	if weapon.texture:
		_weapon_sprite.texture = weapon.texture
	if armor_data.texture:
		_armor_sprite.texture = armor_data.texture
		# Armor drawing tints the body too.
	(_hitbox_shape.shape as RectangleShape2D).size = Vector2(reach, 48)
	_hitbox_shape.position = Vector2(reach * 0.5 + 18.0, 0)
	stats_changed.emit()


func _physics_process(delta: float) -> void:
	if hp <= 0.0:
		return
	if is_player:
		_gather_player_input()

	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	velocity.y += GRAVITY * delta

	var speed := move_speed
	if slow_timer > 0.0:
		slow_timer -= delta
		speed *= 0.55
	blocking = intent_block and can_block and is_on_floor()
	if blocking:
		speed *= 0.3
		_body_poly.color = _body_poly.color.lerp(Color(0.4, 0.6, 1.0), 0.2)

	velocity.x = intent_move * speed
	if intent_jump and is_on_floor():
		velocity.y = JUMP_VELOCITY
	if intent_attack and attack_cooldown <= 0.0:
		_start_attack()

	if attack_window > 0.0:
		attack_window -= delta
		_check_melee_hits()
		if attack_window <= 0.0:
			_hitbox.monitoring = false
			_weapon_sprite.rotation = 0.0

	if intent_move != 0.0:
		facing = 1 if intent_move > 0.0 else -1
	elif enemy and is_instance_valid(enemy):
		facing = 1 if enemy.global_position.x > global_position.x else -1
	_rig.scale.x = facing

	move_and_slide()

	if regen_rate > 0.0 and hp < max_hp:
		hp = minf(max_hp, hp + regen_rate * delta)
		stats_changed.emit()

	intent_jump = false
	intent_attack = false


func _gather_player_input() -> void:
	intent_move = Input.get_axis("move_left", "move_right")
	if Input.is_action_just_pressed("jump"):
		intent_jump = true
	if Input.is_action_just_pressed("attack"):
		intent_attack = true
	intent_block = Input.is_action_pressed("block")


func _start_attack() -> void:
	match weapon_type:
		"bow":
			attack_cooldown = 0.9
			_shoot_arrow()
			_weapon_sprite.rotation = -0.4
			get_tree().create_timer(0.15).timeout.connect(_reset_weapon_pose)
		"spear":
			attack_cooldown = 0.8
			attack_window = 0.2
			_hit_targets.clear()
			_hitbox.monitoring = true
			_weapon_sprite.rotation = 0.25
		_:
			attack_cooldown = 0.55
			attack_window = 0.16
			_hit_targets.clear()
			_hitbox.monitoring = true
			_weapon_sprite.rotation = -0.8


func _reset_weapon_pose() -> void:
	if is_instance_valid(_weapon_sprite):
		_weapon_sprite.rotation = 0.0


func _check_melee_hits() -> void:
	for body in _hitbox.get_overlapping_bodies():
		if body is Character and body != self and not _hit_targets.has(body):
			_hit_targets.append(body)
			body.take_damage(atk, self, true)


func _shoot_arrow() -> void:
	var arrow := PROJECTILE_SCENE.instantiate()
	arrow.direction = facing
	arrow.damage = atk
	arrow.shooter = self
	arrow.special = weapon_special
	get_parent().add_child(arrow)
	arrow.global_position = global_position + Vector2(facing * 40.0, -12.0)


func take_damage(amount: float, source: Character, is_melee: bool) -> void:
	if hp <= 0.0:
		return
	var dmg := amount
	# Blocking only works against attacks from the front.
	if blocking and source and sign(source.global_position.x - global_position.x) == facing:
		dmg *= 0.3
	dmg = maxf(1.0, dmg - defense)
	if armor > 0.0:
		var absorbed := minf(armor, dmg)
		armor -= absorbed
		dmg -= absorbed
	hp -= dmg
	if source and source.weapon_special == "ice":
		slow_timer = 1.4
	if is_melee and thorns > 0.0 and source:
		source.take_thorns(amount * thorns)
	_flash_hit()
	stats_changed.emit()
	if hp <= 0.0:
		hp = 0.0
		_die()


func take_thorns(amount: float) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	_flash_hit()
	stats_changed.emit()
	if hp <= 0.0:
		hp = 0.0
		_die()


func _flash_hit() -> void:
	modulate = Color(1, 0.5, 0.5)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.2)


func _die() -> void:
	_hitbox.monitoring = false
	var tween := create_tween()
	tween.tween_property(_rig, "rotation", 0.5 * PI * facing, 0.5)
	tween.parallel().tween_property(self, "modulate:a", 0.4, 0.5)
	died.emit(self)
