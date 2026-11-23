package game

import "../assets"
import "../render"
import "core:math"

spawn_twink :: proc(w: ^World, x_col4, y_px: int) {
	w.twinks[w.twink_index] = Twink {
		x          = x_col4,
		y          = y_px,
		prev_x     = x_col4,
		prev_y     = y_px,
		prev_valid = true,
		state      = 9,
		dir        = int(assets.rand_next(&w.rng, 2)),
	}
	w.twink_index = (w.twink_index + 1) % MAX_TWINKS
}

update_twinks :: proc(w: ^World) {
	for &tw in w.twinks {
		if tw.state > 0 {
			tw.state -= 1
		}
	}
}

draw_twinks :: proc(
	r: ^render.GPU_Renderer,
	bank: ^Sprite_Bank,
	w: ^World,
	cam_off_x: f32 = 0,
	cam_off_y: f32 = 0,
	alpha: f32 = 1.0,
) {
	for tw in w.twinks {
		if tw.state <= 0 {
			continue
		}
		frame := 0
		switch tw.state {
		case 9, 1:
			frame = 0
		case 8, 2:
			frame = 1
		case 7, 3:
			frame = 2
		case 6, 4:
			frame = 3
		case 5:
			frame = 4
		}
		sx := f32(tw.x * 4) + cam_off_x
		sy := f32(tw.y) + cam_off_y
		if alpha < 0.9999 && tw.prev_valid {
			sx = math.round(math.lerp(f32(tw.prev_x * 4), f32(tw.x * 4), alpha) + cam_off_x)
			sy = math.round(math.lerp(f32(tw.prev_y), f32(tw.y), alpha) + cam_off_y)
		}
		draw_sprite_px(
			r,
			bank,
			SPR_TWINKS,
			sx,
			sy,
			tw.dir,
			frame,
		)
	}
}

spawn_score_tag :: proc(w: ^World, x_col4, y_px, tag: int) {
	for &st in w.score_tags {
		if st.state == 0 {
			dir := 0
			frame := tag
			if tag > 4 {
				dir = 1
				frame = tag - 5
			}
			st = Score_Tag {
				x          = x_col4,
				y          = y_px,
				prev_x     = x_col4,
				prev_y     = y_px,
				prev_valid = true,
				frame      = frame,
				state      = 17,
				dir        = dir,
			}
			break
		}
	}
}

update_score_tags :: proc(w: ^World) {
	for &st in w.score_tags {
		if st.state > 0 {
			st.y -= 2
			st.state -= 1
		}
	}
}

draw_score_tags :: proc(
	r: ^render.GPU_Renderer,
	bank: ^Sprite_Bank,
	w: ^World,
	cam_off_x: f32 = 0,
	cam_off_y: f32 = 0,
	alpha: f32 = 1.0,
) {
	for st in w.score_tags {
		if st.state > 0 {
			sx := f32(st.x * 4) + cam_off_x
			sy := f32(st.y) + cam_off_y
			if alpha < 0.9999 && st.prev_valid {
				sx = math.round(math.lerp(f32(st.prev_x * 4), f32(st.x * 4), alpha) + cam_off_x)
				sy = math.round(math.lerp(f32(st.prev_y), f32(st.y), alpha) + cam_off_y)
			}
			draw_sprite_px(
				r,
				bank,
				SPR_SCORETAGS,
				sx,
				sy,
				st.dir,
				st.frame,
			)
		}
	}
}

spawn_particles :: proc(w: ^World, x_px, y_px: int) {
	burst := &w.particles[w.particle_index]
	burst.state = 16
	burst.prev_valid = true
	for i in 0 ..< PIXELS_PER_PARTICLE {
		vx := int(assets.rand_next(&w.rng, 10)) - int(assets.rand_next(&w.rng, 10))
		vy := -(int(assets.rand_next(&w.rng, 7)) + 5)
		white := assets.rand_next(&w.rng, 2)
		color := u8(0x60) if white != 0 else u8(0x70)
		burst.pixels[i] = Particle_Pixel {
			x      = x_px,
			y      = y_px,
			prev_x = x_px,
			prev_y = y_px,
			vx     = vx,
			vy     = vy,
			color  = color,
		}
	}
	w.particle_index = (w.particle_index + 1) % MAX_PARTICLES
}

update_particles :: proc(w: ^World) {
	for &burst in w.particles {
		if burst.state <= 0 {
			continue
		}
		for &p in burst.pixels {
			p.y += p.vy
			p.vy += 1
			p.x += p.vx
		}
		burst.state -= 1
	}
}

draw_particles :: proc(
	r: ^render.GPU_Renderer,
	w: ^World,
	cam_off_x: f32 = 0,
	cam_off_y: f32 = 0,
	alpha: f32 = 1.0,
) {
	for burst in w.particles {
		if burst.state <= 0 {
			continue
		}
		for p in burst.pixels {
			px := f32(p.x) + cam_off_x
			py := f32(p.y) + cam_off_y
			if alpha < 0.9999 && burst.prev_valid {
				px = math.round(math.lerp(f32(p.prev_x), f32(p.x), alpha) + cam_off_x)
				py = math.round(math.lerp(f32(p.prev_y), f32(p.y), alpha) + cam_off_y)
			}
			if px >= 0 && px < VIEWPORT_W && py >= 0 && py < VIEWPORT_H {
				render.draw_solid_rect(&r.batch, px, py, 1, 1, p.color)
			}
		}
	}
}

spawn_snow :: proc(w: ^World, x_col4, y_px: int) {
	if w.snow[w.snow_index].x == -99 {
		w.snow[w.snow_index] = Snow_Particle {
			x          = x_col4,
			y          = y_px,
			prev_x     = x_col4,
			prev_y     = y_px,
			prev_valid = true,
			state      = 0,
		}
	}
	w.snow_index = (w.snow_index + 1) % MAX_SNOW
}

update_snow :: proc(w: ^World) {
	for &sn in w.snow {
		if sn.x >= 0 && sn.x < 80 && sn.y >= 0 && sn.y < VIEWPORT_H {
			sn.sub_x = u8(assets.rand_next(&w.rng, 4))
			if sn.state == 0 {
				sn.prev_sub_x = sn.sub_x
			}
			sn.visible = assets.rand_next(&w.rng, 2) == 0
		} else {
			sn.visible = false
		}
		sn.y += 1
		sn.state += 1
		if sn.state >= 16 {
			sn.x = -99
		}
	}
}

draw_snow :: proc(
	r: ^render.GPU_Renderer,
	w: ^World,
	cam_off_x: f32 = 0,
	cam_off_y: f32 = 0,
	alpha: f32 = 1.0,
) {
	for sn in w.snow {
		if sn.visible && sn.x >= 0 && sn.x < 80 && sn.y >= 0 && sn.y < VIEWPORT_H {
			color := u8(sn.state / 4 + 0x78)
			sx := f32(sn.x * 4 + int(sn.sub_x)) + cam_off_x
			sy := f32(sn.y) + cam_off_y
			if alpha < 0.9999 && sn.prev_valid {
				prev_px := f32(sn.prev_x * 4 + int(sn.prev_sub_x))
				cur_px := f32(sn.x * 4 + int(sn.sub_x))
				sx = math.round(math.lerp(prev_px, cur_px, alpha) + cam_off_x)
				sy = math.round(math.lerp(f32(sn.prev_y), f32(sn.y), alpha) + cam_off_y)
			}
			render.draw_solid_rect(
				&r.batch,
				sx,
				sy,
				1,
				1,
				color,
			)
		}
	}
}
