class_name RenderEffect
## Fake "AI render" pass: normalize the drawing to a fixed palette and
## add a soft glow halo, so the raw doodle feels like finished gear art.

const PALETTE: Array[Color] = [
	Color(0.88, 0.24, 0.24), # red
	Color(0.95, 0.55, 0.18), # orange
	Color(0.95, 0.85, 0.32), # yellow
	Color(0.30, 0.80, 0.38), # green
	Color(0.28, 0.55, 0.95), # blue
	Color(0.62, 0.38, 0.90), # purple
	Color(0.16, 0.16, 0.22), # dark
	Color(0.95, 0.95, 0.92), # white
]

const GLOW_RADIUS := 2


static func render(src: Image) -> ImageTexture:
	return ImageTexture.create_from_image(stylize(src))


# Quantize + glow, returning the processed Image (same size as src).
static func stylize(src: Image) -> Image:
	var w := src.get_width()
	var h := src.get_height()
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var used := src.get_used_rect()

	# Pass 1: palette-normalize painted pixels.
	for y in range(used.position.y, used.end.y):
		for x in range(used.position.x, used.end.x):
			var c := src.get_pixel(x, y)
			if c.a > 0.1:
				out.set_pixel(x, y, _nearest_palette(c))

	# Pass 2: glow halo around painted pixels.
	for y in range(used.position.y, used.end.y):
		for x in range(used.position.x, used.end.x):
			var c := out.get_pixel(x, y)
			if c.a < 0.9:
				continue
			for dy in range(-GLOW_RADIUS, GLOW_RADIUS + 1):
				for dx in range(-GLOW_RADIUS, GLOW_RADIUS + 1):
					var px := x + dx
					var py := y + dy
					if px < 0 or py < 0 or px >= w or py >= h:
						continue
					if out.get_pixel(px, py).a == 0.0:
						var glow := c.lightened(0.35)
						glow.a = 0.35
						out.set_pixel(px, py, glow)
	return out


static func _nearest_palette(c: Color) -> Color:
	var best := PALETTE[0]
	var best_dist := 999.0
	for p in PALETTE:
		var d := absf(c.r - p.r) + absf(c.g - p.g) + absf(c.b - p.b)
		if d < best_dist:
			best_dist = d
			best = p
	return best
