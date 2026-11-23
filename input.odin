package main

import "assets"
import "audio"
import "game"
import "render"
import sdl "vendor:sdl3"

@(private)
wrap_index :: proc(cur, delta, count: int) -> int {
	return (cur + delta + count) % count
}

@(private)
update_edge_trigger :: proc(held: bool, down, up: ^bool) {
	if held {
		if up^ {
			down^ = true
			up^ = false
		}
	} else {
		down^ = false
		up^ = true
	}
}

update_gameplay_input :: proc(inp: ^game.Input_State, ctx: ^GameContext, locked: bool) {
	if locked {
		game.init_input_state(inp)
		return
	}

	keys := sdl.GetKeyboardState(nil)
	s := &ctx.settings
	gamepad := ctx.gamepad

	gp_left, gp_right, gp_up, gp_down, gp_jump, gp_fire, gp_scroll_up, gp_scroll_down: bool
	if s.gamepad_enabled && gamepad != nil {
		dz := i16(clamp(s.gamepad_deadzone, 5, 90) * 32767 / 100)
		axis_x := sdl.GetGamepadAxis(gamepad, .LEFTX)
		axis_y := sdl.GetGamepadAxis(gamepad, .LEFTY)
		rt := sdl.GetGamepadAxis(gamepad, .RIGHT_TRIGGER)

		gp_left = sdl.GetGamepadButton(gamepad, .DPAD_LEFT) || axis_x < -dz
		gp_right = sdl.GetGamepadButton(gamepad, .DPAD_RIGHT) || axis_x > dz
		gp_up = sdl.GetGamepadButton(gamepad, .DPAD_UP) || axis_y < -dz
		gp_down = sdl.GetGamepadButton(gamepad, .DPAD_DOWN) || axis_y > dz
		if s.gamepad_swap_buttons {
			gp_jump = sdl.GetGamepadButton(gamepad, .EAST)
			gp_fire =
				sdl.GetGamepadButton(gamepad, .SOUTH) ||
				sdl.GetGamepadButton(gamepad, .WEST) ||
				rt > 10000
		} else {
			gp_jump = sdl.GetGamepadButton(gamepad, .SOUTH)
			gp_fire =
				sdl.GetGamepadButton(gamepad, .WEST) ||
				sdl.GetGamepadButton(gamepad, .EAST) ||
				rt > 10000
		}
		gp_scroll_up = sdl.GetGamepadButton(gamepad, .LEFT_SHOULDER)
		gp_scroll_down = sdl.GetGamepadButton(gamepad, .RIGHT_SHOULDER)
	}

	kb := s.key_bindings
	inp.left = keys[kb[.Left]] || gp_left
	inp.right = keys[kb[.Right]] || gp_right
	inp.down = keys[kb[.Down]] || gp_down
	inp.scroll_up = keys[kb[.Scroll_Up]] || gp_scroll_up
	inp.scroll_down = keys[kb[.Scroll_Down]] || gp_scroll_down

	up_held := keys[kb[.Up]] || gp_up
	inp.up = up_held
	update_edge_trigger(up_held, &inp.use_down, &inp.use_up)
	update_edge_trigger(keys[kb[.Jump]] || gp_jump, &inp.jump_down, &inp.jump_up)
	update_edge_trigger(keys[kb[.Fire]] || gp_fire, &inp.fire_down, &inp.fire_up)
}

