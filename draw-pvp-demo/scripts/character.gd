class_name Character
extends CharacterBody2D
## Shared fighter logic for both the player and the AI opponent.
## Stats come from LoadoutData (analyzed drawings). Movement intents are
## written either from keyboard input (player) or by AIController.
## J = neutral attack, W+J = up special, S+J (ground) = down special.

signal stats_changed
signal died(who: Character)

const GRAVITY := 1800.0
const FAST_FALL_GRAVITY := 2200.0
const JUMP_VELOCITY := -650.0
const INPUT_BUFFER_MS := 150
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
var hitbox_height := 48.0
var thorns := 0.0
var regen_rate := 0.0
var can_block := false
var skills: Array = [] # [{id, name, cooldown, cd_left}]

var facing := 1
var blocking := false
var crouching := false
var attack_cooldown := 0.0
var special_cooldown := 0.0
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
var _weapon_base_rot := 0.0
var _up_pressed_at := -100000
var _down_pressed_at := -100000

# One-shot intents are consumed each physics frame.
var intent_move := 0.0
var intent_jump := false
var intent_attack := false
var intent_attack_dir := 0 # 0 neutral, 1 up special, 2 down special
var intent_block := false
var intent_down := false
var intent_skill := -1

var enemy: Character

var _rig: Node2D
var _body_poly: Polygon2D
var _armor_sprite: Sprite2D
var _weapon_sprite: Sprite2D
var _acc_sprite: Sprite2D
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
	_armor_sprite.modulate = Color(1, 1, 1, 0.75)
	_rig.add_child(_armor_sprite)

	_acc_sprite = Sprite2D.new()
	_acc_sprite.position = Vector2(-10, -32)
	_rig.add_child(_acc_sprite)

	_weapon_sprite = Sprite2D.new()
	_weapon_sprite.position = Vector2(30, -8)
	_rig.add_child(_weapon_sprite)

	_hitbox = Area2D.new()
	_hitbox.monitoring = false
	_hitbox_shape = CollisionShape2D.new()
	var hb_shape := RectangleShape2D.new()
	hb_shape.size = Vector2(reach, hitbox_height)
	_hitbox_shape.shape = hb_shape
	_hitbox.add_child(_hitbox_shape)
	_rig.add_child(_hitbox)


# Called by the arena after instancing; loadouts: {Slot -> LoadoutData}.
func setup(loadouts: Dictionary, p_is_player: bool, body_color: Color) -> void:
	is_player = p_is_player
	display_name = "玩家" if is_player else "AI 对手"

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
	# Melee hitbox loosely follows the drawn weapon's silhouette:
	# long flat drawings sweep thin, blobby drawings hit tall.
	hitbox_height = clampf(64.0 / maxf(weapon.aspect, 0.6), 26.0, 80.0)

	thorns = armor_data.special_power if armor_data.special == "thorns" else 0.0
	can_block = armor_data.special == "shield"
	regen_rate = 0.0
	if armor_data.special == "regen":
		regen_rate += armor_data.special_power
	if acc.special == "regen":
		regen_rate += acc.special_power

	skills = Skills.build(loadouts)

	# Armor drawing tints the body and overlays it semi-transparently.
	_body_poly.color = body_color.lerp(armor_data.main_color, 0.4)
	if armor_data.texture:
		_armor_sprite.texture = armor_data.texture
		var cover := 74.0 / maxf(float(armor_data.texture.get_width()), 1.0)
		_armor_sprite.scale = Vector2(cover, cover)

	# Weapon sprite IS the trimmed drawing silhouette, held in the hand.
	if weapon.texture:
		_weapon_sprite.texture = weapon.texture
		var longest := maxf(weapon.texture.get_width(), weapon.texture.get_height())
		var s := 74.0 / maxf(longest, 1.0)
		_weapon_sprite.scale = Vector2(s, s)
		if weapon.aspect >= 1.4:
			_weapon_base_rot = -0.9 # long weapon held diagonally
		elif weapon.aspect <= 0.7:
			_weapon_base_rot = 0.0 # tall drawing stays upright
		else:
			_weapon_base_rot = -0.35
		_weapon_sprite.rotation = _weapon_base_rot

	# Accessory drawing floats as a small charm near the shoulder.
	if acc.texture:
		_acc_sprite.texture = acc.texture
		var acc_longest := maxf(acc.texture.get_width(), acc.texture.get_height())
		var acc_s := 26.0 / maxf(acc_longest, 1.0)
		_acc_sprite.scale = Vector2(acc_s, acc_s)

	(_hitbox_shape.shape as RectangleShape2D).size = Vector2(reach, hitbox_height)
	_hitbox_shape.position = Vector2(reach * 0.5 + 18.0, 0)
	stats_changed.emit()


