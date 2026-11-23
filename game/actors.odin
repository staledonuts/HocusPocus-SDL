package game

import "../assets"
import "../render"
import "core:math"

check_enemy_shot_hits_player :: proc(w: ^World) {
	max_x := w.player_x_pix + 3
	min_x := w.player_x_pix + 2
	max_y := w.player_y + 25
	min_y := w.player_y + 6

	for &es in w.enemy_shots {
		if es.state == -1 {
			continue
		}
		if es.delay == 0 && w.hurt_countdown == 0 && w.hide_countdown == 0 {
			if es.x <= max_x &&
			   es.x + es.width - 1 >= min_x &&
			   es.y <= max_y &&
			   es.y + es.height - 1 >= min_y {
				w.player_health += SKILL_DAMAGE[w.skill]
				w.hurt_countdown = 20
				world_play_sound(w, SFX_OUCH)
				es.state = -1
			}
		}
	}
}

check_enemy_hits_player :: proc(w: ^World) {
	max_x := w.player_x_pix + 3
	min_x := w.player_x_pix + 2
	max_y := w.player_y + 25
	min_y := w.player_y + 6

	for &a in w.actors {
		if a.type != -1 && w.hide_countdown == 0 && a.spawn_countdown == 0 {
			if a.x <= max_x &&
			   a.x + a.width - 1 >= min_x &&
			   a.y <= max_y &&
			   a.y + a.height - 1 >= min_y {
				if a.max_health > 20 && w.skill != 3 {
					w.player_health = 0
				} else if w.hurt_countdown == 0 {
					w.player_health += SKILL_DAMAGE[w.skill]
					w.hurt_countdown = 20
					world_play_sound(w, SFX_OUCH)
				}
			}
		}
	}
}

kill_active_enemies :: proc(w: ^World) {
	for &a in w.actors {
		if a.type != -1 {
			base_x := a.x - (w.cam_x_t8 << 1)
			base_y := a.y - (w.cam_y << 4)
			pix_x := (base_x + (a.width / 2)) << 2
			pix_y := base_y + (a.height / 2)
			spawn_particles(w, pix_x, pix_y)
			world_play_sound(w, SFX_EXPLODE)
			a.type = -1
			if a.tile_index >= 0 && a.tile_index < MAP_TILES {
				w.level.map_info[a.tile_index] = EMPTY_INFO
			}
			w.num_enemies_killed += 1
		}
	}
}

check_enemy_hits_player_shot :: proc(w: ^World) {
	for &a in w.actors {
		if a.type == -1 || a.spawn_countdown > 0 {
			continue
		}
		min_x := a.x - (w.cam_x_t8 << 1)
		max_x := min_x + a.width - 1
		min_y := a.y - (w.cam_y << 4)
		max_y := min_y + a.height - 1
		pix_x := (min_x + (a.width / 2)) << 2
		pix_y := min_y + (a.height / 2)

		for &s in w.shots {
			sx := s.x
			sy := s.y + 2
			if sx != -99 && sx >= min_x && sx <= max_x && sy >= min_y && sy <= max_y {
				spawn_particles(w, pix_x, pix_y)
				if !s.is_power {
					s.x = -99
					w.player_shots_active -= 1
				}
				if a.health == -2 {
					a.health = -1
					kill_active_enemies(w)
					break
				} else if a.health != -1 {
					if a.health > 0 && !s.is_power {
						a.health -= 1
						a.flashing = 10
					} else {
						world_play_sound(w, SFX_EXPLODE)
						spawn_particles(w, pix_x, pix_y)
						spawn_particles(w, pix_x, pix_y)
						spawn_particles(w, pix_x, pix_y)
						a.type = -1
						if a.tile_index >= 0 && a.tile_index < MAP_TILES {
							w.level.map_info[a.tile_index] = EMPTY_INFO
						}
						w.num_enemies_killed += 1
						break
					}
				}
			}
		}
	}
}

remove_hidden_actors :: proc(w: ^World) {
	cam_x4 := w.cam_x_t8 << 1
	cam_y_px := w.cam_y << 4

	for &a in w.actors {
		if a.type == -1 {
			continue
		}
		hidden :=
			a.x < cam_x4 - 50 || a.x > cam_x4 + 120 || a.y < cam_y_px - 120 || a.y > cam_y_px + 510
		if hidden && a.max_health < 500 {
			a.type = -1
			a.tile_index = -1
		}
	}
}

