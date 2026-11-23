package main

import "assets"
import "core:fmt"
import "game"
import "render"
import "ui"

render_app :: proc(app: ^App) {
	ctx := &app.ctx
	r := ctx.ren
	u := ctx.ui_assets

	switch app.state {
	case .Intro_Apogee, .Intro_Title, .Help_Screen, .Warp_Screen:
		render.begin_scene(r)
		if u.screen_pcx.handle != nil {
			render.draw_texture_region(
				&r.batch,
				u.screen_pcx,
				0,
				0,
				f32(u.screen_pcx.width),
				f32(u.screen_pcx.height),
				0,
				0,
				render.SCREEN_WIDTH,
				render.SCREEN_HEIGHT,
			)
		}
		if app.state == .Intro_Title && u.regist_bar.handle != nil {
			render.draw_texture_region(
				&r.batch,
				u.regist_bar,
				0,
				0,
				f32(u.regist_bar.width),
				f32(u.regist_bar.height),
				0,
				188,
				f32(u.regist_bar.width),
				f32(u.regist_bar.height),
			)
		}

	case .Main_Menu:
		items := [8]string {
			"Begin a new game",
			"Restore an old game",
			"Ordering Information",
			"Instructions",
			"Legends and hints",
			"Change game options",
			"High scores",
			"Quit - return to desktop",
		}
		render.begin_scene(r)
		ui.draw_menu_list(
			r,
			u,
			"",
			items[:],
			app.menu_sel,
			app.cursor_tick,
			"UP/DOWN to move - ENTER to select",
		)

	case .Episode_Menu:
		items := [4]string {
			"Time Tripping",
			"Shattered Worlds",
			"Warped and Weary",
			"Destination Home",
		}
		render.begin_scene(r)
		ui.draw_menu_list(
			r,
			u,
			"Which game do you want to play?",
			items[:],
			app.menu_sel,
			app.cursor_tick,
			"UP/DOWN to move - ENTER to select",
		)

	case .Skill_Menu:
		items := [3]string {
			"Easy game - good for beginners",
			"Moderate - a reasonable challenge",
			"Hard - the ultimate battle!",
		}
		render.begin_scene(r)
		ui.draw_menu_list(
			r,
			u,
			"Choose a skill level",
			items[:],
			app.menu_sel,
			app.cursor_tick,
			"UP/DOWN to move - ENTER to select",
		)

	case .Options_Menu:
		snd_str := "Sound is now on" if ctx.cfg.sound_on != 0 else "Sound is now off"
		mus_str := "Music is now on" if ctx.cfg.music_on != 0 else "Music is now off"
		spd_names := [3]string{"Game speed: Slow", "Game speed: Medium", "Game speed: Fast"}
		items := [6]string {
			snd_str,
			mus_str,
			"Volume control",
			"Video settings",
			"Input & Gamepad",
			spd_names[clamp(int(ctx.cfg.game_speed), 0, 2)],
		}
		render.begin_scene(r)
		ui.draw_menu_list(
			r,
			u,
			"Game Options",
			items[:],
			app.menu_sel,
			app.cursor_tick,
			"ENTER to select - ESC to return",
		)

	case .Volume_Menu:
		render.begin_scene(r)
		ui.draw_volume_screen(
			r,
			u,
			ctx.aud.sfx_volume,
			ctx.aud.music_volume,
			app.menu_sel,
			app.cursor_tick,
		)

	case .Video_Menu:
		aspect_names := [3]string{"4:3 CRT", "16:10 Square", "Stretch"}
		fs_str := "Fullscreen: On" if ctx.settings.fullscreen else "Fullscreen: Off"
		asp_buf: [32]u8
		asp_str := fmt.bprintf(
			asp_buf[:],
			"Aspect Ratio: %s",
			aspect_names[clamp(int(ctx.settings.aspect_mode), 0, 2)],
		)
		int_str := "Integer Scale: On" if ctx.settings.integer_scale else "Integer Scale: Off"
		vs_str := "VSync: On" if ctx.settings.vsync else "VSync: Off"
		sl_buf: [32]u8
		sl_str := fmt.bprintf(
			sl_buf[:],
			"Scanlines: %s",
			SCANLINE_LABELS[clamp(ctx.settings.scanlines_level, 0, len(SCANLINE_LABELS) - 1)],
		)
		sm_str := "Smooth Motion: On" if ctx.settings.smooth_motion else "Smooth Motion: Off"
		items := [6]string{fs_str, asp_str, int_str, vs_str, sl_str, sm_str}
		render.begin_scene(r)
		ui.draw_menu_list(
			r,
			u,
			"Video Settings",
			items[:],
			app.menu_sel,
			app.cursor_tick,
			"LEFT/RIGHT or ENTER to change - ESC back",
		)

	case .Input_Menu:
		gp_str := "Gamepad: On" if ctx.settings.gamepad_enabled else "Gamepad: Off"
		btn_str :=
			"Buttons: Swapped (B=Jump)" if ctx.settings.gamepad_swap_buttons else "Buttons: Normal (A=Jump)"
		dz_buf: [32]u8
		dz_str := fmt.bprintf(dz_buf[:], "Stick Deadzone: %d%%", ctx.settings.gamepad_deadzone)
		items := [4]string{"Define Key Controls", gp_str, btn_str, dz_str}
		gp_name := get_gamepad_name(ctx)
		if len(gp_name) > 26 {
			gp_name = gp_name[:26]
		}
		sub_buf: [48]u8
		sub_str := fmt.bprintf(sub_buf[:], "Gamepad: %s", gp_name)
		render.begin_scene(r)
		ui.draw_menu_list(
			r,
			u,
			"Input & Gamepad",
			items[:],
			app.menu_sel,
			app.cursor_tick,
			"LEFT/RIGHT or ENTER to change - ESC back",
			sub_str,
		)

	case .Key_Controls_Menu:
		labels: [NUM_CONTROL_ACTIONS]string
		key_names: [NUM_CONTROL_ACTIONS]string
		for act in Control_Action {
			labels[int(act)] = CONTROL_ACTION_LABELS[act]
			key_names[int(act)] = scancode_display_name(ctx.settings.key_bindings[act])
		}
		render.begin_scene(r)
		ui.draw_key_controls_screen(
			r,
			u,
			labels[:],
			key_names[:],
			app.menu_sel,
			app.waiting_for_key,
			app.cursor_tick,
		)

	case .Speed_Menu:
		items := [3]string{"Slow", "Medium", "Fast"}
		render.begin_scene(r)
		ui.draw_menu_list(
			r,
			u,
			"Select Game Speed",
			items[:],
			app.menu_sel,
			app.cursor_tick,
			"UP/DOWN to move - ENTER to select",
		)

	case .Highscores:
		names: [5]string
		scores: [5]i32
		ep := clamp(app.hs_episode, 0, 3)
		for i in 0 ..< 5 {
			names[i] = assets.cstr_slice(ctx.cfg.hs_names[ep][i][:])
			scores[i] = i32(ctx.cfg.hs_scores[ep][i])
		}
		render.begin_scene(r)
		ui.draw_highscores_screen(r, u, ep, names, scores)

	case .Enter_Highscore:
		render.begin_scene(r)
		ui.draw_enter_highscore_screen(
			r,
			u,
			app.cur_episode,
			app.world.score,
			string(app.edit_buf[:app.edit_len]),
			app.cursor_tick,
		)

	case .Save_Menu, .Restore_Menu:
		labels: [NUM_SAVEGAMES]string
		bufs: [NUM_SAVEGAMES][48]u8
		for i in 0 ..< NUM_SAVEGAMES {
			ep := int(ctx.cfg.sg_episodes[i])
			lv := int(ctx.cfg.sg_levels[i])
			name := assets.cstr_slice(ctx.cfg.sg_names[i][:])
			if ep >= 0 && ep < 4 && lv >= 0 && lv < 9 {
				labels[i] = fmt.bprintf(bufs[i][:], "%s (E%dL%d)", name, ep + 1, lv + 1)
			} else {
				labels[i] = "Empty"
			}
		}
		render.begin_scene(r)
		ui.draw_save_restore_screen(
			r,
			u,
			app.state == .Save_Menu,
			app.menu_sel,
			labels,
			app.editing_name,
			string(app.edit_buf[:app.edit_len]),
			app.cursor_tick,
		)

	case .Text_Page_View:
		render.begin_scene(r)
		ui.draw_text_page(r, u, &app.text_page_data, app.text_page_idx, app.text_page_count)

	case .Playing:
		alpha := app.render_alpha if ctx.settings.smooth_motion else f32(1.0)
		game.world_render(r, app.world, &app.gfx, &app.sprites, alpha)
		switch app.overlay {
		case .None:
			if app.toast_timer > 0 && len(app.toast_text) > 0 {
				ui.draw_ingame_text_centered(r, &u.font, 8, app.toast_text)
			}
		case .Paused:
			ui.draw_paused_overlay(r, u)
		case .Wizard_Message:
			ui.draw_wizard_overlay(r, u, app.world, app.wizard_msg_idx)
		case .Crystal_Popup:
			ui.draw_crystal_popup(r, u)
		}

	case .Ingame_Menu:
		items := [7]string {
			"How to play Hocus Pocus",
			"Abandon level & restart",
			"Save this game",
			"Restore an old game",
			"Change game options",
			"Back to the action!",
			"Quit to Main Menu",
		}
		render.begin_scene(r)
		ui.draw_menu_list(
			r,
			u,
			"",
			items[:],
			app.menu_sel,
			app.cursor_tick,
			"UP/DOWN to move - ENTER to select",
		)

	case .Intermission:
		render.begin_scene(r)
		ui.draw_intermission_screen(r, u, app.intermission)
	}
}