func _physics_process(delta: float) -> void:
	if hp <= 0.0:
		return
	if is_player:
		_gather_player_input()

	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	special_cooldown = maxf(0.0, special_cooldown - delta)
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
	if intent_attack:
		_start_attack(intent_attack_dir)
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
	intent_attack_dir = 0
	intent_skill = -1


func _gather_player_input() -> void:
	var now := Time.get_ticks_msec()
	intent_move = Input.get_axis("move_left", "move_right")
	if Input.is_action_just_pressed("move_up"):
		_up_pressed_at = now
	if Input.is_action_just_pressed("move_down"):
		_down_pressed_at = now
	if Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("move_up"):
		intent_jump = true
	intent_block = Input.is_action_pressed("block")
	intent_down = Input.is_action_pressed("move_down")
	if Input.is_action_just_pressed("attack"):
		intent_attack = true
		# Directional specials: held or buffered W/S within 150ms.
		if Input.is_action_pressed("move_up") or now - _up_pressed_at <= INPUT_BUFFER_MS:
			intent_attack_dir = 1
		elif Input.is_action_pressed("move_down") or now - _down_pressed_at <= INPUT_BUFFER_MS:
			intent_attack_dir = 2
	if Input.is_action_just_pressed("skill1"):
		intent_skill = 0
	elif Input.is_action_just_pressed("skill2"):
		intent_skill = 1
	elif Input.is_action_just_pressed("skill3"):
		intent_skill = 2


# --- Attacks (J / W+J / S+J) ---------------------------------------------

func _start_attack(dir: int) -> void:
	if dir == 1 and special_cooldown <= 0.0:
		_up_special()
		return
	if dir == 2 and special_cooldown <= 0.0 and is_on_floor():
		_down_special()
		return
	if attack_cooldown > 0.0:
		return
	match weapon_type:
		"bow":
			attack_cooldown = 0.9
			_shoot_arrow(atk, false, weapon_special)
			_weapon_sprite.rotation = _weapon_base_rot - 0.4
			get_tree().create_timer(0.15).timeout.connect(_reset_weapon_pose)
		"spear":
			attack_cooldown = 0.8
			_begin_strike(0.2, 1.0, false, 0.0)
			_weapon_sprite.rotation = _weapon_base_rot + 0.25
			VFX.slash_arc(get_parent(), global_position, reach * 0.7,
				Color(1, 1, 1, 0.4), facing, -0.3, 0.3)
		_:
			attack_cooldown = 0.55
			_begin_strike(0.16, 1.0, false, 0.0)
			_weapon_sprite.rotation = _weapon_base_rot - 0.8
			VFX.slash_arc(get_parent(), global_position, reach * 0.8,
				Color(1, 1, 1, 0.45), facing)


func _up_special() -> void:
	special_cooldown = 2.4
	match weapon_type:
		"bow": # 箭雨: arrows rain down over the enemy.
			VFX.popup(get_parent(), global_position, "箭雨!", Color(0.9, 0.85, 0.4))
			var base_x := global_position.x + facing * 260.0
			if enemy and is_instance_valid(enemy):
				base_x = enemy.global_position.x
			for i in range(5):
				_spawn_projectile(atk * 0.5, false, "",
					Vector2(0, 640), Vector2(base_x + (i - 2) * 46.0, 120.0))
			VFX.burst(get_parent(), global_position + Vector2(facing * 30, -30),
				Color(0.95, 0.85, 0.4), 12, 160.0)
		_: # 升龙斩 / 挑空刺: rising slash.
			var skill_name := "升龙斩!" if weapon_type == "sword" else "挑空刺!"
			VFX.popup(get_parent(), global_position, skill_name, Color(0.8, 0.9, 1.0))
			velocity.y = -680.0
			_begin_strike(0.3, 1.3, weapon_special == "fire", 10.0, -20.0)
			_weapon_sprite.rotation = _weapon_base_rot - 1.4
			VFX.slash_arc(get_parent(), global_position, reach * 0.9,
				Color(0.75, 0.9, 1.0, 0.7), facing, -2.6, -0.6)
			VFX.burst(get_parent(), global_position, Color(0.8, 0.9, 1.0), 14, 240.0)


