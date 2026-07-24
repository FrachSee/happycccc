class_name Skills
## Maps analyzed drawings to three active skills (keys U / I / O).
## Each skill is a Dictionary: {id, name, cooldown, cd_left}.

const KEY_LABELS := ["U", "I", "O"]

const DEFS := {
	"flame_slash": { "name": "火焰斩", "cooldown": 6.0 },
	"ice_shard": { "name": "冰锥", "cooldown": 5.0 },
	"power_shot": { "name": "强力射击", "cooldown": 7.0 },
	"dash_strike": { "name": "突进斩", "cooldown": 6.0 },
	"regen_burst": { "name": "回复爆发", "cooldown": 10.0 },
	"spike_burst": { "name": "荆棘爆发", "cooldown": 8.0 },
	"iron_wall": { "name": "铁壁", "cooldown": 12.0 },
	"shadow_step": { "name": "影步", "cooldown": 7.0 },
}


static func build(loadouts: Dictionary) -> Array:
	return [
		_make(_weapon_skill(loadouts[LoadoutData.Slot.WEAPON])),
		_make(_armor_skill(loadouts[LoadoutData.Slot.ARMOR])),
		_make(_accessory_skill(loadouts[LoadoutData.Slot.ACCESSORY])),
	]


static func _make(id: String) -> Dictionary:
	return {
		"id": id,
		"name": DEFS[id]["name"],
		"cooldown": DEFS[id]["cooldown"],
		"cd_left": 0.0,
	}


# Skill 1 (U): from the weapon drawing.
static func _weapon_skill(w: LoadoutData) -> String:
	if w.special == "fire":
		return "flame_slash"
	if w.special == "ice":
		return "ice_shard"
	if w.weapon_type == "bow":
		return "power_shot"
	return "dash_strike" # sword / spear


# Skill 2 (I): from the armor drawing.
static func _armor_skill(a: LoadoutData) -> String:
	match a.special:
		"regen":
			return "regen_burst"
		"thorns":
			return "spike_burst"
		"shield", "heavy":
			return "iron_wall"
	return "shadow_step" # light armor


# Skill 3 (O): from the accessory drawing.
static func _accessory_skill(acc: LoadoutData) -> String:
	if acc.special == "regen":
		return "regen_burst"
	if acc.atk > 0.0:
		return "flame_slash"
	if acc.armor_hp > 0.0:
		return "ice_shard"
	if acc.defense > 0.0:
		return "iron_wall"
	return "shadow_step" # speed accessory
