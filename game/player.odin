package game

import "../assets"
import "../render"
import "core:math"

@(private)
tile_main_safe :: proc(lvl: ^Level_Data, ti: int) -> u8 {
	if ti < 0 || ti >= MAP_TILES {
		return 0
	}
	return lvl.map_main[ti]
}

@(private)
destroy_shootable_tile :: proc(w: ^World, s: ^Player_Shot, ti, twink_x, twink_y: int) {
	w.level.map_main[ti] = EMPTY_TILE
	spawn_twink(w, twink_x, twink_y)
	s.x = -99
	w.player_shots_active -= 1
}

@(private)
advance_player_walk_frame :: proc(w: ^World, pinfo: assets.Sprite_Info) {
	w.player_walking = true
	w.player_frame += 1
	if w.player_frame > int(pinfo.walk_end) {
		w.player_frame = int(pinfo.walk_start)
	}
}

update_player_shots :: proc(w: ^World, inp: ^Input_State, sprites: ^Sprite_Bank) {
	if w.teleport_counter == 0 && inp.fire_down {
		if w.rapid_fire_countdown == 0 {
			inp.fire_down = false
		}
		slot := -1
		for i in 0 ..< MAX_SHOTS {
			if w.shots[i].x == -99 {
				slot = i
				break
			}
		}
		if slot >= 0 && w.player_shots_active < w.player_firepower {
			w.player_shots_active += 1
			is_power := false
			if w.powershots_left > 0 {
				w.powershots_left -= 1
				is_power = true
			}

			sx, sy: int
			fly_up := w.player_aiming_up
			if fly_up {
				sx = w.player_screen_x + 1
				sy = w.player_screen_y
			} else {
				sx = w.player_screen_x - 2 if w.player_dir != 0 else w.player_screen_x + 2
				proj_dy :=
					int(sprites.infos[SPR_PLAYER].projectile_delta_y) if sprites != nil else 9
				sy = w.player_screen_y + proj_dy
			}

			w.shots[slot] = Player_Shot {
				x        = sx,
				y        = sy,
				dir      = w.player_dir,
				fly_up   = fly_up,
				is_power = is_power,
			}

			if w.rapid_fire_countdown == 0 {
				world_play_sound(w, SFX_PLAYERSHOT)
			} else {
				world_play_sound(w, SFX_ENEMYSHOT)
			}
		}
	}

	if w.rapid_fire_countdown > 0 {
		w.rapid_fire_countdown -= 1
		if w.rapid_fire_countdown == 1 {
			w.rapid_fire_countdown = 0
			w.player_firepower = w.old_firepower
		}
	}

	shootable := w.level.tile_info.shootable_tile

	for i in 0 ..< MAX_SHOTS {
		s := &w.shots[i]
		if s.x == -99 {
			continue
		}

		if !s.fly_up {
			if s.dir == 0 {
				ti := (s.y / 16 + w.cam_y) * MAP_WIDTH + s.x / 4 + w.cam_x + 1
				if tile_main_safe(&w.level, ti) == shootable {
					destroy_shootable_tile(w, s, ti, s.x + 2 - (w.odd_cam_x << 1), s.y - 8)
				} else if tile_main_safe(&w.level, ti + MAP_WIDTH) == shootable {
					destroy_shootable_tile(
						w,
						s,
						ti + MAP_WIDTH,
						s.x + 2 - (w.odd_cam_x << 1),
						s.y + 8,
					)
				} else if tile_main_safe(&w.level, ti + 1) == shootable {
					destroy_shootable_tile(w, s, ti + 1, s.x + 6 - (w.odd_cam_x << 1), s.y - 8)
				} else if tile_main_safe(&w.level, ti + MAP_WIDTH + 1) == shootable {
					destroy_shootable_tile(
						w,
						s,
						ti + MAP_WIDTH + 1,
						s.x + 6 - (w.odd_cam_x << 1),
						s.y + 8,
					)
				} else if tile_main_safe(&w.level, ti) != EMPTY_TILE ||
				   tile_main_safe(&w.level, ti + 1) != EMPTY_TILE {
					spawn_particles(w, (s.x << 2) + 24, s.y + 10)
					s.x = -99
					w.player_shots_active -= 1
				} else {
					s.x += 4
					if s.x > 79 || s.y < 0 {
						s.x = -99
						w.player_shots_active -= 1
					} else if assets.rand_next(&w.rng, 10) > 2 {
						spawn_snow(w, s.x, s.y + 5)
					}
				}
			} else {
				ti := (s.y / 16 + w.cam_y) * MAP_WIDTH + s.x / 4 + w.cam_x + 1
				if tile_main_safe(&w.level, ti) == shootable {
					destroy_shootable_tile(w, s, ti, s.x - (w.odd_cam_x << 1), s.y - 8)
				} else if tile_main_safe(&w.level, ti + MAP_WIDTH) == shootable {
					destroy_shootable_tile(w, s, ti + MAP_WIDTH, s.x - (w.odd_cam_x << 1), s.y + 8)
				} else if tile_main_safe(&w.level, ti - 1) == shootable {
					destroy_shootable_tile(w, s, ti - 1, s.x - 2 - (w.odd_cam_x << 1), s.y - 8)
				} else if tile_main_safe(&w.level, ti + MAP_WIDTH - 1) == shootable {
					destroy_shootable_tile(
						w,
						s,
						ti + MAP_WIDTH - 1,
						s.x - 2 - (w.odd_cam_x << 1),
						s.y + 8,
					)
				} else if tile_main_safe(&w.level, ti - 1) != EMPTY_TILE ||
				   tile_main_safe(&w.level, ti) != EMPTY_TILE {
					spawn_particles(w, (s.x << 2) + 1, s.y + 2)
					s.x = -99
					w.player_shots_active -= 1
				} else {
					s.x -= 4
					if s.x < -3 || s.y < 0 {
						s.x = -99
						w.player_shots_active -= 1
					} else if assets.rand_next(&w.rng, 10) > 2 {
						spawn_snow(w, s.x, s.y + 5)
					}
				}
			}
		} else {
			ti := (s.y / 16 + w.cam_y) * MAP_WIDTH + s.x / 4 + w.cam_x + (1 if s.dir != 0 else 0)
			ti -= MAP_WIDTH
			if ti < 0 {
				ti += MAP_WIDTH
			}
			if tile_main_safe(&w.level, ti - w.player_dir) == shootable {
				destroy_shootable_tile(
					w,
					s,
					ti - w.player_dir,
					s.x - 1 - (w.odd_cam_x << 1),
					s.y - 15,
				)
			} else if tile_main_safe(&w.level, ti - w.player_dir + 1) == shootable {
				destroy_shootable_tile(
					w,
					s,
					ti - w.player_dir + 1,
					s.x + 3 - (w.odd_cam_x << 1),
					s.y - 15,
				)
			} else if tile_main_safe(&w.level, ti) != EMPTY_TILE {
				spawn_particles(w, (s.x << 2) + 8, s.y + 2)
				s.x = -99
				w.player_shots_active -= 1
			} else {
				s.y -= 16
				if s.x > 79 || s.y < 0 {
					s.x = -99
					w.player_shots_active -= 1
				} else if assets.rand_next(&w.rng, 10) > 2 {
					spawn_snow(w, s.x + (w.player_dir << 1), s.y + 5)
				}
			}
		}
	}
}

