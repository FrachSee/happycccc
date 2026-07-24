class_name Character
extends CharacterBody2D
## Shared fighter logic for both the player and the AI opponent.
## Stats come from LoadoutData (analyzed drawings). Movement intents are
## written either from keyboard input (player) or by AIController.

signal stats_changed
signal died(who: Character)

const GRAVITY := 1800.0
const FAST_FALL_GRAVITY := 2200.0
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
var skills: Array = [] # [{id, name, cooldown, cd_left}]

var facing := 1
var blocking := false
var crouching := false
var attack_cooldown := 0.0
var attack_window := 0.0
var slow_timer := 0.0
var burn_timer := 0.0
var burn_dps := 0.0
var iron_wall_timer := 0.0
var invuln_timer := 0.0
var dash_timer := 0.0
var dash_speed := 0.0
var _strike_mult := 1.0
var _strike_burn := false
var _hit_targets: Array = []

# One-shot intents are consumed each physics frame.
var intent_move := 0.0
var intent_jump := false
var intent_attack := false
var intent_block := false
var intent_down := false
var intent_skill := -1

var enemy: Character

var _rig: Node2D
var _body_poly: Polygon2D
var _armor_sprite: Sprite2D
var _weapon_sprite: Sprite2D
var _hitbox: Area2D
var _hitbox_shape: CollisionShape2D
var _body_col: CollisionShape2D


func _ready() -> void:
	_body_col = CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(36, 64)
	_body_col.shape = shape
	add_child(_body_col)

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

	skills = Skills.build(loadouts)

	if weapon.texture:
		_weapon_sprite.texture = weapon.texture
	if armor_data.texture:
		_armor_sprite.texture = armor_data.texture
	(_hitbox_shape.shape as RectangleShape2D).size = Vector2(reach, 48)
	_hitbox_shape.position = Vector2(reach * 0.5 + 18.0, 0)
	stats_changed.emit()


func _physics_process(delta: float) -> void:
	if hp <= 0.0:
		return
	if is_player:
		_gather_player_input()

	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	iron_wall_timer = maxf(0.0, iron_wall_timer - delta)
	invuln_timer = maxf(0.0, invuln_timer - delta)
	for skill in skills:
		skill["cd_left"] = maxf(0.0, skill["cd_left"] - delta)

	# Burn damage-over-time (from Flame Slash).
	if burn_timer > 0.0:
		burn_timer -= delta
		_apply_direct_damage(burn_dps * delta)

	# Gravity; S in the air = fast-fall.
	if not is_on_floor() and intent_down:
		velocity.y += FAST_FALL_GRAVITY * delta
	else:
		velocity.y += GRAVITY * delta

	var speed := move_speed
	if slow_timer > 0.0:
		slow_timer -= delta
		speed *= 0.55
	blocking = intent_block and can_block and is_on_floor()
	if blocking:
		speed *= 0.3
		_body_poly.color = _body_poly.color.lerp(Color(0.4, 0.6, 1.0), 0.2)

	# S on the ground = crouch: slower, shorter hurtbox (arrows fly overhead).
	var want_crouch := intent_down and is_on_floor() and dash_timer <= 0.0
	if want_crouch != crouching:
		crouching = want_crouch
		var shape := _body_col.shape as RectangleShape2D
		if crouching:
			shape.size = Vector2(36, 40)
			_body_col.position.y = 12
			_rig.scale.y = 0.7
			_rig.position.y = 10
		else:
			shape.size = Vector2(36, 64)
			_body_col.position.y = 0
			_rig.scale.y = 1.0
			_rig.position.y = 0
	if crouching:
		speed *= 0.4

	velocity.x = intent_move * speed
	if dash_timer > 0.0:
		dash_timer -= delta
		velocity.x = facing * dash_speed
		velocity.y = minf(velocity.y, 0.0)
	if intent_jump and is_on_floor() and not crouching:
		velocity.y = JUMP_VELOCITY
	if intent_attack and attack_cooldown <= 0.0:
		_start_attack()
	if intent_skill >= 0:
		_use_skill(intent_skill)

	if attack_window > 0.0:
		attack_window -= delta
		_check_melee_hits()
		if attack_window <= 0.0:
			_end_strike()

	if intent_move != 0.0 and dash_timer <= 0.0:
		facing = 1 if intent_move > 0.0 else -1
	elif enemy and is_instance_valid(enemy) and dash_timer <= 0.0:
		facing = 1 if enemy.global_position.x > global_position.x else -1
	_rig.scale.x = facing

	move_and_slide()

	if regen_rate > 0.0 and hp < max_hp:
		hp = minf(max_hp, hp + regen_rate * delta)
		stats_changed.emit()

	intent_jump = false
	intent_attack = false
	intent_skill = -1


