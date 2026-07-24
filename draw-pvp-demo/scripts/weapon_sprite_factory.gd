class_name WeaponSpriteFactory
## Turns a raw drawing into a unique gear sprite: trims transparent margins
## so the texture IS the drawn silhouette, then runs the "AI render" pass
## (palette normalize + glow). The result is attached to the fighter, so
## every drawing produces a visibly different weapon.

const MARGIN := 6 # room for the glow halo around the silhouette


static func create(src: Image) -> ImageTexture:
	var used := src.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return null
	var img := Image.create(
		used.size.x + MARGIN * 2, used.size.y + MARGIN * 2, false, Image.FORMAT_RGBA8)
	img.blit_rect(src, used, Vector2i(MARGIN, MARGIN))
	return ImageTexture.create_from_image(RenderEffect.stylize(img))


# Armor stays full-canvas (used as a body overlay); weapon and accessory
# are trimmed to their silhouettes.
static func texture_for_slot(img: Image, slot: int) -> Texture2D:
	if img.get_used_rect().size.x <= 0:
		return null
	if slot == LoadoutData.Slot.ARMOR:
		return RenderEffect.render(img)
	return create(img)
