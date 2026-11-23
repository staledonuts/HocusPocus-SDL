package game

import "../assets"

SFX_PLAYERSHOT :: 0
SFX_HEAL :: 1
SFX_BONUS1 :: 2
SFX_BONUS2 :: 3
SFX_CRYSTAL :: 4
SFX_TELEPORT :: 5
SFX_FLIPSWITCH :: 6
SFX_SWOOSH :: 7
SFX_OUCH :: 8
SFX_YAHOO :: 9
SFX_EXPLODE :: 10
SFX_LAUGH :: 11
SFX_DRAGONFIRE :: 12
SFX_ENEMYSHOT :: 13
SFX_ENEMYSPAWN :: 14
SFX_HITFLOOR :: 15

@(private)
trigger_tile_rect :: proc(lvl: ^Level_Data, left, top, right, bottom: int, kind: u8) {
	for ty := top; ty <= bottom; ty += 1 {
		for tx := left; tx <= right; tx += 1 {
			if tx < 0 || tx >= MAP_WIDTH || ty < 0 || ty >= MAP_HEIGHT {
				continue
			}
			ti := ty * MAP_WIDTH + tx
			if kind == 1 {
				if lvl.map_main[ti] != EMPTY_TILE {
					lvl.map_triggered[ti] = 1
				}
			} else {
				if lvl.map_insert[ti] != EMPTY_TILE {
					lvl.map_triggered[ti] = 2
				}
			}
		}
	}
}

@(private)
activate_key_trigger :: proc(w: ^World, trig: Trigger, info_index: int, trigger_kind: u8) {
	activated := 0
	if trig.required_key == 0 do activated = 1
	if trig.required_key == 1 && w.got_key1 do activated = 2
	if trig.required_key == 2 && w.got_key2 do activated = 3

	if activated != 0 {
		world_play_sound(w, SFX_SWOOSH)
		w.level.tile_countdown = 10
		trigger_tile_rect(
			&w.level,
			int(trig.left),
			int(trig.top),
			int(trig.right),
			int(trig.bottom),
			trigger_kind,
		)
		w.level.map_info[info_index] = EMPTY_INFO
		if trig.required_key == 0 {
			w.level.map_back[info_index] = trig.replace_tile
		} else {
			w.level.map_back[info_index] = w.level.tile_info.back_tile
		}
		if activated > 1 {
			spawn_twink(
				w,
				((info_index % MAP_WIDTH) - w.cam_x) << 2,
				((info_index / MAP_WIDTH) - w.cam_y) << 4,
			)
		}
	}
	if activated == 2 do w.got_key1 = false
	if activated == 3 do w.got_key2 = false
}

update_world_tiles :: proc(w: ^World) {
	w.level.tile_countdown -= 1

	for y in 0 ..< 10 {
		map_y := w.cam_y + y
		if map_y < 0 || map_y >= MAP_HEIGHT {
			continue
		}
		for x in 0 ..< 21 {
			map_x := w.cam_x + x
			if map_x < 0 || map_x >= MAP_WIDTH {
				continue
			}
			ti := map_y * MAP_WIDTH + map_x

			trig := w.level.map_triggered[ti]
			if trig != 0 {
				if w.level.tile_countdown <= 0 {
					if trig == 1 {
						w.level.map_main[ti] = EMPTY_TILE
						w.level.map_triggered[ti] = 0
					} else if trig == 2 {
						w.level.map_main[ti] = w.level.map_insert[ti]
						w.level.map_triggered[ti] = 0
					}
				} else if assets.rand_next(&w.rng, 3) == 0 {
					if trig == 1 {
						w.level.map_main[ti] = EMPTY_TILE
						w.level.map_triggered[ti] = 0
						if x < 20 {
							spawn_twink(w, (x << 2) - (w.odd_cam_x << 1), y << 4)
						}
					} else if trig == 2 {
						w.level.map_main[ti] = w.level.map_insert[ti]
						w.level.map_triggered[ti] = 0
						if x < 20 {
							spawn_twink(w, (x << 2) - (w.odd_cam_x << 1), y << 4)
						}
					}
				}
			}

			tile := w.level.map_back[ti]
			if tile < 240 {
				anim := w.level.tile_info.anim[tile]
				if anim.type == 1 {
					next_tile := tile + 1
					if next_tile > anim.last {
						next_tile = anim.first
					}
					w.level.map_back[ti] = next_tile
				} else if anim.type == 2 {
					if tile != anim.first {
						next_tile := tile + 1
						if next_tile > anim.last {
							next_tile = anim.first
						}
						w.level.map_back[ti] = next_tile
					} else if assets.rand_next(&w.rng, 20) == 0 {
						w.level.map_back[ti] = tile + 1
					}
				}
			}
		}
	}
}

