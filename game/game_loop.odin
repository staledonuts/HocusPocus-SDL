package game

import "../assets"
import "../render"
import "core:math"

world_step :: proc(w: ^World, inp: ^Input_State, sprites: ^Sprite_Bank, demo: ^Demo_Player = nil) {
	if w.status != .Playing {
		return
	}
	world_capture_prev_state(w)
	w.tick_count += 1

	update_camera(w)

	if w.teleport_counter == 0 {
		check_tiles(w, inp, sprites)
	}

	if w.level_flash_red_countdown > 0 {
		w.level_flash_red_countdown -= 1
	}

	if w.hud_level_num_flash > 0 {
		w.hud_level_num_flash += 1
		if w.hud_level_num_flash > 20 {
			w.hud_level_num_flash = 1
		}
	}

	w.player_health = clamp(w.player_health, 0, 100)

	if w.player_health <= 0 && w.player_death_countdown == 0 {
		w.player_death_countdown = 90
		w.hide_countdown = 30000
		init_input_state(inp)
	}
	if w.player_death_countdown > 0 {
		w.player_death_countdown -= 1
		if (assets.rand_next(&w.rng, 4) == 0 && w.player_death_countdown > 25) ||
		   w.player_death_countdown == 89 {
			for _ in 0 ..< 2 {
				px :=
					(w.player_screen_x << 2) +
					int(assets.rand_next(&w.rng, 10)) +
					12 -
					int(assets.rand_next(&w.rng, 10))
				py :=
					w.player_screen_y +
					int(assets.rand_next(&w.rng, 10)) +
					16 -
					int(assets.rand_next(&w.rng, 10))
				spawn_particles(w, px, py)
				tx :=
					w.player_screen_x +
					int(assets.rand_next(&w.rng, 3)) -
					int(assets.rand_next(&w.rng, 3))
				ty :=
					w.player_screen_y +
					int(assets.rand_next(&w.rng, 12)) -
					int(assets.rand_next(&w.rng, 12))
				spawn_twink(w, tx, ty)
			}
			world_play_sound(w, SFX_EXPLODE)
		}
	}

	if w.level.crystals_total > 0 &&
	   w.crystals_collected >= w.level.crystals_total &&
	   w.level_done_countdown == 0 {
		w.level_done_countdown = 90
		w.hide_countdown = 30000
		init_input_state(inp)
		kill_active_enemies(w)
	}
	if w.level_done_countdown > 0 {
		w.level_done_countdown -= 1
		if assets.rand_next(&w.rng, 7) == 0 && w.level_done_countdown > 25 {
			for _ in 0 ..< 2 {
				tx :=
					w.player_screen_x +
					int(assets.rand_next(&w.rng, 3)) -
					int(assets.rand_next(&w.rng, 3))
				ty :=
					w.player_screen_y +
					int(assets.rand_next(&w.rng, 12)) -
					int(assets.rand_next(&w.rng, 12))
				spawn_twink(w, tx, ty)
			}
			world_play_sound(w, SFX_YAHOO)
		}
	}

	if w.hide_countdown == 0 {
		if w.super_jump_counter > 0 {
			tx := w.player_screen_x + int(assets.rand_next(&w.rng, 7)) - 2
			ty := w.player_screen_y + int(assets.rand_next(&w.rng, 10)) + 20
			spawn_twink(w, tx, ty)
			if !w.super_jump {
				w.super_jump_counter -= 1
			}
		}
		if w.powershots_left > 0 {
			w.tick5 -= 1
			if w.tick5 <= 0 {
				w.tick5 = 5
				w.tick1 = 0 if w.tick1 != 0 else 1
			}
		}
	} else {
		w.hide_countdown -= 1
		if w.hide_countdown == 0 {
			world_play_sound(w, SFX_TELEPORT)
		}
	}

	check_enemy_hits_player_shot(w)
	check_enemy_shot_hits_player(w)
	check_enemy_hits_player(w)
	update_actor_spawns(w, sprites)
	update_enemy_shots(w)
	update_actors(w, sprites)
	remove_hidden_actors(w)

	update_particles(w)
	update_score_tags(w)
	update_twinks(w)
	update_snow(w)

	if w.tile_tick {
		update_world_tiles(w)
	}
	w.tile_tick = !w.tile_tick

	if demo != nil && demo.active {
		_ = demo_next_input(demo, inp)
	}

	w.player_firing = !inp.fire_up
	w.player_aiming_up = !inp.use_up

	update_player_shots(w, inp, sprites)
	update_player_movement(w, inp, sprites)

	if w.player_death_countdown == 1 {
		w.status = .Died
	}
	if w.level_done_countdown == 1 {
		w.status = .Won
	}
}

world_render :: proc(
	r: ^render.GPU_Renderer,
	w: ^World,
	gfx: ^Level_Graphics,
	sprites: ^Sprite_Bank,
	alpha: f32 = 1.0,
) {
	t := clamp(alpha, 0.0, 1.0)
	cur_cam_x_px := f32(w.cam_x_t8 * 8)
	cur_cam_y_px := f32(w.cam_y * 16)

	cam_x_px := cur_cam_x_px
	cam_y_px := cur_cam_y_px
	if t < 0.9999 && abs(w.cam_x_t8 - w.prev_cam_x_t8) <= 4 && abs(w.cam_y - w.prev_cam_y) <= 3 {
		cam_x_px = math.round(math.lerp(f32(w.prev_cam_x_t8 * 8), cur_cam_x_px, t))
		cam_y_px = math.round(math.lerp(f32(w.prev_cam_y * 16), cur_cam_y_px, t))
	}
	cam_off_x := cur_cam_x_px - cam_x_px
	cam_off_y := cur_cam_y_px - cam_y_px

	render.begin_scene(r)

	if w.level_flash_red_countdown > 0 {
		render.batch_set_scissor(&r.batch, 0, 0, VIEWPORT_W, VIEWPORT_H)
		render.draw_solid_rect(
			&r.batch,
			0,
			0,
			VIEWPORT_W,
			VIEWPORT_H,
			u8(0x77 - w.level_flash_red_countdown),
		)
		render.batch_reset_scissor(&r.batch)
	} else {
		draw_level_viewport_px(r, &w.level, gfx, cam_x_px, cam_y_px)
	}

	render.batch_set_scissor(&r.batch, 0, 0, VIEWPORT_W, VIEWPORT_H)
	draw_player(r, sprites, w, cam_x_px, cam_y_px, t)
	draw_enemy_shots(r, sprites, w, cam_x_px, cam_y_px, t)
	draw_actors(r, sprites, w, cam_x_px, cam_y_px, t)
	draw_player_shots(r, sprites, w, cam_off_y, t)
	draw_particles(r, w, cam_off_x, cam_off_y, t)
	draw_score_tags(r, sprites, w, cam_off_x, cam_off_y, t)
	draw_twinks(r, sprites, w, cam_off_x, cam_off_y, t)
	draw_snow(r, w, cam_off_x, cam_off_y, t)
	render.batch_reset_scissor(&r.batch)

	draw_hud(r, gfx, world_get_hud(w))
}