draw_player_shots :: proc(
	r: ^render.GPU_Renderer,
	bank: ^Sprite_Bank,
	w: ^World,
	cam_off_y: f32 = 0,
	alpha: f32 = 1.0,
) {
	if !bank.slot_loaded[SPR_PLAYER] {
		return
	}
	proj_start := int(bank.infos[SPR_PLAYER].projectile_start)
	for s in w.shots {
		if s.x == -99 {
			continue
		}
		frame := proj_start
		if s.fly_up {
			frame = proj_start + 3 if s.is_power else proj_start + 1
		} else {
			frame = proj_start + 2 if s.is_power else proj_start
		}
		sx := f32(s.x * 4)
		sy := f32(s.y) + cam_off_y
		if alpha < 0.9999 && s.prev_valid {
			sx = math.round(math.lerp(f32(s.prev_x * 4), f32(s.x * 4), alpha))
			sy = math.round(math.lerp(f32(s.prev_y), f32(s.y), alpha) + cam_off_y)
		}
		draw_sprite_px(r, bank, SPR_PLAYER, sx, sy, s.dir, frame)
	}
}

update_player_movement :: proc(w: ^World, inp: ^Input_State, sprites: ^Sprite_Bank) {
	pinfo :=
		sprites.infos[SPR_PLAYER] if (sprites != nil && sprites.slot_loaded[SPR_PLAYER]) else assets.Sprite_Info{stand_frame = 0, walk_start = 1, walk_end = 6, jump_start = 7, jump_end = 8, shoot_start = 9}

	if w.teleport_counter == 0 {
		if inp.jump_down && !w.player_jumping && !w.cam_scrolled && !w.player_falling {
			world_play_sound(w, SFX_HITFLOOR)
			inp.jump_down = false
			w.player_jumping = true
			w.player_jump_index = 0
			if !w.super_jump {
				w.using_hi_jump = false
				w.max_jump_index = 9
				w.max_delta_y_index = 19
			} else {
				w.super_jump = false
				w.using_hi_jump = true
				w.max_jump_index = 12
				w.max_delta_y_index = 25
				world_play_sound(w, SFX_TELEPORT)
			}
		}

		jump_ended := false
		if w.player_jumping && w.player_death_countdown == 0 && w.level_done_countdown == 0 {
			jump_deltas := PLAYER_DELTA_YS_HI[:] if w.using_hi_jump else PLAYER_DELTA_YS[:]
			if w.player_jump_index < w.max_delta_y_index {
				w.player_y += jump_deltas[w.player_jump_index]
				if w.player_y < 0 do w.player_y = 0
				w.player_tile_y = w.player_y / 16
				ti := w.player_tile_y * MAP_WIDTH + (w.player_x + 1) / 2
				if tile_main_safe(&w.level, ti) != EMPTY_TILE {
					w.player_jump_index = (w.max_delta_y_index - 1) - w.player_jump_index
					w.player_y += jump_deltas[w.player_jump_index]
					if w.player_y < 0 do w.player_y = 0
					w.player_tile_y = w.player_y / 16
				}
				w.player_jump_index += 1
				if w.player_jump_index >= w.max_delta_y_index {
					w.player_jumping = false
					jump_ended = true
				}
			} else {
				w.player_jumping = false
				jump_ended = true
			}
		}

		floor_ti := w.player_tile_y * MAP_WIDTH + (w.player_x + 1) / 2 + MAP_WIDTH * 2
		if tile_main_safe(&w.level, floor_ti) != EMPTY_TILE {
			if w.player_jumping && w.player_jump_index >= w.max_jump_index {
				w.player_jumping = false
				w.player_y = w.player_tile_y << 4
				world_play_sound(w, SFX_HITFLOOR)
			}
			w.player_falling = false
			if w.was_falling {
				w.was_falling = false
				world_play_sound(w, SFX_HITFLOOR)
			}
		} else if !w.player_jumping &&
		   w.player_death_countdown == 0 &&
		   w.level_done_countdown == 0 {
			w.player_y += 16
			if tile_main_safe(&w.level, floor_ti + MAP_WIDTH) == EMPTY_TILE {
				w.player_falling = true
				w.was_falling = true
			}
		}
		if jump_ended && !w.player_falling {
			world_play_sound(w, SFX_HITFLOOR)
		}

		can_w, can_e, can_nw, can_ne: bool
		ti_w := w.player_tile_y * MAP_WIDTH + (w.player_x / 2)
		ti_e := w.player_tile_y * MAP_WIDTH + ((w.player_x + 2) / 2)
		aligned_y := (w.player_y % 16) == 0

		if aligned_y {
			if tile_main_safe(&w.level, ti_w) == EMPTY_TILE &&
			   tile_main_safe(&w.level, ti_w + MAP_WIDTH) == EMPTY_TILE {
				can_w = true
			}
			if tile_main_safe(&w.level, ti_w - MAP_WIDTH) == EMPTY_TILE &&
			   tile_main_safe(&w.level, ti_w) == EMPTY_TILE &&
			   tile_main_safe(&w.level, ti_w + MAP_WIDTH) != EMPTY_TILE {
				can_nw = true
			}
			if tile_main_safe(&w.level, ti_e) == EMPTY_TILE &&
			   tile_main_safe(&w.level, ti_e + MAP_WIDTH) == EMPTY_TILE {
				can_e = true
			}
			if tile_main_safe(&w.level, ti_e - MAP_WIDTH) == EMPTY_TILE &&
			   tile_main_safe(&w.level, ti_e) == EMPTY_TILE &&
			   tile_main_safe(&w.level, ti_e + MAP_WIDTH) != EMPTY_TILE {
				can_ne = true
			}
		} else {
			if tile_main_safe(&w.level, ti_w) == EMPTY_TILE &&
			   tile_main_safe(&w.level, ti_w + MAP_WIDTH) == EMPTY_TILE &&
			   tile_main_safe(&w.level, ti_w + MAP_WIDTH * 2) == EMPTY_TILE {
				can_w = true
			}
			if tile_main_safe(&w.level, ti_w - MAP_WIDTH) == EMPTY_TILE &&
			   tile_main_safe(&w.level, ti_w) == EMPTY_TILE &&
			   tile_main_safe(&w.level, ti_w + MAP_WIDTH) != EMPTY_TILE {
				can_nw = true
			}
			if tile_main_safe(&w.level, ti_e) == EMPTY_TILE &&
			   tile_main_safe(&w.level, ti_e + MAP_WIDTH) == EMPTY_TILE &&
			   tile_main_safe(&w.level, ti_e + MAP_WIDTH * 2) == EMPTY_TILE {
				can_e = true
			}
			if tile_main_safe(&w.level, ti_e - MAP_WIDTH) == EMPTY_TILE &&
			   tile_main_safe(&w.level, ti_e) == EMPTY_TILE &&
			   tile_main_safe(&w.level, ti_e + MAP_WIDTH) != EMPTY_TILE {
				can_ne = true
			}
		}
		if w.player_falling || w.player_jumping {
			can_nw = false
			can_ne = false
		}

		w.player_walking = false
		if inp.left && w.player_x > 0 {
			if w.player_dir == 0 {
				w.player_dir = 1
			} else if can_w {
				w.player_x -= 1
				advance_player_walk_frame(w, pinfo)
			} else if can_nw {
				w.player_x -= 1
				w.player_y -= 16
				advance_player_walk_frame(w, pinfo)
			}
		}
		if inp.right && w.player_x < 477 {
			if w.player_dir != 0 {
				w.player_dir = 0
			} else if can_e {
				w.player_x += 1
				advance_player_walk_frame(w, pinfo)
			} else if can_ne {
				w.player_x += 1
				w.player_y -= 16
				advance_player_walk_frame(w, pinfo)
			}
		}

		if !w.wizard_activated && w.elevator_tile1 != -1 {
			eti := w.player_tile_y * MAP_WIDTH + (w.player_x + 1) / 2 + MAP_WIDTH * 2
			etile := int(tile_main_safe(&w.level, eti))
			if etile == w.elevator_tile1 || etile == w.elevator_tile2 {
				if etile == w.elevator_tile2 {
					eti -= 1
				}
				if inp.up || inp.use_down {
					above := eti - MAP_WIDTH * 3
					inp.use_down = false
					inp.use_up = true
					if tile_main_safe(&w.level, above) == EMPTY_TILE &&
					   tile_main_safe(&w.level, above + 1) == EMPTY_TILE {
						w.player_y -= 16
						dst := eti - MAP_WIDTH
						w.level.map_main[dst] = w.level.map_main[eti]
						w.level.map_main[eti] = EMPTY_TILE
						w.level.map_main[dst + 1] = w.level.map_main[eti + 1]
						w.level.map_main[eti + 1] = EMPTY_TILE
						w.up_key_counter = 0
					}
				} else if inp.down {
					below := eti + MAP_WIDTH
					if tile_main_safe(&w.level, below) == EMPTY_TILE &&
					   tile_main_safe(&w.level, below + 1) == EMPTY_TILE {
						w.player_y += 16
						w.level.map_main[below] = w.level.map_main[eti]
						w.level.map_main[eti] = EMPTY_TILE
						w.level.map_main[below + 1] = w.level.map_main[eti + 1]
						w.level.map_main[eti + 1] = EMPTY_TILE
						w.down_key_counter = 0
					}
				}
			}
		}

		if !w.player_walking && !w.player_firing {
			w.player_frame = int(pinfo.stand_frame)
		}
	} else {
		if w.teleport_end_x == w.player_x && w.teleport_end_y == w.player_y {
			if w.teleport_counter == 25 {
				world_play_sound(w, SFX_TELEPORT)
			}
			if w.teleport_counter == 40 {
				w.teleport_counter = 0
			} else {
				w.teleport_counter += 1
			}
		} else if w.teleport_counter < 25 {
			w.teleport_counter += 1
		}

		if w.teleport_counter == 25 {
			if w.player_y < w.teleport_end_y do w.player_y += 16
			if w.player_y > w.teleport_end_y do w.player_y -= 16
			if w.player_x < w.teleport_end_x do w.player_x += 1
			if w.player_x > w.teleport_end_x do w.player_x -= 1
		}
	}

	if inp.up {
		w.up_key_counter = min(w.up_key_counter + 1, 10)
	} else {
		w.up_key_counter = 0
	}
	if inp.down {
		w.down_key_counter = min(w.down_key_counter + 1, 10)
	} else {
		w.down_key_counter = 0
	}

	if (inp.scroll_down || w.down_key_counter > 0) && w.look_delta_y > 0 {
		w.look_delta_y -= 1
	}
	if (inp.scroll_up || w.up_key_counter > 0) && w.look_delta_y < 8 {
		w.look_delta_y += 1
	}
	if !inp.scroll_down && !inp.scroll_up && w.up_key_counter != 10 && w.down_key_counter != 10 {
		w.look_delta_y = 5
	}
}