func _down_special() -> void:
	special_cooldown = 2.6
	match weapon_type:
		"bow": # 陷阱地雷: proximity mine at the feet.
			VFX.popup(get_parent(), global_position, "陷阱地雷!", Color(0.95, 0.6, 0.3))
			_spawn_mine()
		"spear": # 横扫千军: wide low sweep.
			VFX.popup(get_parent(), global_position, "横扫千军!", Color(1.0, 0.85, 0.6))
			_begin_strike(0.25, 0.95, false, 40.0, 16.0)
			_weapon_sprite.rotation = _weapon_base_rot + 0.5
			VFX.slash_arc(get_parent(), global_position + Vector2(0, 16),
				reach * 1.0, Color(1.0, 0.9, 0.6, 0.6), facing, -0.2, 0.5)
		_: # 地裂波: shockwave along the ground.
			VFX.popup(get_parent(), global_position, "地裂波!", Color(1.0, 0.6, 0.3))
			_spawn_projectile(atk * 0.9, false, "wave",
				Vector2(facing * 520.0, 0), global_position + Vector2(facing * 30.0, 22.0))
			VFX.burst(get_parent(), global_position + Vector2(facing * 30, 24),
				Color(1.0, 0.55, 0.25), 14, 200.0, 0.4, Vector2(facing, -0.3), 60.0)
			VFX.shake(self, 5.0)


func _begin_strike(window: float, mult: float, burn: bool, bonus_reach: float, offset_y := 0.0) -> void:
	attack_window = window
	_strike_mult = mult
	_strike_burn = burn
	_hit_targets.clear()
	var shape := _hitbox_shape.shape as RectangleShape2D
	shape.size = Vector2(reach + bonus_reach, hitbox_height + absf(offset_y))
	_hitbox_shape.position = Vector2((reach + bonus_reach) * 0.5 + 18.0, offset_y)
	_hitbox.monitoring = true


func _end_strike() -> void:
	_hitbox.monitoring = false
	_weapon_sprite.rotation = _weapon_base_rot
	_strike_mult = 1.0
	_strike_burn = false
	var shape := _hitbox_shape.shape as RectangleShape2D
	shape.size = Vector2(reach, hitbox_height)
	_hitbox_shape.position = Vector2(reach * 0.5 + 18.0, 0)


func _reset_weapon_pose() -> void:
	if is_instance_valid(_weapon_sprite):
		_weapon_sprite.rotation = _weapon_base_rot


func _check_melee_hits() -> void:
	for body in _hitbox.get_overlapping_bodies():
		if body is Character and body != self and not _hit_targets.has(body):
			_hit_targets.append(body)
			body.take_damage(atk * _strike_mult, self, true)
			if _strike_burn:
				body.burn_timer = 3.0
				body.burn_dps = 4.0


func _spawn_projectile(damage: float, pierce: bool, special: String,
		vel: Vector2, spawn_pos: Vector2) -> void:
	var arrow := PROJECTILE_SCENE.instantiate()
	arrow.damage = damage
	arrow.shooter = self
	arrow.special = special
	arrow.pierce = pierce
	arrow.velocity = vel
	get_parent().add_child(arrow)
	arrow.global_position = spawn_pos


func _shoot_arrow(damage: float, pierce: bool, special: String, speed := 640.0) -> void:
	_spawn_projectile(damage, pierce, special, Vector2(facing * speed, 0),
		global_position + Vector2(facing * 40.0, -12.0))


func _spawn_mine() -> void:
	var mine := Area2D.new()
	mine.monitoring = false
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 55.0
	col.shape = shape
	mine.add_child(col)
	var visual := Polygon2D.new()
	var points := PackedVector2Array()
	for i in range(10):
		var a := TAU * i / 10.0
		points.append(Vector2(cos(a), sin(a)) * 10.0)
	visual.polygon = points
	visual.color = Color(0.9, 0.35, 0.2)
	mine.add_child(visual)
	var pulse := visual.create_tween().set_loops()
	pulse.tween_property(visual, "scale", Vector2(1.4, 1.4), 0.35)
	pulse.tween_property(visual, "scale", Vector2(0.8, 0.8), 0.35)

	var parent := get_parent()
	parent.add_child(mine)
	mine.global_position = global_position + Vector2(facing * 34.0, 22.0)
	mine.body_entered.connect(
		func(body: Node) -> void:
			if body is Character and body != self:
				body.take_damage(atk * 1.4, self, false)
				VFX.burst(parent, mine.global_position, Color(1.0, 0.5, 0.2), 24, 320.0)
				VFX.shake(self, 9.0)
				mine.queue_free())
	# Short arm delay so it cannot detonate instantly on the enemy's face.
	get_tree().create_timer(0.5).timeout.connect(
		func() -> void:
			if is_instance_valid(mine):
				mine.monitoring = true)
	get_tree().create_timer(8.0).timeout.connect(
		func() -> void:
			if is_instance_valid(mine):
				mine.queue_free())


# --- Skills (U / I / O) --------------------------------------------------