handle_gamepad_button_down :: proc(app: ^App, btn: sdl.GamepadButton) {
	if app.state == .Key_Controls_Menu && app.waiting_for_key {
		if btn == .EAST || btn == .BACK {
			app.waiting_for_key = false
		}
		return
	}

	if !app.ctx.settings.gamepad_enabled {
		return
	}

	if app.editing_name || app.state == .Enter_Highscore {
		#partial switch btn {
		case .EAST, .BACK:
			handle_key_down(app, .ESCAPE, 0)
		case .START:
			handle_key_down(app, .RETURN, 0)
		}
		return
	}

	if app.state == .Playing {
		if app.demo.active {
			enter_main_menu(app, restart_music = true)
			return
		}
		if app.overlay != .None {
			app.overlay = .None
			app.wizard_msg_idx = -1
			return
		}
		#partial switch btn {
		case .START:
			handle_key_down(app, .ESCAPE, 0)
		case .BACK:
			handle_key_down(app, .P, 0)
		}
		return
	}

	#partial switch app.state {
	case .Intro_Apogee, .Intro_Title, .Intermission, .Warp_Screen:
		handle_key_down(app, .RETURN, 0)
		return
	}

	#partial switch btn {
	case .DPAD_UP:
		handle_key_down(app, .UP, 0)
	case .DPAD_DOWN:
		handle_key_down(app, .DOWN, 0)
	case .DPAD_LEFT, .LEFT_SHOULDER:
		handle_key_down(app, .LEFT, 0)
	case .DPAD_RIGHT, .RIGHT_SHOULDER:
		handle_key_down(app, .RIGHT, 0)
	case .SOUTH, .START:
		handle_key_down(app, .RETURN, 0)
	case .EAST, .BACK:
		handle_key_down(app, .ESCAPE, 0)
	}
}

update_gamepad_menu_nav :: proc(app: ^App, dt: f32) {
	ctx := &app.ctx
	inactive :=
		!ctx.settings.gamepad_enabled ||
		ctx.gamepad == nil ||
		app.state == .Playing ||
		app.waiting_for_key ||
		app.editing_name ||
		app.state == .Enter_Highscore
	if inactive {
		app.gp_nav_dir_x = 0
		app.gp_nav_dir_y = 0
		app.gp_nav_timer = 0
		return
	}

	thresh := max(i16(clamp(ctx.settings.gamepad_deadzone, 5, 90) * 32767 / 100), i16(16000))
	ax := sdl.GetGamepadAxis(ctx.gamepad, .LEFTX)
	ay := sdl.GetGamepadAxis(ctx.gamepad, .LEFTY)

	dx, dy: int
	if ax < -thresh {
		dx = -1
	} else if ax > thresh {
		dx = 1
	}
	if ay < -thresh {
		dy = -1
	} else if ay > thresh {
		dy = 1
	}

	if dx != 0 && dy != 0 {
		if abs(int(ax)) > abs(int(ay)) {
			dy = 0
		} else {
			dx = 0
		}
	}

	if dx == 0 && dy == 0 {
		app.gp_nav_dir_x = 0
		app.gp_nav_dir_y = 0
		app.gp_nav_timer = 0
		return
	}

	trigger := false
	if dx != app.gp_nav_dir_x || dy != app.gp_nav_dir_y {
		app.gp_nav_dir_x = dx
		app.gp_nav_dir_y = dy
		app.gp_nav_timer = 0.35
		trigger = true
	} else {
		app.gp_nav_timer -= dt
		if app.gp_nav_timer <= 0 {
			app.gp_nav_timer = 0.15
			trigger = true
		}
	}

	if !trigger {
		return
	}

	if dy < 0 {
		handle_key_down(app, .UP, 0)
	} else if dy > 0 {
		handle_key_down(app, .DOWN, 0)
	} else if dx < 0 {
		handle_key_down(app, .LEFT, 0)
	} else if dx > 0 {
		handle_key_down(app, .RIGHT, 0)
	}
}

handle_name_edit_key :: proc(
	app: ^App,
	sc: sdl.Scancode,
	keycode: sdl.Keycode,
) -> (
	confirmed, cancelled: bool,
) {
	#partial switch sc {
	case .ESCAPE:
		return false, true
	case .RETURN, .KP_ENTER:
		return true, false
	case .BACKSPACE:
		if app.edit_len > 0 do app.edit_len -= 1
	case:
		if keycode >= 32 && keycode <= 122 && app.edit_len < MAX_NAME_LEN - 1 {
			ch := u8(keycode)
			keys := sdl.GetKeyboardState(nil)
			shift := keys[sdl.Scancode.LSHIFT] || keys[sdl.Scancode.RSHIFT]
			if shift && ch >= 'a' && ch <= 'z' {
				ch -= 32
			}
			app.edit_buf[app.edit_len] = ch
			app.edit_len += 1
		}
	}
	return false, false
}

