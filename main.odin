package main

import "assets"
import "audio"
import "core:fmt"
import "core:mem"
import "game"
import "render"
import "ui"
import sdl "vendor:sdl3"

SPEED_TICKS := [3]f32{8.0, 7.0, 6.0}

App_State :: enum {
	Intro_Apogee,
	Intro_Title,
	Main_Menu,
	Episode_Menu,
	Skill_Menu,
	Options_Menu,
	Volume_Menu,
	Video_Menu,
	Input_Menu,
	Key_Controls_Menu,
	Speed_Menu,
	Highscores,
	Enter_Highscore,
	Save_Menu,
	Restore_Menu,
	Help_Screen,
	Text_Page_View,
	Playing,
	Ingame_Menu,
	Intermission,
	Warp_Screen,
}

Text_Page_Group :: enum {
	Story,
	Ordering,
	Finale_1,
	Finale_2,
	Finale_3,
	Finale_4,
}

Playing_Overlay :: enum {
	None,
	Paused,
	Wizard_Message,
	Crystal_Popup,
}

App :: struct {
	ctx:             GameContext,
	world:           ^game.World,
	gfx:             game.Level_Graphics,
	sprites:         game.Sprite_Bank,
	cur_episode:     int,
	cur_level:       int,
	cur_skill:       int,
	inp:             game.Input_State,
	overlay:         Playing_Overlay,
	wizard_msg_idx:  int,
	level_elapsed_s: f32,
	render_alpha:    f32,
	state:           App_State,
	return_state:    App_State,
	running:         bool,
	waiting_for_key: bool,
	gp_nav_dir_x:    int,
	gp_nav_dir_y:    int,
	gp_nav_timer:    f32,
	demo:            game.Demo_Player,
	next_demo_num:   int,
	menu_idle_s:     f32,
	cheat:           game.Cheat_Detector,
	toast_text:      string,
	toast_timer:     f32,
	menu_sel:        int,
	cursor_tick:     int,
	state_timer:     f32,
	warp_phase:      int,
	help_page:       int,
	hs_episode:      int,
	hs_pending_rank: int,
	text_group:      Text_Page_Group,
	text_page_idx:   int,
	text_page_count: int,
	text_page_data:  assets.Text_Page,
	editing_name:    bool,
	edit_buf:        [MAX_NAME_LEN]u8,
	edit_len:        int,
	intermission:    ui.Intermission_Info,
}

world_sound_callback :: proc(userdata: rawptr, sfx_id: int) {
	if userdata == nil do return
	audio.play_sfx((^audio.Audio_System)(userdata), sfx_id)
}

enter_intro_apogee :: proc(app: ^App) {
	ctx := &app.ctx
	app.state = .Intro_Apogee
	app.state_timer = 0
	if ui.load_screen_pcx(ctx.ui_assets, ctx.ren, &ctx.dat, .APOGEE_PCX) {
		render.set_palette(ctx.ren, ctx.ui_assets.screen_pal)
	}
	_ = audio.play_music_chunk(ctx.aud, &ctx.dat, .FANFARE_MID, looping = false)
	render.fade_from_black(ctx.ren, 0.5)
}

enter_intro_title :: proc(app: ^App) {
	ctx := &app.ctx
	app.state = .Intro_Title
	app.state_timer = 0
	if ui.load_screen_pcx(ctx.ui_assets, ctx.ren, &ctx.dat, .TITLE_PCX) {
		render.set_palette(ctx.ren, ctx.ui_assets.screen_pal)
	}
	_ = audio.play_music_chunk(ctx.aud, &ctx.dat, .MUSIC03_MID, looping = true)
	audio.play_voc_chunk(ctx.aud, &ctx.dat, .SOUND01_VOC)
	render.fade_from_black(ctx.ren, 0.7)
}

enter_main_menu :: proc(app: ^App, restart_music := false) {
	ctx := &app.ctx
	app.state = .Main_Menu
	app.menu_sel = 0
	app.menu_idle_s = 0
	app.editing_name = false
	game.demo_stop(&app.demo)
	render.set_palette(ctx.ren, ctx.ui_assets.menu_palette)
	render.fade_from_black(ctx.ren, 0.35)
	if restart_music {
		_ = audio.play_music_chunk(ctx.aud, &ctx.dat, .MUSIC03_MID, looping = true)
	}
}

start_demo :: proc(app: ^App, demo_num: int) {
	if !game.load_demo(&app.demo, &app.ctx.dat, demo_num) {
		return
	}
	if !start_level(app, 0, app.demo.level_idx, 1, 0, false) {
		game.demo_stop(&app.demo)
		return
	}
	app.toast_text = "DEMO MODE - Press any key"
	app.toast_timer = 3.0
}

