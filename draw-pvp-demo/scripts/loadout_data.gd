class_name LoadoutData
extends Resource
## Stats derived from one drawing (weapon / armor / accessory slot).

enum Slot { WEAPON, ARMOR, ACCESSORY }

var slot: int = Slot.WEAPON
var weapon_type: String = "sword" # sword / bow / spear
var atk: float = 0.0
var defense: float = 0.0
var spd: float = 0.0 # movement speed bonus (px/s)
var hp_bonus: float = 0.0
var armor_hp: float = 0.0 # armor bar that absorbs damage first
var reach: float = 85.0 # melee hitbox length
var special: String = "" # fire / ice / thorns / regen / shield / ""
var special_power: float = 0.0
var texture: Texture2D # "AI rendered" version of the drawing
var summary: String = ""