@(private)
handle_key_binding_capture :: proc(app: ^App, sc: sdl.Scancode) {
	if sc == .ESCAPE {
		app.waiting_for_key = false
		return
	}
	if sc == .UNKNOWN {
		return
	}
	ctx := &app.ctx
	target_act := Control_Action(clamp(app.menu_sel, 0, NUM_CONTROL_ACTIONS - 1))
	prev_sc := ctx.settings.key_bindings[target_act]
	for other_act in Control_Action {
		if other_act != target_act && ctx.settings.key_bindings[other_act] == sc {
			ctx.settings.key_bindings[other_act] = prev_sc
		}
	}
	ctx.settings.key_bindings[target_act] = sc
	app.waiting_for_key = false
	_ = save_settings(ctx)
	audio.play_sfx(ctx.aud, game.SFX_PLAYERSHOT)
}

@(private)
handle_main_menu_key :: proc(app: ^App, sc: sdl.Scancode) {
	app.menu_idle_s = 0
	#partial switch sc {
	case .UP, .W:
		app.menu_sel = wrap_index(app.menu_sel, -1, 8)
	case .DOWN, .S:
		app.menu_sel = wrap_index(app.menu_sel, 1, 8)
	case .D:
		start_demo(app, app.next_demo_num)
		app.next_demo_num = (app.next_demo_num + 1) % 5
	case .ESCAPE:
		app.running = false
	case .RETURN, .KP_ENTER, .SPACE:
		switch app.menu_sel {
		case 0:
			app.state = .Episode_Menu
			app.menu_sel = app.cur_episode
		case 1:
			app.state = .Restore_Menu
			app.return_state = .Main_Menu
			app.menu_sel = 0
		case 2:
			enter_text_group(app, .Ordering, .Main_Menu)
		case 3:
			enter_help(app, .Main_Menu)
		case 4:
			enter_text_group(app, .Story, .Main_Menu)
		case 5:
			app.state = .Options_Menu
			app.return_state = .Main_Menu
			app.menu_sel = 0
		case 6:
			app.state = .Highscores
			app.hs_episode = app.cur_episode
		case 7:
			app.running = false
		}
	}
}

@(private)
handle_options_menu_key :: proc(app: ^App, sc: sdl.Scancode) {
	ctx := &app.ctx
	#partial switch sc {
	case .UP, .W:
		app.menu_sel = wrap_index(app.menu_sel, -1, 6)
	case .DOWN, .S:
		app.menu_sel = wrap_index(app.menu_sel, 1, 6)
	case .ESCAPE:
		_ = save_config(ctx)
		_ = save_settings(ctx)
		if app.return_state == .Ingame_Menu {
			app.state = .Ingame_Menu
			app.menu_sel = 4
		} else {
			enter_main_menu(app)
		}
	case .RETURN, .KP_ENTER, .SPACE:
		switch app.menu_sel {
		case 0:
			ctx.cfg.sound_on = 0 if ctx.cfg.sound_on != 0 else 1
			sync_audio_from_config(ctx)
		case 1:
			ctx.cfg.music_on = 0 if ctx.cfg.music_on != 0 else 1
			sync_audio_from_config(ctx)
		case 2:
			app.state = .Volume_Menu
			app.menu_sel = 0
		case 3:
			app.state = .Video_Menu
			app.menu_sel = 0
		case 4:
			app.state = .Input_Menu
			app.menu_sel = 0
		case 5:
			app.state = .Speed_Menu
			app.menu_sel = int(ctx.cfg.game_speed)
		}
		_ = save_config(ctx)
	}
}

@(private)
handle_volume_menu_key :: proc(app: ^App, sc: sdl.Scancode) {
	ctx := &app.ctx
	delta := 0
	#partial switch sc {
	case .UP, .W, .DOWN, .S:
		app.menu_sel = 1 - app.menu_sel
	case .LEFT, .A:
		delta = -16
	case .RIGHT, .D:
		delta = 16
	case .ESCAPE, .RETURN, .KP_ENTER:
		_ = save_config(ctx)
		app.state = .Options_Menu
		app.menu_sel = 2
	}
	if delta != 0 {
		if app.menu_sel == 0 {
			ctx.cfg.sound_volume = i16le(clamp(int(ctx.cfg.sound_volume) + delta, 0, 255))
		} else {
			ctx.cfg.music_volume = i16le(clamp(int(ctx.cfg.music_volume) + delta, 0, 255))
		}
		sync_audio_from_config(ctx)
		audio.play_sfx(ctx.aud, game.SFX_PLAYERSHOT)
	}
}