func _gather_player_input() -> void:
	intent_move = Input.get_axis("move_left", "move_right")
	if Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("move_up"):
		intent_jump = true
	if Input.is_action_just_pressed("attack"):
		intent_attack = true
	intent_block = Input.is_action_pressed("block")
	intent_down = Input.is_action_pressed("move_down")
	if Input.is_action_just_pressed("skill1"):
		intent_skill = 0
	elif Input.is_action_just_pressed("skill2"):
		intent_skill = 1
	elif Input.is_action_just_pressed("skill3"):
		intent_skill = 2


func _start_attack() -> void:
	match weapon_type:
		"bow":
			attack_cooldown = 0.9
			_shoot_arrow(atk, false, weapon_special)
			_weapon_sprite.rotation = -0.4
			get_tree().create_timer(0.15).timeout.connect(_reset_weapon_pose)
		"spear":
			attack_cooldown = 0.8
			_begin_strike(0.2, 1.0, false, 0.0)
			_weapon_sprite.rotation = 0.25
		_:
			attack_cooldown = 0.55
			_begin_strike(0.16, 1.0, false, 0.0)
			_weapon_sprite.rotation = -0.8


func _begin_strike(window: float, mult: float, burn: bool, bonus_reach: float) -> void:
	attack_window = window
	_strike_mult = mult
	_strike_burn = burn
	_hit_targets.clear()
	var shape := _hitbox_shape.shape as RectangleShape2D
	shape.size = Vector2(reach + bonus_reach, 48)
	_hitbox_shape.position = Vector2((reach + bonus_reach) * 0.5 + 18.0, 0)
	_hitbox.monitoring = true


func _end_strike() -> void:
	_hitbox.monitoring = false
	_weapon_sprite.rotation = 0.0
	_strike_mult = 1.0
	_strike_burn = false
	var shape := _hitbox_shape.shape as RectangleShape2D
	shape.size = Vector2(reach, 48)
	_hitbox_shape.position = Vector2(reach * 0.5 + 18.0, 0)


func _reset_weapon_pose() -> void:
	if is_instance_valid(_weapon_sprite):
		_weapon_sprite.rotation = 0.0


func _check_melee_hits() -> void:
	for body in _hitbox.get_overlapping_bodies():
		if body is Character and body != self and not _hit_targets.has(body):
			_hit_targets.append(body)
			body.take_damage(atk * _strike_mult, self, true)
			if _strike_burn:
				body.burn_timer = 3.0
				body.burn_dps = 4.0


func _shoot_arrow(damage: float, pierce: bool, special: String, speed := 640.0) -> void:
	var arrow := PROJECTILE_SCENE.instantiate()
	arrow.direction = facing
	arrow.damage = damage
	arrow.shooter = self
	arrow.special = special
	arrow.pierce = pierce
	arrow.speed = speed
	get_parent().add_child(arrow)
	arrow.global_position = global_position + Vector2(facing * 40.0, -12.0)


# --- Skills (U / I / O) --------------------------------------------------