spawn_actor :: proc(w: ^World, sprites: ^Sprite_Bank, num, x, y, tile_index: int) -> bool {
	if num < 0 || num >= 10 {
		return false
	}

	slot := -1
	for i in 0 ..< MAX_ACTORS {
		if w.actors[i].type == -1 {
			slot = i
			break
		}
	}
	if slot < 0 {
		return false
	}

	einfo := w.level.enemy_infos[num]
	spr_slot := SPR_ENEMY_0 + num
	spr_w := 8
	spr_h := 32
	if sprites != nil && spr_slot < MAX_SPRITES && sprites.slot_loaded[spr_slot] {
		spr_w = int(sprites.infos[spr_slot].width)
		spr_h = int(sprites.infos[spr_slot].height)
	}

	a := &w.actors[slot]
	a^ = {}
	a.shoot_countdown = 0
	a.spawn_countdown = 20
	a.is_shooting = false
	a.shot_delta_x = int(einfo.projectile_delta_x)
	a.sprite = spr_slot
	a.settings_index = num
	a.type = int(einfo.type)
	a.shoots_in_walk_dir = einfo.shoot_in_walk_dir != 0
	a.can_shoot = einfo.can_shoot != 0
	a.seeking = int(einfo.projectile_seeking)
	a.move_countdown = int(einfo.move_countdown)
	a.x = x
	a.y = y
	a.width = spr_w
	a.height = spr_h
	a.health = int(einfo.health) + (w.skill << 1) if einfo.health >= 0 else int(einfo.health)
	a.max_health = a.health
	a.dir = 1 if x > w.player_x_pix else 0
	if a.type == 2 {
		a.dir = 0
	}
	a.frame = 0
	a.flashing = 0
	a.tile_index = tile_index
	a.one = 1
	a.jump_countdown = 1
	a.countdown = 0
	a.jump_speed = -99

	near_player := abs(x - w.player_x_pix) < 50 && abs(y - w.player_y) < 100
	if w.tick_count > w.next_spawn_sound_tick && near_player {
		world_play_sound(w, SFX_ENEMYSPAWN)
		w.next_spawn_sound_tick = w.tick_count + 1
	}

	switch a.type {
	case 8:
		a.vx = x
		a.move_countdown = int(assets.rand_next(&w.rng, 10)) + 10

	case 2, 3:
		for {
			a.vx = int(assets.rand_next(&w.rng, 2)) - int(assets.rand_next(&w.rng, 2))
			a.vy = (int(assets.rand_next(&w.rng, 2)) - int(assets.rand_next(&w.rng, 2))) << 2
			if a.vx != 0 || a.vy != 0 do break
		}
		a.new_dir_countdown = int(assets.rand_next(&w.rng, 20))

	case 6:
		for {
			a.vx = int(assets.rand_next(&w.rng, 2)) - int(assets.rand_next(&w.rng, 2))
			a.vy = (int(assets.rand_next(&w.rng, 2)) - int(assets.rand_next(&w.rng, 2))) << 2
			if a.vx != 0 do break
		}
		a.new_dir_countdown = int(assets.rand_next(&w.rng, 20))

	case 0, 1, 7:
		a.vx = 1 if a.dir == 0 else -1
		a.vy = 0

	case 4:
		a.vx = 0
		a.vy = 0
		a.dir = 0
		a.frame = 0
		world_play_sound(w, SFX_LAUGH)

	case 5:
		a.vx = 0
		a.vy = 0
		a.frame = 0
	}

	return true
}

update_actor_spawns :: proc(w: ^World, sprites: ^Sprite_Bank) {
	for &ti in w.spawn_tile_index {
		if ti == -1 {
			continue
		}
		if ti < 0 || ti >= MAP_TILES {
			ti = -1
			continue
		}
		infoval := int(w.level.map_info[ti])
		if infoval != int(EMPTY_INFO) && infoval >= 106 && infoval <= 115 {
			y := ti / MAP_WIDTH
			x := ti % MAP_WIDTH
			if spawn_actor(w, sprites, infoval - 106, x << 2, y << 4, ti) {
				ti = -1
			}
		} else {
			ti = -1
		}
	}
}