@(private)
handle_video_menu_key :: proc(app: ^App, sc: sdl.Scancode) {
	ctx := &app.ctx
	dir := 0
	#partial switch sc {
	case .UP, .W:
		app.menu_sel = wrap_index(app.menu_sel, -1, 6)
	case .DOWN, .S:
		app.menu_sel = wrap_index(app.menu_sel, 1, 6)
	case .LEFT, .A:
		dir = -1
	case .RIGHT, .D, .RETURN, .KP_ENTER, .SPACE:
		dir = 1
	case .ESCAPE:
		_ = save_settings(ctx)
		app.state = .Options_Menu
		app.menu_sel = 3
	}
	if dir == 0 {
		return
	}

	switch app.menu_sel {
	case 0:
		ctx.settings.fullscreen = !ctx.settings.fullscreen
	case 1:
		ctx.settings.aspect_mode = render.Aspect_Mode(
			wrap_index(int(ctx.settings.aspect_mode), dir, 3),
		)
	case 2:
		ctx.settings.integer_scale = !ctx.settings.integer_scale
	case 3:
		ctx.settings.vsync = !ctx.settings.vsync
	case 4:
		ctx.settings.scanlines_level = wrap_index(
			ctx.settings.scanlines_level,
			dir,
			len(SCANLINE_LEVELS),
		)
	case 5:
		ctx.settings.smooth_motion = !ctx.settings.smooth_motion
	}
	apply_video_settings(ctx)
	_ = save_settings(ctx)
	audio.play_sfx(ctx.aud, game.SFX_PLAYERSHOT)
}

@(private)
handle_input_menu_key :: proc(app: ^App, sc: sdl.Scancode) {
	ctx := &app.ctx
	dir := 0
	#partial switch sc {
	case .UP, .W:
		app.menu_sel = wrap_index(app.menu_sel, -1, 4)
	case .DOWN, .S:
		app.menu_sel = wrap_index(app.menu_sel, 1, 4)
	case .LEFT, .A:
		dir = -1
	case .RIGHT, .D:
		dir = 1
	case .RETURN, .KP_ENTER, .SPACE:
		if app.menu_sel == 0 {
			app.state = .Key_Controls_Menu
			app.menu_sel = 0
			app.waiting_for_key = false
			return
		}
		dir = 1
	case .ESCAPE:
		_ = save_settings(ctx)
		app.state = .Options_Menu
		app.menu_sel = 4
	}
	if dir == 0 {
		return
	}

	switch app.menu_sel {
	case 1:
		ctx.settings.gamepad_enabled = !ctx.settings.gamepad_enabled
	case 2:
		ctx.settings.gamepad_swap_buttons = !ctx.settings.gamepad_swap_buttons
	case 3:
		dz_idx := 1
		for v, idx in DEADZONE_OPTIONS {
			if v == ctx.settings.gamepad_deadzone {
				dz_idx = idx
				break
			}
		}
		ctx.settings.gamepad_deadzone =
			DEADZONE_OPTIONS[wrap_index(dz_idx, dir, len(DEADZONE_OPTIONS))]
	}
	_ = save_settings(ctx)
	audio.play_sfx(ctx.aud, game.SFX_PLAYERSHOT)
}