func _use_skill(index: int) -> void:
	if index < 0 or index >= skills.size():
		return
	var skill: Dictionary = skills[index]
	if skill["cd_left"] > 0.0:
		return
	match skill["id"]:
		"flame_slash":
			_begin_strike(0.2, 1.2, true, 40.0)
			_weapon_sprite.rotation = -1.1
			_spawn_flash(Color(1.0, 0.5, 0.15, 0.6), 70.0, Vector2(facing * 50.0, 0))
		"ice_shard":
			_shoot_arrow(atk * 0.9, false, "ice", 720.0)
			_spawn_flash(Color(0.5, 0.8, 1.0, 0.5), 40.0, Vector2(facing * 40.0, -12.0))
		"power_shot":
			_shoot_arrow(atk * 1.8, true, "power", 900.0)
			_spawn_flash(Color(1.0, 0.9, 0.4, 0.6), 45.0, Vector2(facing * 40.0, -12.0))
		"dash_strike":
			dash_timer = 0.18
			dash_speed = 900.0
			_begin_strike(0.24, 1.1, false, 20.0)
			_spawn_flash(Color(0.9, 0.9, 1.0, 0.4), 50.0, Vector2.ZERO)
		"regen_burst":
			hp = minf(max_hp, hp + max_hp * 0.2)
			_spawn_flash(Color(0.4, 1.0, 0.5, 0.6), 80.0, Vector2.ZERO)
			stats_changed.emit()
		"spike_burst":
			_spawn_flash(Color(1.0, 0.3, 0.3, 0.6), 130.0, Vector2.ZERO)
			if enemy and is_instance_valid(enemy) \
					and global_position.distance_to(enemy.global_position) < 150.0:
				enemy.take_damage(atk * 0.8 + 8.0, self, false)
		"iron_wall":
			iron_wall_timer = 4.0
			_spawn_flash(Color(0.75, 0.75, 0.8, 0.7), 70.0, Vector2.ZERO)
		"shadow_step":
			invuln_timer = 0.45
			dash_timer = 0.2
			dash_speed = 780.0
			modulate.a = 0.35
			get_tree().create_timer(0.45).timeout.connect(_end_shadow_step)
	skill["cd_left"] = skill["cooldown"]


func _end_shadow_step() -> void:
	if is_instance_valid(self) and hp > 0.0:
		modulate.a = 1.0


# Simple expanding-circle VFX so skills read clearly.
func _spawn_flash(color: Color, radius: float, offset: Vector2) -> void:
	var flash := Polygon2D.new()
	var points := PackedVector2Array()
	for i in range(20):
		var a := TAU * i / 20.0
		points.append(Vector2(cos(a), sin(a)) * radius)
	flash.polygon = points
	flash.color = color
	flash.scale = Vector2(0.3, 0.3)
	get_parent().add_child(flash)
	flash.global_position = global_position + offset
	var tween := flash.create_tween()
	tween.tween_property(flash, "scale", Vector2.ONE, 0.25)
	tween.parallel().tween_property(flash, "modulate:a", 0.0, 0.3)
	tween.tween_callback(flash.queue_free)


# --- Damage --------------------------------------------------------------

func take_damage(amount: float, source: Character, is_melee: bool) -> void:
	if hp <= 0.0 or invuln_timer > 0.0:
		return
	var dmg := amount
	# Blocking only works against attacks from the front.
	if blocking and source and sign(source.global_position.x - global_position.x) == facing:
		dmg *= 0.3
	if iron_wall_timer > 0.0:
		dmg *= 0.4
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
	_apply_direct_damage(amount)
	_flash_hit()


# Damage that skips block/defense/armor (thorns reflect, burn DOT).
func _apply_direct_damage(amount: float) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	stats_changed.emit()
	if hp <= 0.0:
		hp = 0.0
		_die()


func _flash_hit() -> void:
	modulate = Color(1, 0.5, 0.5, modulate.a)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, modulate.a), 0.2)


func _die() -> void:
	_hitbox.monitoring = false
	modulate.a = 1.0
	var tween := create_tween()
	tween.tween_property(_rig, "rotation", 0.5 * PI * facing, 0.5)
	tween.parallel().tween_property(self, "modulate:a", 0.4, 0.5)
	died.emit(self)