spawn_enemy_shot :: proc(
	w: ^World,
	sprites: ^Sprite_Bank,
	x, y: int,
	adjust_dir: bool,
	delay: int,
	enemy_num: int,
	spr_slot: int,
) -> bool {
	if enemy_num < 0 || enemy_num >= 10 {
		return false
	}

	slot := -1
	for i in 0 ..< MAX_ENEMYSHOTS {
		if w.enemy_shots[i].state == -1 {
			slot = i
			break
		}
	}
	if slot < 0 {
		return false
	}

	einfo := w.level.enemy_infos[enemy_num]
	sinfo: assets.Sprite_Info
	if sprites != nil && spr_slot >= 0 && spr_slot < MAX_SPRITES && sprites.slot_loaded[spr_slot] {
		sinfo = sprites.infos[spr_slot]
	}

	dir := 0
	delta_x := 0
	if adjust_dir {
		if x <= w.player_x_pix {
			delta_x = int(sinfo.width)
			dir = 0
		} else {
			delta_x = 0
			dir = 1
		}
	}

	w.enemy_shots[slot] = Enemy_Shot {
		state     = 30000,
		delay     = delay,
		dir       = dir,
		wobble    = einfo.projectile_tumbling != 0,
		width     = int(sinfo.projectile_width),
		height    = int(sinfo.projectile_height) + 3,
		frame     = int(sinfo.projectile_start),
		max_frame = int(sinfo.projectile_end),
		x         = x + delta_x,
		y         = y + int(sinfo.projectile_delta_y),
		sprite    = spr_slot,
		speed_x   = int(einfo.projectile_speed_x),
		speed_y   = int(einfo.projectile_speed_y),
		seeking   = einfo.projectile_seeking != 0,
	}
	world_play_sound(w, SFX_ENEMYSHOT)
	return true
}

update_enemy_shots :: proc(w: ^World) {
	for &es in w.enemy_shots {
		if es.state == -1 {
			continue
		}
		if es.delay > 0 {
			es.delay -= 1
			continue
		}

		x := es.x - (w.cam_x_t8 << 1)
		y := es.y - (w.cam_y << 4)
		blocked := 0
		if x < -10 || x > 80 || y < -20 || y > VIEWPORT_H {
			blocked = 1
		}
		ti := (es.y / 16) * MAP_WIDTH + (es.x / 4)
		if tile_main_safe(&w.level, ti) != EMPTY_TILE {
			blocked = 2
		}

		if blocked != 0 {
			es.state = -1
			if blocked == 2 {
				spawn_particles(w, (x << 2) + 8, y + 8)
			}
		} else {
			if es.frame < es.max_frame {
				es.frame += 1
			}
			if es.dir == 0 {
				es.x += es.speed_x
			} else {
				es.x -= es.speed_x
			}
			if es.seeking {
				if es.x < w.player_x_pix {
					es.x += 1
				} else if es.x > w.player_x_pix {
					es.x -= 1
				}
			}
			es.y += es.speed_y
			if es.wobble {
				es.y += int(assets.rand_next(&w.rng, 2)) - int(assets.rand_next(&w.rng, 2))
			}
		}
	}
}

@(private)
interp_world_pos :: proc(
	prev_x, prev_y, cur_x, cur_y: int,
	valid: bool,
	alpha: f32,
) -> (
	wx, wy: f32,
) {
	wx = f32(cur_x * 4)
	wy = f32(cur_y)
	if alpha < 0.9999 && valid && abs(cur_x - prev_x) <= 16 && abs(cur_y - prev_y) <= 48 {
		wx = math.round(math.lerp(f32(prev_x * 4), wx, alpha))
		wy = math.round(math.lerp(f32(prev_y), wy, alpha))
	}
	return wx, wy
}

@(private)
tick_actor_spawn_effect :: proc(w: ^World, a: ^Actor) -> bool {
	if a.spawn_countdown <= 0 {
		return false
	}
	x := a.x - (w.cam_x_t8 << 1) + (a.width / 2)
	y := a.y - (w.cam_y << 4) + (a.height / 2)
	if assets.rand_next(&w.rng, 5) == 0 {
		spawn_twink(
			w,
			x + int(assets.rand_next(&w.rng, 3)) - int(assets.rand_next(&w.rng, 3)),
			y + int(assets.rand_next(&w.rng, 12)) - int(assets.rand_next(&w.rng, 12)),
		)
	}
	a.spawn_countdown -= 1
	return true
}

@(private)
bounce_ground_walker :: proc(
	w: ^World,
	a: ^Actor,
	old_x, old_y, tile_index, tw, th: int,
	blocked: bool,
) {
	ti := tile_index + th * MAP_WIDTH
	if a.dir == 0 {
		ti += tw - 2
	}
	should_turn := blocked || tile_main_safe(&w.level, ti) == EMPTY_TILE
	if should_turn {
		a.x = old_x
		a.y = old_y
		a.dir = 1 if a.dir == 0 else 0
		a.vx = 1 if a.dir == 0 else -1
	}
}