@(private)
handle_save_menu_key :: proc(app: ^App, sc: sdl.Scancode, keycode: sdl.Keycode) {
	ctx := &app.ctx
	if app.editing_name {
		confirmed, cancelled := handle_name_edit_key(app, sc, keycode)
		if confirmed {
			slot := app.menu_sel
			name := string(app.edit_buf[:app.edit_len]) if app.edit_len > 0 else "Saved Game"
			ctx.cfg.sg_episodes[slot] = i16le(app.cur_episode)
			ctx.cfg.sg_levels[slot] = i16le(app.cur_level)
			ctx.cfg.sg_skill[slot] = i16le(app.cur_skill)
			ctx.cfg.sg_scores[slot] = i32le(app.world.old_score)
			copy_str_into(ctx.cfg.sg_names[slot][:], name)
			_ = save_config(ctx)
			app.editing_name = false
			app.state = .Ingame_Menu
			app.menu_sel = 5
		} else if cancelled {
			app.editing_name = false
		}
		return
	}

	#partial switch sc {
	case .UP, .W:
		app.menu_sel = wrap_index(app.menu_sel, -1, NUM_SAVEGAMES)
	case .DOWN, .S:
		app.menu_sel = wrap_index(app.menu_sel, 1, NUM_SAVEGAMES)
	case .ESCAPE:
		app.state = .Ingame_Menu
		app.menu_sel = 2
	case .RETURN, .KP_ENTER, .SPACE:
		app.editing_name = true
		app.edit_len = 0
	}
}

@(private)
return_from_help :: proc(app: ^App, fade: bool) {
	ctx := &app.ctx
	if app.return_state == .Playing {
		app.state = .Playing
		render.set_palette(ctx.ren, app.gfx.palette)
		if fade do render.fade_from_black(ctx.ren, 0.2)
	} else if app.return_state == .Ingame_Menu {
		app.state = .Ingame_Menu
		render.set_palette(ctx.ren, ctx.ui_assets.menu_palette)
		if fade do render.fade_from_black(ctx.ren, 0.2)
	} else {
		enter_main_menu(app)
	}
}

@(private)
return_from_text_page :: proc(app: ^App) {
	if app.return_state == .Enter_Highscore {
		finish_episode_or_quit_to_menu(app)
	} else if app.return_state == .Episode_Menu {
		app.state = .Episode_Menu
	} else {
		enter_main_menu(app)
	}
}

@(private)
handle_playing_key :: proc(app: ^App, sc: sdl.Scancode, keycode: sdl.Keycode) {
	ctx := &app.ctx
	if app.demo.active {
		enter_main_menu(app, restart_music = true)
		return
	}
	if app.overlay != .None {
		app.overlay = .None
		app.wizard_msg_idx = -1
		return
	}

	if keycode >= 'a' && keycode <= 'z' {
		msg := game.cheat_feed_char(
			&app.cheat,
			u8(keycode),
			app.world,
			assets.is_registered(&ctx.dat),
		)
		if len(msg) > 0 {
			app.toast_text = msg
			app.toast_timer = 2.5
		}
	}

	#partial switch sc {
	case .ESCAPE:
		app.state = .Ingame_Menu
		app.menu_sel = 5
		render.set_palette(ctx.ren, ctx.ui_assets.menu_palette)
		render.fade_from_black(ctx.ren, 0.25)
	case .P:
		app.overlay = .Paused
	case .F1:
		enter_help(app, .Playing)
	case .M:
		ctx.cfg.music_on = 0 if ctx.cfg.music_on != 0 else 1
		sync_audio_from_config(ctx)
	case .N:
		ctx.cfg.sound_on = 0 if ctx.cfg.sound_on != 0 else 1
		sync_audio_from_config(ctx)
	case ._1 ..= ._9:
		new_lv := int(sc) - int(sdl.Scancode._1)
		if new_lv >= 0 && new_lv < 9 {
			start_level(app, app.cur_episode, new_lv, app.cur_skill, app.world.score, false)
		}
	}
}

@(private)
handle_ingame_menu_key :: proc(app: ^App, sc: sdl.Scancode) {
	ctx := &app.ctx
	#partial switch sc {
	case .UP, .W:
		app.menu_sel = wrap_index(app.menu_sel, -1, 7)
	case .DOWN, .S:
		app.menu_sel = wrap_index(app.menu_sel, 1, 7)
	case .ESCAPE:
		app.state = .Playing
		render.set_palette(ctx.ren, app.gfx.palette)
		render.fade_from_black(ctx.ren, 0.2)
	case .RETURN, .KP_ENTER, .SPACE:
		switch app.menu_sel {
		case 0:
			enter_help(app, .Ingame_Menu)
		case 1:
			start_level(
				app,
				app.cur_episode,
				app.cur_level,
				app.cur_skill,
				app.world.old_score,
				false,
			)
		case 2:
			app.state = .Save_Menu
			app.editing_name = false
			app.menu_sel = 0
		case 3:
			app.state = .Restore_Menu
			app.return_state = .Ingame_Menu
			app.menu_sel = 0
		case 4:
			app.state = .Options_Menu
			app.return_state = .Ingame_Menu
			app.menu_sel = 0
		case 5:
			app.state = .Playing
			render.set_palette(ctx.ren, app.gfx.palette)
			render.fade_from_black(ctx.ren, 0.2)
		case 6:
			finish_episode_or_quit_to_menu(app)
		}
	}
}

