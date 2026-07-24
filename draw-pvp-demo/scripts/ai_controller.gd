class_name AIController
extends Node
## Simple state machine for the AI opponent: approach -> attack -> retreat.

var me: Character
var target: Character

var state := "approach"
var _state_timer := 0.0
var _block_timer := 0.0
var _retreat_cooldown := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if me == null:
		me = get_parent() as Character


func _physics_process(delta: float) -> void:
	if me == null or target == null:
		return
	if me.hp <= 0.0 or target.hp <= 0.0:
		me.intent_move = 0.0
		me.intent_block = false
		return

	_state_timer -= delta
	_block_timer -= delta
	_retreat_cooldown -= delta
	var dx := target.global_position.x - me.global_position.x
	var dist := absf(dx)
	var dir := 1.0 if dx > 0.0 else -1.0

	var desired := 62.0
	match me.weapon_type:
		"spear":
			desired = 105.0
		"bow":
			desired = 330.0

	# Retreat when badly hurt, but re-engage afterwards (cooldown prevents
	# cowering at the wall forever).
	if me.hp < me.max_hp * 0.3 and state != "retreat" and _retreat_cooldown <= 0.0:
		state = "retreat"
		_state_timer = _rng.randf_range(1.0, 1.8)
		_retreat_cooldown = 6.0

	match state:
		"approach":
			me.intent_move = dir if dist > desired else 0.0
			if dist <= desired:
				state = "attack"
		"attack":
			if dist > desired * 1.35:
				state = "approach"
			else:
				me.intent_move = 0.0
				if me.attack_cooldown <= 0.0 and _rng.randf() < 0.35:
					me.intent_attack = true
					# Occasionally use a directional special (W+J / S+J).
					if me.special_cooldown <= 0.0:
						var roll := _rng.randf()
						if roll < 0.25:
							me.intent_attack_dir = 1
						elif roll < 0.5 and me.is_on_floor():
							me.intent_attack_dir = 2
		"retreat":
			me.intent_move = -dir
			if _rng.randf() < 0.02:
				me.intent_jump = true
			if _state_timer <= 0.0:
				state = "approach"

	# Try to block incoming melee swings if the armor allows it.
	if me.can_block and target.attack_window > 0.0 and dist < 150.0:
		_block_timer = 0.4
	me.intent_block = _block_timer > 0.0

	# Hop occasionally to dodge arrows.
	if target.weapon_type == "bow" and _rng.randf() < 0.015:
		me.intent_jump = true

	_try_skills(dist)


# Fire a ready skill when its situational condition fits.
func _try_skills(dist: float) -> void:
	for i in range(me.skills.size()):
		var skill: Dictionary = me.skills[i]
		if skill["cd_left"] > 0.0:
			continue
		var use := false
		match skill["id"]:
			"regen_burst":
				use = me.hp < me.max_hp * 0.55
			"iron_wall":
				use = dist < 170.0 and _rng.randf() < 0.03
			"spike_burst":
				use = dist < 130.0 and _rng.randf() < 0.2
			"shadow_step":
				use = me.hp < me.max_hp * 0.4 and dist < 140.0
			"dash_strike":
				use = dist > 120.0 and dist < 280.0 and _rng.randf() < 0.1
			"flame_slash":
				use = dist < me.reach + 60.0 and _rng.randf() < 0.2
			"ice_shard", "power_shot":
				use = dist < 520.0 and _rng.randf() < 0.04
		if use:
			me.intent_skill = i
			break