draw_enemy_shots :: proc(
	r: ^render.GPU_Renderer,
	bank: ^Sprite_Bank,
	w: ^World,
	cam_x_px, cam_y_px: f32,
	alpha: f32 = 1.0,
) {
	for es in w.enemy_shots {
		if es.state == -1 || es.delay > 0 {
			continue
		}
		wx, wy := interp_world_pos(es.prev_x, es.prev_y, es.x, es.y, es.prev_valid, alpha)
		draw_sprite_px(r, bank, es.sprite, wx - cam_x_px, wy - cam_y_px, es.dir, es.frame)
	}
}

@(private)
update_boss3 :: proc(w: ^World, sprites: ^Sprite_Bank, idx: int) {
	a := &w.actors[idx]
	if tick_actor_spawn_effect(w, a) {
		return
	}

	if a.flashing > 0 {
		a.flashing -= 1
	}

	if a.frame == 1 && assets.rand_next(&w.rng, 10) == 0 && a.x > w.player_x_pix {
		spawn_enemy_shot(w, sprites, a.x, a.y, true, 0, a.settings_index, a.sprite)
		world_play_sound(w, SFX_DRAGONFIRE)
	}

	if a.move_countdown == 0 {
		a.move_countdown = int(assets.rand_next(&w.rng, 10)) + 10
		if a.x < a.vx {
			dx := a.vx - a.x
			if dx >= 5 || assets.rand_next(&w.rng, 2) == 0 {
				a.x += 1
				a.frame -= 1
			} else {
				a.x -= 1
				a.frame += 1
			}
		} else {
			dx := a.x - a.vx
			if dx >= 5 || assets.rand_next(&w.rng, 2) == 0 {
				a.x -= 1
				a.frame += 1
			} else {
				a.x += 1
				a.frame -= 1
			}
		}
	}
	if a.frame > 3 do a.frame = 0
	if a.frame < 0 do a.frame = 3
	a.move_countdown -= 1
}

@(private)
update_boss4 :: proc(w: ^World, sprites: ^Sprite_Bank) {
	a := &w.actors[0]
	if tick_actor_spawn_effect(w, a) {
		return
	}

	a.dir = 1 if a.x > w.player_x_pix else 0
	if a.flashing > 0 {
		a.flashing -= 1
	}

	if a.seeking == 0 {
		if a.shot_delta_x == 0 {
			a.frame = 1
			a.shot_delta_x = 1
			a.seeking = 4
		} else if a.shot_delta_x == 1 {
			a.shot_delta_x = 2
			a.seeking = 1
			spawn_enemy_shot(w, sprites, a.x, a.y, true, 0, a.settings_index, a.sprite)
		} else if a.shot_delta_x == 2 {
			a.frame = 0
			a.shot_delta_x = 0
			a.seeking = int(assets.rand_next(&w.rng, 45)) + 5
		}
	} else {
		a.seeking -= 1
	}

	if w.boss4_stage < 4 && BOSS4_HEALTH[w.boss4_stage] > a.health {
		if a.shot_delta_x < 3 {
			a.shot_delta_x = 3
			a.seeking = 20
			a.frame = 2
			world_play_sound(w, SFX_TELEPORT)
		} else if a.seeking == 0 {
			w.boss4_stage += 1
			if w.boss4_stage < 4 {
				a.type = -1
				spawn_actor(
					w,
					sprites,
					0,
					BOSS4_XS[w.boss4_stage] << 2,
					BOSS4_YS[w.boss4_stage] << 4,
					BOSS4_TILE_OFFS[w.boss4_stage],
				)
				w.actors[0].health = BOSS4_HEALTH[w.boss4_stage - 1]
				w.actors[0].dir = BOSS4_DIRS[w.boss4_stage]
				w.actors[0].vx = 0
				w.actors[0].seeking = int(assets.rand_next(&w.rng, 50)) + 5
				w.actors[0].shot_delta_x = 0
			}
		}
	}
}