enter_text_group :: proc(app: ^App, group: Text_Page_Group, ret: App_State) {
	ctx := &app.ctx
	app.state = .Text_Page_View
	app.return_state = ret
	app.text_group = group
	app.text_page_idx = 0
	switch group {
	case .Story:
		app.text_page_count = 10
	case .Ordering:
		app.text_page_count = 2 if assets.is_registered(&ctx.dat) else 7
	case .Finale_1:
		app.text_page_count = 2
	case .Finale_2:
		app.text_page_count = 2
	case .Finale_3:
		app.text_page_count = 4
	case .Finale_4:
		app.text_page_count = 2
	}
	load_current_text_page(app)
	render.set_palette(ctx.ren, ctx.ui_assets.menu_palette)
	render.fade_from_black(ctx.ren, 0.35)
}

load_current_text_page :: proc(app: ^App) {
	ctx := &app.ctx
	idx := app.text_page_idx
	base := assets.Chunk_ID.STORY01_PAG
	pic := ui.Text_Pic_Ref{.NONE, 0, 0}

	switch app.text_group {
	case .Story:
		base = .STORY01_PAG
		if idx < len(ui.STORY_PICS) do pic = ui.STORY_PICS[idx]
	case .Ordering:
		base = .ORDER_R1_PAG if assets.is_registered(&ctx.dat) else .ORDER1_PAG
	case .Finale_1:
		base = .E1END1_PAG
		if idx < len(ui.FINALE1_PICS) do pic = ui.FINALE1_PICS[idx]
	case .Finale_2:
		base = .E2END1_PAG
		if idx < len(ui.FINALE2_PICS) do pic = ui.FINALE2_PICS[idx]
	case .Finale_3:
		base = .E3END1_PAG
		if idx < len(ui.FINALE3_PICS) do pic = ui.FINALE3_PICS[idx]
	case .Finale_4:
		base = .E4END1_PAG
		if idx < len(ui.FINALE4_PICS) do pic = ui.FINALE4_PICS[idx]
	}

	_ = assets.load_text_page_offset(&app.text_page_data, &ctx.dat, base, idx)
	ui.load_page_pic(ctx.ui_assets, ctx.ren, &ctx.dat, pic.chunk, pic.x4, pic.y)
}

enter_help :: proc(app: ^App, ret: App_State) {
	app.state = .Help_Screen
	app.return_state = ret
	app.help_page = 0
	load_help_page(app)
}

load_help_page :: proc(app: ^App) {
	ctx := &app.ctx
	pages := [3]assets.Chunk_ID{.HELP1_K_PCX, .HELP2_PCX, .HELP3_PCX}
	id := pages[clamp(app.help_page, 0, 2)]
	if ui.load_screen_pcx(ctx.ui_assets, ctx.ren, &ctx.dat, id) {
		render.set_palette(ctx.ren, ctx.ui_assets.screen_pal)
	}
	render.fade_from_black(ctx.ren, 0.3)
}

start_level :: proc(
	app: ^App,
	episode, level_idx, skill: int,
	carry_score: i32,
	show_crystal_popup := false,
) -> bool {
	ctx := &app.ctx
	if !game.world_init_level(app.world, &ctx.dat, nil, episode, level_idx, skill, carry_score) {
		fmt.eprintfln("Failed to initialize E%dL%d", episode + 1, level_idx + 1)
		return false
	}
	if !game.load_level_graphics(&app.gfx, ctx.ren, &ctx.dat, &app.world.level) {
		return false
	}
	if !game.load_level_sprites(&app.sprites, ctx.ren, &ctx.dat, &app.world.level) {
		return false
	}

	if app.sprites.slot_loaded[game.SPR_PLAYER] {
		app.world.player_frame = int(app.sprites.infos[game.SPR_PLAYER].stand_frame)
	}
	if app.world.actors[0].type == 99 && app.sprites.slot_loaded[game.SPR_ENEMY_0] {
		app.world.actors[0].width = int(app.sprites.infos[game.SPR_ENEMY_0].width)
		app.world.actors[0].height = int(app.sprites.infos[game.SPR_ENEMY_0].height)
	}

	app.cur_episode = episode
	app.cur_level = level_idx
	app.cur_skill = skill
	app.state = .Playing
	app.overlay = .Crystal_Popup if show_crystal_popup else .None
	app.wizard_msg_idx = -1
	app.level_elapsed_s = 0
	app.render_alpha = 1.0
	app.toast_timer = 0
	game.cheat_reset(&app.cheat)
	game.init_input_state(&app.inp)

	music_num := game.LEVEL_MUSIC_NUMBERS[episode][level_idx]
	_ = audio.play_level_music(ctx.aud, &ctx.dat, music_num, looping = true)

	render.set_palette(ctx.ren, app.gfx.palette)
	render.fade_from_black(ctx.ren, 0.4)
	return true
}