func _use_skill(index: int) -> void:
	if index < 0 or index >= skills.size():
		return
	var skill: Dictionary = skills[index]
	if skill["cd_left"] > 0.0:
		return
	var arena := get_parent()
	match skill["id"]:
		"flame_slash":
			_begin_strike(0.2, 1.2, true, 40.0)
			_weapon_sprite.rotation = _weapon_base_rot - 1.1
			VFX.slash_arc(arena, global_position, reach * 1.0,
				Color(1.0, 0.5, 0.15, 0.8), facing)
			VFX.burst(arena, global_position + Vector2(facing * 50, 0),
				Color(1.0, 0.45, 0.1), 20, 260.0, 0.5, Vector2(facing, -0.5), 70.0)
			VFX.aura(self, Color(1.0, 0.5, 0.15), 0.8)
		"ice_shard":
			_shoot_arrow(atk * 0.9, false, "ice", 720.0)
			VFX.burst(arena, global_position + Vector2(facing * 40, -12),
				Color(0.55, 0.85, 1.0), 14, 200.0, 0.45, Vector2(facing, 0), 40.0)
		"power_shot":
			_shoot_arrow(atk * 1.8, true, "power", 900.0)
			VFX.burst(arena, global_position + Vector2(facing * 40, -12),
				Color(1.0, 0.9, 0.4), 18, 260.0, 0.4, Vector2(facing, 0), 30.0)
			VFX.shake(self, 4.0)
		"dash_strike":
			dash_timer = 0.18
			dash_speed = 900.0
			_begin_strike(0.24, 1.1, false, 20.0)
			VFX.slash_arc(arena, global_position, reach * 0.9,
				Color(0.9, 0.9, 1.0, 0.6), facing, -0.6, 0.6)
			VFX.burst(arena, global_position, Color(0.9, 0.9, 1.0), 12, 180.0,
				0.35, Vector2(-facing, 0), 40.0)
		"regen_burst":
			hp = minf(max_hp, hp + max_hp * 0.2)
			VFX.burst(arena, global_position, Color(0.4, 1.0, 0.5), 20, 180.0,
				0.7, Vector2.UP, 60.0)
			VFX.aura(self, Color(0.4, 1.0, 0.5), 1.0)
			stats_changed.emit()
		"spike_burst":
			VFX.burst(arena, global_position, Color(1.0, 0.3, 0.3), 26, 340.0, 0.5)
			VFX.shake(self, 7.0)
			if enemy and is_instance_valid(enemy) \
					and global_position.distance_to(enemy.global_position) < 150.0:
				enemy.take_damage(atk * 0.8 + 8.0, self, false)
		"iron_wall":
			iron_wall_timer = 4.0
			VFX.aura(self, Color(0.75, 0.75, 0.85), 4.0, 50.0)
			VFX.burst(arena, global_position, Color(0.8, 0.8, 0.9), 14, 140.0)
		"shadow_step":
			invuln_timer = 0.45
			dash_timer = 0.2
			dash_speed = 780.0
			modulate.a = 0.35
			VFX.burst(arena, global_position, Color(0.6, 0.4, 0.9), 16, 200.0,
				0.4, Vector2(-facing, 0), 50.0)
			VFX.aura(self, Color(0.6, 0.4, 0.9), 0.5)
			get_tree().create_timer(0.45).timeout.connect(_end_shadow_step)
	VFX.popup(arena, global_position, skill["name"] + "!", Color(1, 1, 1))
	skill["cd_left"] = skill["cooldown"]


func _end_shadow_step() -> void:
	if is_instance_valid(self) and hp > 0.0:
		modulate.a = 1.0


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
	VFX.hit_flash(self)
	VFX.burst(get_parent(), global_position + Vector2(0, -10),
		Color(1.0, 0.85, 0.7), 8, 160.0, 0.3)
	if amount >= 14.0:
		VFX.shake(self, minf(10.0, amount * 0.4))
	stats_changed.emit()
	if hp <= 0.0:
		hp = 0.0
		_die()


func take_thorns(amount: float) -> void:
	_apply_direct_damage(amount)
	VFX.hit_flash(self)


# Damage that skips block/defense/armor (thorns reflect, burn DOT).
func _apply_direct_damage(amount: float) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	stats_changed.emit()
	if hp <= 0.0:
		hp = 0.0
		_die()


func _die() -> void:
	_hitbox.monitoring = false
	modulate.a = 1.0
	VFX.shake(self, 8.0, 0.4)
	VFX.burst(get_parent(), global_position, _body_poly.color, 22, 260.0, 0.6)
	var tween := create_tween()
	tween.tween_property(_rig, "rotation", 0.5 * PI * facing, 0.5)
	tween.parallel().tween_property(self, "modulate:a", 0.4, 0.5)
	died.emit(self)
