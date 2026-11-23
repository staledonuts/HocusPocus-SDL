package main

import "assets"
import "audio"
import "core:c"
import "core:fmt"
import "render"
import "ui"
import sdl "vendor:sdl3"

DEFAULT_WIN_WIDTH :: i32(1280)
DEFAULT_WIN_HEIGHT :: i32(720)

GameContext :: struct {
	window:     ^sdl.Window,
	gpu_device: ^sdl.GPUDevice,
	gamepad:    ^sdl.Gamepad,
	paths:      App_Paths,
	dat:        assets.Dat_File,
	aud:        ^audio.Audio_System,
	ren:        ^render.GPU_Renderer,
	ui_assets:  ^ui.UI_Assets,
	cfg:        Game_Config,
	settings:   User_Settings,
}

setup_game_context :: proc(ctx: ^GameContext) -> bool {
	if ctx == nil {
		return false
	}
	ctx^ = {}

	ctx.window = sdl.CreateWindow(
		"Hocus Pocus SDL",
		DEFAULT_WIN_WIDTH,
		DEFAULT_WIN_HEIGHT,
		{.RESIZABLE},
	)
	if ctx.window == nil {
		fmt.eprintln("CreateWindow failed:", sdl.GetError())
		return false
	}

	debug_gpu := false
	gpu_props := sdl.CreateProperties()
	defer sdl.DestroyProperties(gpu_props)
	sdl.SetBooleanProperty(gpu_props, sdl.PROP_GPU_DEVICE_CREATE_SHADERS_SPIRV_BOOLEAN, true)
	sdl.SetBooleanProperty(gpu_props, sdl.PROP_GPU_DEVICE_CREATE_DEBUGMODE_BOOLEAN, debug_gpu)
	ctx.gpu_device = sdl.CreateGPUDeviceWithProperties(gpu_props)
	if ctx.gpu_device == nil {
		fmt.eprintln("CreateGPUDeviceWithProperties failed:", sdl.GetError())
		destroy_game_context(ctx)
		return false
	}

	if !sdl.ClaimWindowForGPUDevice(ctx.gpu_device, ctx.window) {
		fmt.eprintln("ClaimWindowForGPUDevice failed:", sdl.GetError())
		destroy_game_context(ctx)
		return false
	}
	_ = sdl.SetGPUSwapchainParameters(ctx.gpu_device, ctx.window, .SDR, .VSYNC)

	ctx.gamepad = init_gamepad()

	init_app_paths(&ctx.paths)
	if len(ctx.paths.dat_path) == 0 {
		fmt.eprintfln(
			"Could not find HOCUS.DAT (checked %s and %s/data)",
			ctx.paths.user_dir,
			ctx.paths.base_dir,
		)
		destroy_game_context(ctx)
		return false
	}

	dat, dat_ok := assets.open_dat(ctx.paths.dat_path)
	if !dat_ok {
		fmt.eprintfln("Could not open HOCUS.DAT at %s", ctx.paths.dat_path)
		destroy_game_context(ctx)
		return false
	}
	ctx.dat = dat

	sav_ok := load_game_config(&ctx.cfg, ctx.paths.sav_path)
	settings_ok := load_user_settings(&ctx.settings, ctx.paths.settings_path)

	fmt.printfln(
		"Data=%s (%v, %d chunks) | user_dir=%s | save(loaded=%v) | cfg(loaded=%v) | gamepad=%s",
		ctx.paths.dat_path,
		ctx.dat.version,
		len(ctx.dat.fat),
		ctx.paths.user_dir,
		sav_ok,
		settings_ok,
		get_gamepad_name(ctx),
	)

	ctx.aud = new(audio.Audio_System)
	_ = audio.init_audio(ctx.aud, &ctx.dat)
	sync_audio_from_config(ctx)

	ctx.ren = new(render.GPU_Renderer)
	if !render.init_renderer(ctx.ren, ctx.gpu_device, ctx.window) {
		fmt.eprintln("init_renderer failed:", sdl.GetError())
		destroy_game_context(ctx)
		return false
	}
	apply_video_settings(ctx)

	ctx.ui_assets = new(ui.UI_Assets)
	if !ui.init_ui_assets(ctx.ui_assets, ctx.ren, &ctx.dat) {
		fmt.eprintln("init_ui_assets failed")
		destroy_game_context(ctx)
		return false
	}

	return true
}