draw_player :: proc(
	r: ^render.GPU_Renderer,
	bank: ^Sprite_Bank,
	w: ^World,
	cam_x_px, cam_y_px: f32,
	alpha: f32 = 1.0,
) {
	if w.hide_countdown > 0 || !bank.slot_loaded[SPR_PLAYER] {
		return
	}

	world_x := f32(w.player_x * 8)
	world_y := f32(w.player_y)
	if alpha < 0.9999 &&
	   abs(w.player_x - w.prev_player_x) <= 4 &&
	   abs(w.player_y - w.prev_player_y) <= 32 {
		world_x = math.round(math.lerp(f32(w.prev_player_x * 8), world_x, alpha))
		world_y = math.round(math.lerp(f32(w.prev_player_y), world_y, alpha))
	}
	px := world_x - cam_x_px
	py := world_y - cam_y_px

	pinfo := bank.infos[SPR_PLAYER]
	if w.teleport_counter == 0 {
		frame := w.player_frame
		if w.player_firing && !w.player_walking {
			frame = int(pinfo.shoot_start) + 1 if w.player_aiming_up else int(pinfo.shoot_start)
		}
		if w.player_jumping {
			frame = int(pinfo.jump_start)
			if w.player_jump_index > w.max_jump_index {
				frame = int(pinfo.jump_end)
			}
		}
		if w.player_falling {
			frame = int(pinfo.jump_end)
		}

		flash := Sprite_Flash.None
		if (w.hurt_countdown % 2) != 0 {
			flash = .Red
		} else if (w.rapid_fire_countdown % 2) != 0 {
			flash = .White
		}
		draw_sprite_px(r, bank, SPR_PLAYER, px, py, w.player_dir, frame, flash)
	} else {
		morph_frame := 0
		dy := 0
		switch {
		case w.teleport_counter < 5:
			morph_frame = 0
		case w.teleport_counter < 10:
			morph_frame = 1
		case w.teleport_counter < 15:
			morph_frame = 2
		case w.teleport_counter < 20:
			morph_frame = 3
		case w.teleport_counter <= 25:
			morph_frame = 4
			dy = int(assets.rand_next(&w.rng, 2)) - int(assets.rand_next(&w.rng, 2))
		case w.teleport_counter < 30:
			morph_frame = 3
		case w.teleport_counter < 35:
			morph_frame = 2
		case w.teleport_counter < 40:
			morph_frame = 1
		}
		draw_sprite_px(r, bank, SPR_MORPH, px, py + f32(dy), w.player_dir, morph_frame)
	}

	if w.powershots_left > 0 && w.tick1 != 0 {
		count := min(w.powershots_left, 3)
		for i in 0 ..< count {
			draw_sprite_px(
				r,
				bank,
				SPR_PLAYER,
				px + 4.0,
				(py - 14.0) - f32(14 * i),
				w.player_dir,
				int(pinfo.projectile_start) + 2,
			)
		}
	}
}