enter_intermission :: proc(app: ^App, won: bool) {
	ctx := &app.ctx
	app.state = .Intermission
	app.intermission = ui.compute_intermission(
		won,
		app.cur_episode,
		app.cur_level,
		app.cur_skill,
		app.world.treasure_found,
		app.world.level.treasure_total,
		int(app.level_elapsed_s),
	)
	app.world.score += app.intermission.treasure_bonus + app.intermission.time_bonus

	render.set_palette(ctx.ren, ctx.ui_assets.menu_palette)
	_ = audio.play_music_chunk(ctx.aud, &ctx.dat, .MUSIC03_MID, looping = true)
	render.fade_from_black(ctx.ren, 0.4)
}

enter_warp :: proc(app: ^App) {
	ctx := &app.ctx
	app.state = .Warp_Screen
	app.warp_phase = 0
	app.state_timer = 0
	if ui.load_screen_pcx(ctx.ui_assets, ctx.ren, &ctx.dat, .WARP_PCX) {
		render.set_palette(ctx.ren, ctx.ui_assets.screen_pal)
	}
	audio.play_voc_chunk(ctx.aud, &ctx.dat, .SOUND04_VOC)
	render.fade_from_black(ctx.ren, 1.0)
}

finish_episode_or_quit_to_menu :: proc(app: ^App) {
	ctx := &app.ctx
	rank := check_highscore_rank(&ctx.cfg, app.cur_episode, app.world.score)
	if rank >= 0 {
		app.state = .Enter_Highscore
		app.hs_pending_rank = rank
		app.edit_len = 0
		render.set_palette(ctx.ren, ctx.ui_assets.menu_palette)
		render.fade_from_black(ctx.ren, 0.3)
	} else {
		enter_main_menu(app, restart_music = true)
	}
}

@(private)
poll_events :: proc(app: ^App) {
	ev: sdl.Event
	for sdl.PollEvent(&ev) {
		#partial switch ev.type {
		case .QUIT:
			app.running = false
		case .WINDOW_FOCUS_LOST, .WINDOW_MINIMIZED:
			if app.state == .Playing && !app.demo.active && app.overlay == .None {
				app.overlay = .Paused
				game.init_input_state(&app.inp)
			}
		case .KEY_DOWN:
			allow_repeat :=
				app.state == .Volume_Menu || app.editing_name || app.state == .Enter_Highscore
			if !ev.key.repeat || allow_repeat {
				handle_key_down(app, ev.key.scancode, ev.key.key)
			}
		case .GAMEPAD_ADDED:
			if open_gamepad_by_id(&app.ctx, ev.gdevice.which) {
				fmt.printfln("Gamepad connected: %s", get_gamepad_name(&app.ctx))
				if app.state == .Playing {
					app.toast_text = "Gamepad connected"
					app.toast_timer = 2.0
				}
			}
		case .GAMEPAD_REMOVED:
			if close_gamepad_if_matches(&app.ctx, ev.gdevice.which) {
				fmt.println("Gamepad disconnected")
				if app.state == .Playing {
					app.toast_text = "Gamepad disconnected"
					app.toast_timer = 2.0
				}
			}
		case .GAMEPAD_BUTTON_DOWN:
			handle_gamepad_button_down(app, sdl.GamepadButton(ev.gbutton.button))
		}
	}
}

@(private)
update_timed_states :: proc(app: ^App, dt: f32) {
	#partial switch app.state {
	case .Intro_Apogee:
		app.state_timer += dt
		if app.state_timer >= 6.0 {
			enter_intro_title(app)
		}
	case .Intro_Title:
		app.state_timer += dt
		if app.state_timer >= 4.5 {
			enter_main_menu(app, restart_music = false)
		}
	case .Warp_Screen:
		app.state_timer += dt
		if app.warp_phase == 0 && app.state_timer >= 1.8 {
			app.warp_phase = 1
			render.fade_to_white(app.ctx.ren, 1.2)
		} else if app.warp_phase == 1 && app.state_timer >= 3.2 {
			app.warp_phase = 2
			render.fade_to_black(app.ctx.ren, 0.5)
		} else if app.warp_phase == 2 && app.state_timer >= 3.8 {
			groups := [4]Text_Page_Group{.Finale_1, .Finale_2, .Finale_3, .Finale_4}
			enter_text_group(app, groups[clamp(app.cur_episode, 0, 3)], .Enter_Highscore)
		}
	case .Main_Menu:
		app.menu_idle_s += dt
		if app.menu_idle_s >= 20.0 {
			start_demo(app, app.next_demo_num)
			app.next_demo_num = (app.next_demo_num + 1) % 5
		}
	}
}

