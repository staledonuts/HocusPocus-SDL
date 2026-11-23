package ui

import "../assets"
import "../render"

NUM_STARS :: 75

Star :: struct {
	angle:        int,
	moved:        int,
	speed:        int,
	brightness:   int,
	delta_bright: int,
}

Starfield :: struct {
	stars:  [NUM_STARS]Star,
	sincos: [360]assets.Sin_Cos_Entry,
	rng:    assets.Rand_Table,
	loaded: bool,
}

init_starfield :: proc(sf: ^Starfield, dat: ^assets.Dat_File) -> bool {
	if !assets.load_sincos_table(&sf.sincos, dat) {
		return false
	}
	_ = assets.load_rand_table(&sf.rng, dat)
	for i in 0 ..< NUM_STARS {
		respawn_star(sf, &sf.stars[i])
	}
	sf.loaded = true
	return true
}

@(private)
star_pos :: proc(sf: ^Starfield, s: Star) -> (x, y: int) {
	sc := sf.sincos[s.angle % 360]
	x = int(f32(s.moved) * f32(sc.sin_val)) + 160
	y = int(f32(s.moved) * f32(sc.cos_val)) + 112
	return x, y
}

@(private)
respawn_star :: proc(sf: ^Starfield, s: ^Star) {
	for _ in 0 ..< 16 {
		s.angle = int(assets.rand_next(&sf.rng, 360))
		s.moved = int(assets.rand_next(&sf.rng, 160))
		x, y := star_pos(sf, s^)
		if x >= 0 && x < render.SCREEN_WIDTH && y >= 0 && y < render.SCREEN_HEIGHT {
			break
		}
	}
	s.speed = int(assets.rand_next(&sf.rng, 5)) + 1
	s.brightness = 0
	s.delta_bright = int(assets.rand_next(&sf.rng, 5)) + 1
}

update_starfield :: proc(sf: ^Starfield) {
	if !sf.loaded do return
	for &s in sf.stars {
		s.moved += s.speed
		s.brightness = min(s.brightness + s.delta_bright, 127)
		x, y := star_pos(sf, s)
		if x < 0 || x >= render.SCREEN_WIDTH || y < 0 || y >= render.SCREEN_HEIGHT {
			respawn_star(sf, &s)
		}
	}
}

draw_starfield :: proc(r: ^render.GPU_Renderer, sf: ^Starfield) {
	if !sf.loaded do return
	for s in sf.stars {
		x, y := star_pos(sf, s)
		if x >= 0 && x < render.SCREEN_WIDTH && y >= 0 && y < render.SCREEN_HEIGHT {
			color := u8((s.brightness >> 3) + 0xF0)
			render.draw_solid_rect(&r.batch, f32(x), f32(y), 1, 1, color)
		}
	}
}
