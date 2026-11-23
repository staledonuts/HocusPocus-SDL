package game

update_camera :: proc(w: ^World) {
	old_y := w.cam_y
	old_x := w.cam_x_t8

	w.player_x_pix = w.player_x << 1
	w.player_tile_y = w.player_y / 16
	w.odd_cam_x = 0

	if w.cam_warp {
		if w.player_x - 20 < 0 {
			w.cam_x_t8 = 0
		} else if w.player_x + 20 >= 480 {
			w.cam_x_t8 = 440
		} else {
			w.cam_x_t8 = w.player_x - 20
			if w.player_x % 2 != 0 {
				w.odd_cam_x = 1
			}
		}
	} else {
		if w.player_x - 20 < 0 {
			w.cam_x_t8 = 0
		} else if w.player_x + 20 >= 480 {
			w.cam_x_t8 = 440
		} else {
			if w.player_x - 20 > w.cam_x_t8 {
				w.cam_x_t8 += 1
			} else if w.player_x - 20 < w.cam_x_t8 {
				w.cam_x_t8 -= 1
			}
			if w.player_x % 2 != 0 {
				w.odd_cam_x = 1
			}
			delta_x_px := (old_x - w.cam_x_t8) << 3
			for &burst in w.particles {
				if burst.state > 0 {
					for &p in burst.pixels {
						p.x += delta_x_px
						if burst.prev_valid {
							p.prev_x += delta_x_px
						}
					}
				}
			}
			delta_x_col4 := delta_x_px / 4
			for &st in w.score_tags {
				st.x += delta_x_col4
				if st.prev_valid {
					st.prev_x += delta_x_col4
				}
			}
			for &tw in w.twinks {
				tw.x += delta_x_col4
				if tw.prev_valid {
					tw.prev_x += delta_x_col4
				}
			}
			for &sn in w.snow {
				if sn.x != -99 {
					sn.x += delta_x_col4
					if sn.prev_valid {
						sn.prev_x += delta_x_col4
					}
				}
			}
		}
	}

	w.player_tile_x = w.player_x / 2
	w.cam_x = w.cam_x_t8 / 2
	w.cam_scrolled = false

	if !w.cam_warp {
		if !w.player_jumping {
			if w.player_tile_y - w.look_delta_y < 0 {
				w.cam_y = 0
			} else if w.player_tile_y + (10 - w.look_delta_y) >= MAP_HEIGHT {
				w.cam_y = MAP_HEIGHT - 10
			} else if w.player_tile_y - w.look_delta_y > w.cam_y {
				w.cam_y += 1
				w.cam_scrolled = true
			} else if w.player_tile_y - w.look_delta_y < w.cam_y {
				w.cam_y -= 1
				w.cam_scrolled = true
			}

			delta_y := (old_y - w.cam_y) << 4
			if delta_y != 0 {
				for &s in w.shots {
					if s.x != -99 {
						s.y += delta_y
						if s.prev_valid {
							s.prev_y += delta_y
						}
					}
				}
				for &burst in w.particles {
					if burst.state > 0 {
						for &p in burst.pixels {
							p.y += delta_y
							if burst.prev_valid {
								p.prev_y += delta_y
							}
						}
					}
				}
				for &st in w.score_tags {
					st.y += delta_y
					if st.prev_valid {
						st.prev_y += delta_y
					}
				}
				for &tw in w.twinks {
					tw.y += delta_y
					if tw.prev_valid {
						tw.prev_y += delta_y
					}
				}
				for &sn in w.snow {
					if sn.x != -99 {
						sn.y += delta_y
						if sn.prev_valid {
							sn.prev_y += delta_y
						}
					}
				}
			}
		}
	} else {
		if !w.player_jumping {
			if w.player_tile_y - w.look_delta_y < 0 {
				w.cam_y = 0
			} else if w.player_tile_y + w.look_delta_y >= MAP_HEIGHT {
				w.cam_y = MAP_HEIGHT - 10
			} else {
				w.cam_y = w.player_tile_y - w.look_delta_y
			}
		}
	}

	w.player_screen_x = (w.player_x - w.cam_x_t8) << 1
	w.player_screen_y = w.player_y - (w.cam_y << 4)
}