@(private)
step_gameplay :: proc(app: ^App, dt: f32, game_acc: ^f32) {
	if app.state != .Playing || app.overlay != .None {
		game_acc^ = 0.0
		return
	}

	if !app.demo.active {
		locked := app.world.player_death_countdown > 0 || app.world.level_done_countdown > 0
		update_gameplay_input(&app.inp, &app.ctx, locked)
	}

	logic_dt := SPEED_TICKS[clamp(int(app.ctx.cfg.game_speed), 0, 2)] / 140.0
	game_acc^ += dt
	for game_acc^ >= logic_dt {
		game_acc^ -= logic_dt
		app.level_elapsed_s += logic_dt

		demo_ptr := &app.demo if app.demo.active else nil
		game.world_step(app.world, &app.inp, &app.sprites, demo_ptr)

		if app.demo.active {
			app.world.active_wizard_msg = -1
			if app.demo.index >= len(app.demo.frames) || app.world.status != .Playing {
				enter_main_menu(app, restart_music = true)
				break
			}
		} else {
			if app.world.active_wizard_msg >= 0 {
				app.wizard_msg_idx = app.world.active_wizard_msg
				app.world.active_wizard_msg = -1
				app.overlay = .Wizard_Message
				break
			}
			if app.world.status == .Won {
				enter_intermission(app, true)
				break
			}
			if app.world.status == .Died {
				enter_intermission(app, false)
				break
			}
		}
	}
	app.render_alpha =
		clamp(game_acc^ / logic_dt, 0.0, 1.0) if app.ctx.settings.smooth_motion else 1.0
}

main :: proc() {
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)
		defer
		{
			if len(track.allocation_map) > 0 {
				fmt.eprintfln("=== %v allocations not freed ===", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintfln(" - %v bytes @ %v", entry.size, entry.location)
				}
			}
			if len(track.bad_free_array) > 0 {
				fmt.eprintfln("=== %v bad frees ===", len(track.bad_free_array))
				for entry in track.bad_free_array {
					fmt.eprintfln(" - %p @ %v", entry.memory, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	} else {
		_ = mem.Allocator{}
	}
	defer free_all(context.temp_allocator)

	if !sdl.Init({.VIDEO, .AUDIO, .GAMEPAD}) {
		fmt.eprintln("SDL_Init failed:", sdl.GetError())
		return
	}
	defer sdl.Quit()

	app := new(App)
	defer free(app)

	if !setup_game_context(&app.ctx) {
		return
	}
	defer destroy_game_context(&app.ctx)

	app.world = new(game.World)
	defer free(app.world)
	app.world.sound_userdata = app.ctx.aud
	app.world.on_sound = world_sound_callback
	defer game.destroy_level_graphics(&app.gfx, app.ctx.ren)
	defer game.destroy_sprite_bank(&app.sprites, app.ctx.ren)

	app.cur_skill = 1
	app.running = true
	enter_intro_apogee(app)

	game_acc: f32 = 0.0
	ui_acc: f32 = 0.0
	UI_DT :: f32(1.0 / 60.0)
	last_ticks := sdl.GetTicksNS()

	for app.running {
		now_ticks := sdl.GetTicksNS()
		dt := min(f32(now_ticks - last_ticks) / 1_000_000_000.0, 0.1)
		last_ticks = now_ticks

		poll_events(app)
		update_gamepad_menu_nav(app, dt)
		update_timed_states(app, dt)

		if app.toast_timer > 0 {
			app.toast_timer = max(app.toast_timer - dt, 0)
		}

		ui_acc += dt
		for ui_acc >= UI_DT {
			ui_acc -= UI_DT
			app.cursor_tick = (app.cursor_tick + 1) % 40
			if app.state != .Playing {
				ui.update_starfield(&app.ctx.ui_assets.starfield)
			}
		}

		step_gameplay(app, dt, &game_acc)

		render.update_fade(app.ctx.ren, dt)
		render_app(app)
		_ = render.present_frame(app.ctx.ren)
		free_all(context.temp_allocator)
	}
}