update_actors :: proc(w: ^World, sprites: ^Sprite_Bank) {
	rand_div := max(i16(w.level.coordinates.randomness), 1)

	for i in 0 ..< MAX_ACTORS {
		a := &w.actors[i]
		if a.type == -1 {
			continue
		}

		if a.type == 8 {
			update_boss3(w, sprites, i)
			continue
		}
		if a.type == 99 {
			update_boss4(w, sprites)
			continue
		}

		if tick_actor_spawn_effect(w, a) {
			continue
		}

		sinfo: assets.Sprite_Info
		if sprites != nil &&
		   a.sprite >= 0 &&
		   a.sprite < MAX_SPRITES &&
		   sprites.slot_loaded[a.sprite] {
			sinfo = sprites.infos[a.sprite]
		}

		if a.shoot_countdown == 0 {
			if a.jump_countdown == 0 {
				old_x := a.x
				old_y := a.y
				blocked := false
				tile_index := 0
				tw := 0
				th := 0

				if a.jump_speed != -99 {
					a.y += a.jump_speed
					a.jump_speed += 1
					if a.jump_speed == 7 {
						a.jump_speed = -99
						a.frame = 0
					}
				} else {
					a.x += a.vx
					a.y += a.vy

					tile_index = (a.y / 16) * MAP_WIDTH + (a.x / 4)
					if a.dir == 0 {
						tile_index += 1
					}
					tw = a.width / 4
					if (a.x % 4) != 0 do tw += 1
					th = a.height / 16
					if (a.y % 16) != 0 do th += 1

					for iy in 0 ..< th {
						ti := (a.y / 16 + iy) * MAP_WIDTH + (a.x / 4)
						for ix in 0 ..< tw {
							if tile_main_safe(&w.level, ti + ix) != EMPTY_TILE {
								blocked = true
							}
						}
					}
				}

				switch a.type {
				case 2:
					if a.new_dir_countdown <= 0 do blocked = true
					if blocked {
						a.x = old_x
						a.y = old_y
						a.new_dir_countdown = int(assets.rand_next(&w.rng, 30)) + 5
						for {
							if a.seeking == 0 {
								a.vx =
									int(assets.rand_next(&w.rng, 2)) -
									int(assets.rand_next(&w.rng, 2))
							} else {
								a.vx =
									-int(assets.rand_next(&w.rng, 2)) if a.x > w.player_x_pix else int(assets.rand_next(&w.rng, 2))
							}
							a.vy =
								(int(assets.rand_next(&w.rng, 2)) -
									int(assets.rand_next(&w.rng, 2))) <<
								2
							if a.vx != 0 || a.vy != 0 do break
						}
					}
					a.new_dir_countdown -= 1

				case 3:
					if a.new_dir_countdown <= 0 do blocked = true
					if blocked {
						a.x = old_x
						a.y = old_y
						a.new_dir_countdown = int(assets.rand_next(&w.rng, 30)) + 5
						for {
							a.vx =
								int(assets.rand_next(&w.rng, 2)) - int(assets.rand_next(&w.rng, 2))
							a.vy =
								(int(assets.rand_next(&w.rng, 2)) -
									int(assets.rand_next(&w.rng, 2))) <<
								2
							if a.vx != 0 || a.vy != 0 do break
						}
						a.dir = 1 if a.x > w.player_x_pix else 0
					}
					a.new_dir_countdown -= 1

				case 6:
					if a.new_dir_countdown <= 0 do blocked = true
					a.dir = 1 if a.x > w.player_x_pix else 0
					if blocked {
						a.x = old_x
						a.y = old_y
						a.new_dir_countdown = int(assets.rand_next(&w.rng, 30)) + 5
						for {
							a.vx =
								(int(assets.rand_next(&w.rng, 2)) -
									int(assets.rand_next(&w.rng, 2))) *
								2
							a.vy =
								(int(assets.rand_next(&w.rng, 2)) -
									int(assets.rand_next(&w.rng, 2))) <<
								2
							if a.vx != 0 do break
						}
					}
					a.new_dir_countdown -= 1

				case 0:
					bounce_ground_walker(w, a, old_x, old_y, tile_index, tw, th, blocked)
					facing_player :=
						(a.x <= w.player_x_pix && a.dir == 0) ||
						(a.x > w.player_x_pix && a.dir != 0)
					if facing_player && a.can_shoot && assets.rand_next(&w.rng, rand_div) == 0 {
						if sinfo.shoot_start != -1 {
							a.frame = int(sinfo.shoot_start)
						}
						a.shoot_countdown = 9
					} else if assets.rand_next(&w.rng, 20) == 0 {
						a.dir = 1 if a.x > w.player_x_pix else 0
						a.vx = 1 if a.dir == 0 else -1
					}

				case 1:
					bounce_ground_walker(w, a, old_x, old_y, tile_index, tw, th, blocked)
					if assets.rand_next(&w.rng, 20) == 0 {
						a.dir = 1 if a.x > w.player_x_pix else 0
						a.countdown = int(assets.rand_next(&w.rng, 15)) + 10
						if sinfo.shoot_start != -1 {
							a.frame = int(sinfo.shoot_start)
						}
						a.vx = 1 if a.dir == 0 else -1
					}

				case 5:
					a.dir = 1 if a.x > w.player_x_pix else 0
				}

				a.frame += 1
				if a.countdown > 0 {
					if sinfo.shoot_start != -1 {
						if a.frame > int(sinfo.shoot_end) {
							a.frame = int(sinfo.shoot_start)
						}
					} else {
						if a.frame > int(sinfo.walk_end) {
							a.frame = int(sinfo.walk_start)
						}
					}
				} else if a.is_shooting {
					if a.frame > int(sinfo.shoot_end) {
						a.is_shooting = false
						a.frame = int(sinfo.walk_start)
					}
				} else {
					if a.frame > int(sinfo.walk_end) {
						a.frame = int(sinfo.walk_start)
					}
				}

				if a.countdown == 0 {
					a.jump_countdown = a.one
				} else {
					a.jump_countdown = 0
					a.countdown -= 1
				}
			} else {
				a.jump_countdown -= 1
			}
		} else {
			a.shoot_countdown -= 1
		}

		if (a.can_shoot && assets.rand_next(&w.rng, rand_div) == 0 && a.type != 0) ||
		   a.shoot_countdown == 1 {
			delay := 1
			fired := false
			a.is_shooting = true
			if w.level.enemy_infos[a.settings_index].projectile_speed_x != 0 {
				if a.shoots_in_walk_dir {
					if a.type == 5 {
						delay = int(sinfo.shoot_end - sinfo.shoot_start)
					}
					if (a.x <= w.player_x_pix && a.dir == 0) ||
					   (a.x > w.player_x_pix && a.dir != 0) {
						fired = spawn_enemy_shot(
							w,
							sprites,
							a.x,
							a.y,
							true,
							delay,
							a.settings_index,
							a.sprite,
						)
					}
				} else {
					fired = spawn_enemy_shot(
						w,
						sprites,
						a.x,
						a.y,
						true,
						delay,
						a.settings_index,
						a.sprite,
					)
				}
			} else {
				fired = spawn_enemy_shot(
					w,
					sprites,
					a.x + a.shot_delta_x,
					a.y + a.height,
					false,
					delay,
					a.settings_index,
					a.sprite,
				)
			}
			if !fired {
				a.is_shooting = false
			}
			if sinfo.shoot_start != -1 {
				a.frame = int(sinfo.shoot_start)
			}
		}

		if a.jump_speed != -99 {
			a.frame = int(sinfo.jump_start)
		}
		if a.flashing > 0 {
			a.flashing -= 1
		}
	}
}