destroy_game_context :: proc(ctx: ^GameContext) {
	if ctx == nil {
		return
	}

	if ctx.ui_assets != nil {
		ui.destroy_ui_assets(ctx.ui_assets, ctx.ren)
		free(ctx.ui_assets)
		ctx.ui_assets = nil
	}

	if ctx.ren != nil {
		render.destroy_renderer(ctx.ren)
		free(ctx.ren)
		ctx.ren = nil
	}

	if ctx.aud != nil {
		audio.destroy_audio(ctx.aud)
		free(ctx.aud)
		ctx.aud = nil
	}

	destroy_app_paths(&ctx.paths)
	assets.close_dat(&ctx.dat)

	if ctx.gamepad != nil {
		sdl.CloseGamepad(ctx.gamepad)
		ctx.gamepad = nil
	}

	if ctx.gpu_device != nil {
		if ctx.window != nil {
			sdl.ReleaseWindowFromGPUDevice(ctx.gpu_device, ctx.window)
		}
		sdl.DestroyGPUDevice(ctx.gpu_device)
		ctx.gpu_device = nil
	}

	if ctx.window != nil {
		sdl.DestroyWindow(ctx.window)
		ctx.window = nil
	}
}

sync_audio_from_config :: proc(ctx: ^GameContext) {
	if ctx == nil || ctx.aud == nil do return
	audio.set_sfx_enabled(ctx.aud, ctx.cfg.sound_on != 0)
	audio.set_music_enabled(ctx.aud, ctx.cfg.music_on != 0)
	audio.set_sfx_volume(ctx.aud, f32(ctx.cfg.sound_volume) / 255.0)
	audio.set_music_volume(ctx.aud, f32(ctx.cfg.music_volume) / 255.0)
}

apply_video_settings :: proc(ctx: ^GameContext) {
	if ctx == nil do return
	if ctx.window != nil {
		_ = sdl.SetWindowFullscreen(ctx.window, ctx.settings.fullscreen)
	}
	if ctx.ren != nil {
		ctx.ren.aspect_mode = ctx.settings.aspect_mode
		ctx.ren.integer_scale = ctx.settings.integer_scale
		ctx.ren.scanlines =
			SCANLINE_LEVELS[clamp(ctx.settings.scanlines_level, 0, len(SCANLINE_LEVELS) - 1)]
		render.set_vsync(ctx.ren, ctx.settings.vsync)
	}
}

save_config :: proc(ctx: ^GameContext) -> bool {
	if ctx == nil || len(ctx.paths.sav_path) == 0 do return false
	return save_game_config(&ctx.cfg, ctx.paths.sav_path)
}

save_settings :: proc(ctx: ^GameContext) -> bool {
	if ctx == nil || len(ctx.paths.settings_path) == 0 do return false
	return save_user_settings(&ctx.settings, ctx.paths.settings_path)
}

open_gamepad_by_id :: proc(ctx: ^GameContext, id: sdl.JoystickID) -> bool {
	if ctx == nil || ctx.gamepad != nil {
		return false
	}
	gp := sdl.OpenGamepad(id)
	if gp == nil {
		return false
	}
	ctx.gamepad = gp
	return true
}

close_gamepad_if_matches :: proc(ctx: ^GameContext, id: sdl.JoystickID) -> bool {
	if ctx == nil || ctx.gamepad == nil {
		return false
	}
	if sdl.GetGamepadID(ctx.gamepad) != id {
		return false
	}
	sdl.CloseGamepad(ctx.gamepad)
	ctx.gamepad = init_gamepad()
	return true
}

get_gamepad_name :: proc(ctx: ^GameContext) -> string {
	if ctx == nil || ctx.gamepad == nil {
		return "None detected"
	}
	cname := sdl.GetGamepadName(ctx.gamepad)
	if cname == nil {
		return "Gamepad"
	}
	name := string(cname)
	if len(name) == 0 {
		return "Gamepad"
	}
	return name
}

@(private)
init_gamepad :: proc() -> ^sdl.Gamepad {
	gamepad: ^sdl.Gamepad = nil
	num_gamepads: c.int
	gamepad_ids := sdl.GetGamepads(&num_gamepads)
	if gamepad_ids != nil {
		if num_gamepads > 0 {
			for i in 0 ..< int(num_gamepads) {
				gp := sdl.OpenGamepad(gamepad_ids[i])
				if gp != nil {
					gamepad = gp
					break
				}
			}
		}
		sdl.free(gamepad_ids)
	}
	return gamepad
}