handle_key_down :: proc(app: ^App, sc: sdl.Scancode, keycode: sdl.Keycode) {
	ctx := &app.ctx

	if app.state == .Key_Controls_Menu && app.waiting_for_key {
		handle_key_binding_capture(app, sc)
		return
	}

	if sc == .F5 {
		ctx.settings.aspect_mode = render.Aspect_Mode(
			wrap_index(int(ctx.settings.aspect_mode), 1, 3),
		)
		apply_video_settings(ctx)
		_ = save_settings(ctx)
		return
	}
	if sc == .F11 {
		ctx.settings.fullscreen = !ctx.settings.fullscreen
		apply_video_settings(ctx)
		_ = save_settings(ctx)
		return
	}

	switch app.state {
	case .Intro_Apogee:
		enter_intro_title(app)

	case .Intro_Title:
		enter_main_menu(app, restart_music = false)

	case .Main_Menu:
		handle_main_menu_key(app, sc)

	case .Episode_Menu:
		#partial switch sc {
		case .UP, .W:
			app.menu_sel = wrap_index(app.menu_sel, -1, 4)
		case .DOWN, .S:
			app.menu_sel = wrap_index(app.menu_sel, 1, 4)
		case .ESCAPE:
			enter_main_menu(app)
		case .RETURN, .KP_ENTER, .SPACE:
			if app.menu_sel > 0 && !assets.is_registered(&ctx.dat) {
				enter_text_group(app, .Ordering, .Episode_Menu)
			} else {
				app.cur_episode = app.menu_sel
				app.state = .Skill_Menu
				app.menu_sel = app.cur_skill
			}
		}

	case .Skill_Menu:
		#partial switch sc {
		case .UP, .W:
			app.menu_sel = wrap_index(app.menu_sel, -1, 3)
		case .DOWN, .S:
			app.menu_sel = wrap_index(app.menu_sel, 1, 3)
		case .ESCAPE:
			app.state = .Episode_Menu
			app.menu_sel = app.cur_episode
		case .RETURN, .KP_ENTER, .SPACE:
			app.cur_skill = app.menu_sel
			start_level(
				app,
				app.cur_episode,
				0,
				app.cur_skill,
				0,
				show_crystal_popup = (app.cur_episode == 0),
			)
		}

	case .Options_Menu:
		handle_options_menu_key(app, sc)

	case .Volume_Menu:
		handle_volume_menu_key(app, sc)

	case .Video_Menu:
		handle_video_menu_key(app, sc)

	case .Input_Menu:
		handle_input_menu_key(app, sc)

	case .Key_Controls_Menu:
		num_rows := NUM_CONTROL_ACTIONS + 1
		#partial switch sc {
		case .UP, .W:
			app.menu_sel = wrap_index(app.menu_sel, -1, num_rows)
		case .DOWN, .S:
			app.menu_sel = wrap_index(app.menu_sel, 1, num_rows)
		case .ESCAPE:
			app.waiting_for_key = false
			app.state = .Input_Menu
			app.menu_sel = 0
		case .RETURN, .KP_ENTER, .SPACE:
			if app.menu_sel < NUM_CONTROL_ACTIONS {
				app.waiting_for_key = true
			} else {
				reset_default_key_bindings(&ctx.settings)
				_ = save_settings(ctx)
				audio.play_sfx(ctx.aud, game.SFX_PLAYERSHOT)
			}
		}

	case .Speed_Menu:
		#partial switch sc {
		case .UP, .W:
			app.menu_sel = wrap_index(app.menu_sel, -1, 3)
		case .DOWN, .S:
			app.menu_sel = wrap_index(app.menu_sel, 1, 3)
		case .ESCAPE:
			app.state = .Options_Menu
			app.menu_sel = 5
		case .RETURN, .KP_ENTER, .SPACE:
			ctx.cfg.game_speed = u16le(app.menu_sel)
			_ = save_config(ctx)
			app.state = .Options_Menu
			app.menu_sel = 5
		}

	case .Highscores:
		#partial switch sc {
		case .LEFT, .A:
			app.hs_episode = wrap_index(app.hs_episode, -1, 4)
		case .RIGHT, .D:
			app.hs_episode = wrap_index(app.hs_episode, 1, 4)
		case .ESCAPE, .RETURN, .SPACE:
			enter_main_menu(app)
		}

	case .Enter_Highscore:
		confirmed, cancelled := handle_name_edit_key(app, sc, keycode)
		if confirmed {
			name := string(app.edit_buf[:app.edit_len]) if app.edit_len > 0 else "Hocus Pocus"
			insert_highscore(&ctx.cfg, app.cur_episode, app.hs_pending_rank, name, app.world.score)
			_ = save_config(ctx)
			app.state = .Highscores
			app.hs_episode = app.cur_episode
		} else if cancelled {
			enter_main_menu(app)
		}

	case .Save_Menu:
		handle_save_menu_key(app, sc, keycode)

	case .Restore_Menu:
		#partial switch sc {
		case .UP, .W:
			app.menu_sel = wrap_index(app.menu_sel, -1, NUM_SAVEGAMES)
		case .DOWN, .S:
			app.menu_sel = wrap_index(app.menu_sel, 1, NUM_SAVEGAMES)
		case .ESCAPE:
			if app.return_state == .Ingame_Menu {
				app.state = .Ingame_Menu
				app.menu_sel = 3
			} else {
				enter_main_menu(app)
			}
		case .RETURN, .KP_ENTER, .SPACE:
			slot := app.menu_sel
			ep := int(ctx.cfg.sg_episodes[slot])
			lv := int(ctx.cfg.sg_levels[slot])
			sk := int(ctx.cfg.sg_skill[slot])
			sc_pts := i32(ctx.cfg.sg_scores[slot])
			if ep >= 0 && ep < 4 && lv >= 0 && lv < 9 {
				if ep == 0 || assets.is_registered(&ctx.dat) {
					start_level(app, ep, lv, sk, sc_pts, false)
				}
			}
		}

	case .Help_Screen:
		#partial switch sc {
		case .ESCAPE:
			return_from_help(app, fade = true)
		case .LEFT, .A:
			if app.help_page > 0 {
				app.help_page -= 1
				load_help_page(app)
			}
		case:
			app.help_page += 1
			if app.help_page >= 3 {
				return_from_help(app, fade = false)
			} else {
				load_help_page(app)
			}
		}

	case .Text_Page_View:
		#partial switch sc {
		case .ESCAPE:
			return_from_text_page(app)
		case .LEFT, .A, .PAGEUP:
			if app.text_page_idx > 0 {
				app.text_page_idx -= 1
				load_current_text_page(app)
			}
		case .RIGHT, .D, .PAGEDOWN, .SPACE, .RETURN:
			if app.text_page_idx + 1 < app.text_page_count {
				app.text_page_idx += 1
				load_current_text_page(app)
			} else {
				return_from_text_page(app)
			}
		}

	case .Playing:
		handle_playing_key(app, sc, keycode)

	case .Ingame_Menu:
		handle_ingame_menu_key(app, sc)

	case .Intermission:
		if app.intermission.won {
			if app.cur_level == 8 {
				enter_warp(app)
			} else {
				start_level(
					app,
					app.cur_episode,
					app.cur_level + 1,
					app.cur_skill,
					app.world.score,
					false,
				)
			}
		} else {
			start_level(
				app,
				app.cur_episode,
				app.cur_level,
				app.cur_skill,
				app.world.old_score,
				false,
			)
		}

	case .Warp_Screen:
		groups := [4]Text_Page_Group{.Finale_1, .Finale_2, .Finale_3, .Finale_4}
		enter_text_group(app, groups[clamp(app.cur_episode, 0, 3)], .Enter_Highscore)
	}
}