@(private)
draw_boss_health_bar :: proc(r: ^render.GPU_Renderer, a: ^Actor) {
	if a.max_health <= 0 || a.health <= 0 {
		return
	}
	width_col4 := clamp(int((f32(a.health) / f32(a.max_health)) * 78.0), 0, 78)
	for col in 0 ..< width_col4 {
		color := u8(0x6F - (col / 10))
		render.draw_solid_rect(&r.batch, f32(4 + col * 4), 152, 4, 3, color)
	}
}

draw_actors :: proc(
	r: ^render.GPU_Renderer,
	bank: ^Sprite_Bank,
	w: ^World,
	cam_x_px, cam_y_px: f32,
	alpha: f32 = 1.0,
) {
	for i in 0 ..< MAX_ACTORS {
		a := &w.actors[i]
		if a.type == -1 {
			continue
		}

		if a.type == 8 || a.type == 99 || a.max_health > 20 {
			draw_boss_health_bar(r, a)
		}

		if a.spawn_countdown > 0 {
			continue
		}

		wx, wy := interp_world_pos(a.prev_x, a.prev_y, a.x, a.y, a.prev_valid, alpha)
		sx := wx - cam_x_px
		sy := wy - cam_y_px
		flash := Sprite_Flash.Red if (a.flashing % 2) != 0 else Sprite_Flash.None

		if a.type == 8 {
			dir := 0 if a.frame < 2 else 1
			frame := a.frame if a.frame < 2 else a.frame - 2
			draw_sprite_px(r, bank, a.sprite, sx, sy, dir, frame, flash)
		} else {
			draw_sprite_px(r, bank, a.sprite, sx, sy, a.dir, a.frame, flash)
		}
	}
}
