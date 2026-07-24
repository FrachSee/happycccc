class_name DrawAnalyzer
## Heuristic analysis of a drawing (Image) -> LoadoutData.
## No external AI: stroke density, dominant color and bounding-box
## aspect ratio decide the stats.

# Analyze a canvas image for the given equipment slot.
static func analyze(image: Image, slot: int) -> LoadoutData:
	var data := LoadoutData.new()
	data.slot = slot
	var used := image.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return _default_loadout(slot)

	var count := 0
	var sum_r := 0.0
	var sum_g := 0.0
	var sum_b := 0.0
	for y in range(used.position.y, used.end.y):
		for x in range(used.position.x, used.end.x):
			var c := image.get_pixel(x, y)
			if c.a > 0.1:
				count += 1
				sum_r += c.r
				sum_g += c.g
				sum_b += c.b
	if count == 0:
		return _default_loadout(slot)

	var density := float(count) / float(image.get_width() * image.get_height())
	var aspect := float(used.size.x) / float(maxi(used.size.y, 1))
	var avg := Color(sum_r / count, sum_g / count, sum_b / count)
	var brightness := (avg.r + avg.g + avg.b) / 3.0
	var tone := _classify_tone(avg, brightness)
	data.aspect = aspect
	data.main_color = avg

	match slot:
		LoadoutData.Slot.WEAPON:
			_build_weapon(data, density, aspect, tone)
		LoadoutData.Slot.ARMOR:
			_build_armor(data, density, aspect, tone, brightness)
		LoadoutData.Slot.ACCESSORY:
			_build_accessory(data, density, aspect, tone)
	return data


static func _classify_tone(avg: Color, brightness: float) -> String:
	if brightness < 0.30:
		return "dark"
	if avg.r > avg.g + 0.08 and avg.r > avg.b + 0.08:
		return "red"
	if avg.b > avg.r + 0.08 and avg.b > avg.g + 0.08:
		return "blue"
	if avg.g > avg.r + 0.08 and avg.g > avg.b + 0.08:
		return "green"
	return "neutral"


static func _build_weapon(data: LoadoutData, density: float, aspect: float, tone: String) -> void:
	var type_name := ""
	if aspect >= 1.8:
		# Long horizontal drawing -> spear: reach, lower damage.
		data.weapon_type = "spear"
		data.atk = 8.0 + density * 45.0
		data.reach = 135.0
		type_name = "长枪(远距)"
	elif density >= 0.13:
		# Dense drawing -> heavy sword: highest damage.
		data.weapon_type = "sword"
		data.atk = 13.0 + density * 55.0
		data.reach = 85.0
		type_name = "剑(近战)"
	else:
		# Sparse drawing -> bow: ranged projectile.
		data.weapon_type = "bow"
		data.atk = 10.0 + density * 50.0
		data.reach = 400.0
		type_name = "弓(远程)"

	var special_name := ""
	if tone == "red":
		data.special = "fire"
		data.atk *= 1.15
		special_name = " · 火焰"
	elif tone == "blue":
		data.special = "ice"
		special_name = " · 冰冻(减速)"
	data.summary = "%s 攻击 %d%s" % [type_name, int(data.atk), special_name]


static func _build_armor(data: LoadoutData, density: float, aspect: float, tone: String, brightness: float) -> void:
	data.armor_hp = 25.0 + density * 140.0
	data.defense = (1.0 - brightness) * 5.0 + density * 10.0
	# Light (sparse) armor -> speed bonus.
	data.spd = (0.18 - minf(density, 0.18)) * 120.0
	if aspect < 0.7:
		data.spd += 10.0 # tall & narrow -> dodgy

	var special_name := ""
	match tone:
		"red":
			data.special = "thorns"
			data.special_power = clampf(0.15 + density * 0.6, 0.15, 0.30)
			special_name = " · 荆棘%d%%" % int(data.special_power * 100)
		"green":
			data.special = "regen"
			data.special_power = minf(2.0 + density * 10.0, 5.0)
			special_name = " · 回复"
		"blue":
			data.special = "shield"
			special_name = " · 可格挡(K)"
		"dark":
			data.special = "heavy"
			data.armor_hp += 25.0
			data.defense += 2.0
			special_name = " · 重甲"
	data.summary = "护甲 %d 防御 %d%s" % [int(data.armor_hp), int(data.defense), special_name]


static func _build_accessory(data: LoadoutData, density: float, aspect: float, tone: String) -> void:
	var effect := ""
	match tone:
		"red":
			data.atk = 4.0 + density * 12.0
			effect = "+攻击 %d" % int(data.atk)
		"blue":
			data.armor_hp = 20.0
			effect = "+护甲 20"
		"green":
			data.special = "regen"
			data.special_power = minf(1.5 + density * 6.0, 3.0)
			data.hp_bonus = 10.0
			effect = "+回复/+生命"
		"dark":
			data.defense = 3.0
			effect = "+防御 3"
		_:
			data.spd = 10.0
			effect = "+速度"
	if aspect < 0.7:
		data.spd += 8.0
		effect += " +闪避"
	data.summary = "饰品 %s" % effect


static func _default_loadout(slot: int) -> LoadoutData:
	var data := LoadoutData.new()
	data.slot = slot
	match slot:
		LoadoutData.Slot.WEAPON:
			data.weapon_type = "sword"
			data.atk = 10.0
			data.reach = 85.0
			data.summary = "空白 -> 木剑 攻击 10"
		LoadoutData.Slot.ARMOR:
			data.armor_hp = 20.0
			data.defense = 1.0
			data.summary = "空白 -> 布衣 护甲 20"
		LoadoutData.Slot.ACCESSORY:
			data.summary = "空白饰品"
	return data