check_tiles :: proc(w: ^World, inp: ^Input_State, sprites: ^Sprite_Bank) {
	if w.hurt_countdown > 0 {
		w.hurt_countdown -= 1
	}

	for dx := -1; dx <= 1; dx += 1 {
		base_x := (w.player_x + 1) / 2 + dx
		if base_x < 0 || base_x >= MAP_WIDTH {
			continue
		}
		info_index := w.player_tile_y * MAP_WIDTH + base_x
		sx := w.player_screen_x - 1
		sy := w.player_screen_y - 16
		w.wizard_activated = false

		for dy := 0; dy < 2; dy += 1 {
			defer {
				info_index += MAP_WIDTH
				sy += 16
			}
			if info_index < 0 || info_index >= MAP_TILES {
				continue
			}

			infoval := int(w.level.map_info[info_index])
			keep := false
			if infoval == int(EMPTY_INFO) {
				continue
			}

			if infoval >= 0 && infoval < 23 {
				item := ITEM_INFOS[infoval]
				itemtype := item.type

				if item.heal != 0 && w.player_health < 100 {
					world_play_sound(w, SFX_HEAL)
				} else if item.heal != 0 {
					keep = true
				} else if item.score != 0 {
					w.treasure_found += 1
					if w.treasure_found == w.level.treasure_total {
						w.hud_level_num_flash = 1
						world_play_sound(w, SFX_YAHOO)
					}
					switch item.score {
					case 100:
						spawn_score_tag(w, sx, sy, 0)
					case 250:
						spawn_score_tag(w, sx, sy, 1)
					case 500:
						spawn_score_tag(w, sx, sy, 2)
					case 1000:
						spawn_score_tag(w, sx, sy, 3)
					case 5000:
						spawn_score_tag(w, sx, sy, 4)
					}
					world_play_sound(w, SFX_BONUS1 + int(assets.rand_next(&w.rng, 2)))
				} else if itemtype == 1 {
					w.crystals_collected += 1
					w.level_flash_red_countdown = 8
					world_play_sound(w, SFX_CRYSTAL)
				} else if itemtype == 2 {
					keep = true
					if w.hurt_countdown == 0 && w.hide_countdown == 0 && dx == 0 {
						w.player_health += SKILL_DAMAGE[w.skill]
						w.hurt_countdown = 20
						world_play_sound(w, SFX_OUCH)
					}
				} else if itemtype == 9 {
					if w.hurt_countdown == 0 && w.hide_countdown == 0 && dx == 0 {
						w.player_health += SKILL_DAMAGE[w.skill]
						w.hurt_countdown = 10
						world_play_sound(w, SFX_OUCH)
					}
					keep = true
				} else if itemtype == 3 {
					w.hide_countdown = 400
					spawn_twink(w, w.player_screen_x - 1, w.player_screen_y)
					spawn_twink(w, w.player_screen_x + 4, w.player_screen_y)
					spawn_twink(w, w.player_screen_x - 1, w.player_screen_y + 16)
					spawn_twink(w, w.player_screen_x + 4, w.player_screen_y + 16)
					w.hurt_countdown = 0
					world_play_sound(w, SFX_TELEPORT)
					spawn_score_tag(w, sx, sy, 8)
				} else if itemtype == 4 {
					if !w.super_jump && dx == 0 {
						w.super_jump = true
						w.super_jump_counter = 25
						world_play_sound(w, SFX_YAHOO)
						spawn_score_tag(w, sx, sy, 7)
					} else {
						keep = true
					}
				} else if itemtype == 5 {
					if dx != 0 {
						keep = true
					} else {
						if w.rapid_fire_countdown == 0 {
							w.old_firepower = w.player_firepower
							w.player_firepower = 10
						}
						w.rapid_fire_countdown = 600
						world_play_sound(w, SFX_YAHOO)
						spawn_score_tag(w, sx, sy, 9)
					}
				} else if itemtype == 7 {
					w.got_key1 = true
					world_play_sound(w, SFX_YAHOO)
					spawn_score_tag(w, sx, sy, 5)
				} else if itemtype == 8 {
					w.got_key2 = true
					world_play_sound(w, SFX_YAHOO)
					spawn_score_tag(w, sx, sy, 5)
				} else if itemtype == 10 {
					keep = true
					if inp.use_down {
						for m in 0 ..< 10 {
							if int(w.level.messages[m].pos_y) == w.player_tile_y &&
							   abs(int(w.level.messages[m].pos_x) - w.player_tile_x) < 3 {
								world_play_sound(w, SFX_TELEPORT)
								w.active_wizard_msg = m
								w.wizard_activated = true
								break
							}
						}
						inp.use_down = false
					}
				} else if itemtype == 11 {
					if dx != 0 {
						keep = true
					} else {
						w.powershots_left += 3
						world_play_sound(w, SFX_YAHOO)
						w.tick1 = 1
						w.tick5 = 5
					}
				} else if itemtype == 12 {
					w.old_player_x = w.player_x
					w.old_player_y = w.player_y
					keep = true
					w.level.map_info[info_index] = EMPTY_INFO
					w.level.map_back[info_index] = w.level.tile_info.back_tile
					if info_index + 1 < MAP_TILES {
						w.level.map_info[info_index + 1] = EMPTY_INFO
						w.level.map_back[info_index + 1] = w.level.tile_info.back_tile
					}
					world_play_sound(w, SFX_YAHOO)
				}

				if item.firepower != 0 {
					world_play_sound(w, SFX_YAHOO)
				}
				w.player_firepower = min(w.player_firepower + int(item.firepower), 10)
				if w.rapid_fire_countdown > 0 {
					w.old_firepower = min(w.old_firepower + int(item.firepower), 10)
				}
				w.score += i32(item.score)
				w.player_health = clamp(w.player_health + int(item.heal), 0, 100)

				if !keep {
					w.level.map_info[info_index] = EMPTY_INFO
					w.level.map_back[info_index] = w.level.tile_info.back_tile
				}
			} else if infoval >= 23 && infoval < 33 {
				num := infoval - 23
				if int(w.level.teleporters[num].start_off) == info_index && dx == 0 {
					w.teleport_counter = 1
					end_off := int(w.level.teleporters[num].end_off)
					w.teleport_end_y = (end_off / MAP_WIDTH) << 4
					w.teleport_end_x = (end_off % MAP_WIDTH) << 1
					if sprites != nil && sprites.slot_loaded[SPR_PLAYER] {
						w.player_frame = int(sprites.infos[SPR_PLAYER].stand_frame)
					}
					w.player_jumping = false
					w.player_y = (w.player_y / 16) << 4
					w.level.map_info[info_index] = EMPTY_INFO
					w.level.map_back[info_index] = w.level.tile_info.back_tile
					world_play_sound(w, SFX_TELEPORT)
					spawn_score_tag(w, sx, sy, 6)
				}
			} else if infoval >= 33 && infoval < 56 {
				if inp.use_down && dx == 0 {
					inp.use_down = false
					if w.level.map_back[info_index] == w.level.tile_info.switch_down_tile {
						w.level.map_back[info_index] = w.level.tile_info.switch_up_tile
					} else {
						w.level.map_back[info_index] = w.level.tile_info.switch_down_tile
					}

					num := infoval - 33
					sw := &w.level.switches[num]
					has_active := false
					for i in 0 ..< 4 {
						if sw.switch_offsets[i] != -1 {
							has_active = true
							break
						}
					}

					if has_active {
						correct := true
						for i in 0 ..< 4 {
							off := int(sw.switch_offsets[i])
							if off >= 0 && off < MAP_TILES {
								desired := sw.desired_tiles[i]
								if desired == w.level.tile_info.switch_down_tile &&
								   w.level.map_back[off] != w.level.tile_info.switch_down_tile {
									correct = false
								}
								if desired == w.level.tile_info.switch_up_tile &&
								   w.level.map_back[off] != w.level.tile_info.switch_up_tile {
									correct = false
								}
							}
						}

						if correct {
							world_play_sound(w, SFX_SWOOSH)
							w.level.tile_countdown = 25
							kind: u8 = 1 if sw.type == 0 else 2
							trigger_tile_rect(
								&w.level,
								int(sw.left),
								int(sw.top),
								int(sw.right),
								int(sw.bottom),
								kind,
							)
							for i in 0 ..< 4 {
								sw.switch_offsets[i] = -1
							}
						} else {
							world_play_sound(w, SFX_FLIPSWITCH)
						}
					} else {
						world_play_sound(w, SFX_FLIPSWITCH)
					}
				}
			} else if infoval >= 56 && infoval < 81 {
				activate_key_trigger(w, w.level.inserts[infoval - 56], info_index, 2)
			} else if infoval >= 81 && infoval < 106 {
				activate_key_trigger(w, w.level.keyholes[infoval - 81], info_index, 1)
			} else if infoval >= 116 && infoval <= 365 && dx == 0 {
				num := infoval - 116
				for i in 0 ..< 8 {
					off := int(w.level.enemy_triggers[num].offsets[i])
					if off >= 0 && off < MAP_TILES && w.level.map_info[off] != EMPTY_INFO {
						already := false
						for a in w.actors {
							if a.type != -1 && a.tile_index == off {
								already = true
								break
							}
						}
						if !already {
							for q in w.spawn_tile_index {
								if q == off {
									already = true
									break
								}
							}
						}
						if !already {
							for &q in w.spawn_tile_index {
								if q == -1 {
									q = off
									break
								}
							}
						}
					}
				}
			}
		}
	}
}
