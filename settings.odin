package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "render"
import sdl "vendor:sdl3"

Control_Action :: enum {
	Left,
	Right,
	Jump,
	Fire,
	Up,
	Down,
	Scroll_Up,
	Scroll_Down,
}

NUM_CONTROL_ACTIONS :: len(Control_Action)

CONTROL_ACTION_LABELS := [Control_Action]string {
	.Left        = "Move Left",
	.Right       = "Move Right",
	.Jump        = "Jump",
	.Fire        = "Fire / Cast",
	.Up          = "Up / Use",
	.Down        = "Down / Crouch",
	.Scroll_Up   = "Look Up",
	.Scroll_Down = "Look Down",
}

CONTROL_ACTION_KEYS := [Control_Action]string {
	.Left        = "key_left",
	.Right       = "key_right",
	.Jump        = "key_jump",
	.Fire        = "key_fire",
	.Up          = "key_up",
	.Down        = "key_down",
	.Scroll_Up   = "key_scroll_up",
	.Scroll_Down = "key_scroll_down",
}

SCANLINE_LEVELS := [4]f32{0.0, 0.25, 0.50, 0.75}
SCANLINE_LABELS := [4]string{"Off", "25%", "50%", "75%"}
DEADZONE_OPTIONS := [4]int{15, 25, 35, 45}

User_Settings :: struct {
	fullscreen:           bool,
	aspect_mode:          render.Aspect_Mode,
	integer_scale:        bool,
	vsync:                bool,
	scanlines_level:      int,
	smooth_motion:        bool,
	key_bindings:         [Control_Action]sdl.Scancode,
	gamepad_enabled:      bool,
	gamepad_swap_buttons: bool,
	gamepad_deadzone:     int,
}

reset_default_key_bindings :: proc(s: ^User_Settings) {
	s.key_bindings = {
		.Left        = .LEFT,
		.Right       = .RIGHT,
		.Jump        = .SPACE,
		.Fire        = .LALT,
		.Up          = .UP,
		.Down        = .DOWN,
		.Scroll_Up   = .PAGEUP,
		.Scroll_Down = .PAGEDOWN,
	}
}

init_default_settings :: proc(s: ^User_Settings) {
	s^ = {}
	s.fullscreen = false
	s.aspect_mode = .CRT_4_3
	s.integer_scale = false
	s.vsync = true
	s.scanlines_level = 0
	s.smooth_motion = false

	reset_default_key_bindings(s)
	s.gamepad_enabled = true
	s.gamepad_swap_buttons = false
	s.gamepad_deadzone = 25
}

scancode_display_name :: proc(sc: sdl.Scancode) -> string {
	if sc == .UNKNOWN {
		return "---"
	}
	cname := sdl.GetScancodeName(sc)
	if cname == nil {
		return "---"
	}
	name := string(cname)
	if len(name) == 0 {
		return "---"
	}
	return name
}

serialize_settings :: proc(s: ^User_Settings, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	fmt.sbprintfln(&b, "fullscreen=%d", 1 if s.fullscreen else 0)
	fmt.sbprintfln(&b, "aspect_mode=%d", int(s.aspect_mode))
	fmt.sbprintfln(&b, "integer_scale=%d", 1 if s.integer_scale else 0)
	fmt.sbprintfln(&b, "vsync=%d", 1 if s.vsync else 0)
	fmt.sbprintfln(&b, "scanlines_level=%d", clamp(s.scanlines_level, 0, len(SCANLINE_LEVELS) - 1))
	fmt.sbprintfln(&b, "smooth_motion=%d", 1 if s.smooth_motion else 0)
	fmt.sbprintfln(&b, "gamepad_enabled=%d", 1 if s.gamepad_enabled else 0)
	fmt.sbprintfln(&b, "gamepad_swap_buttons=%d", 1 if s.gamepad_swap_buttons else 0)
	fmt.sbprintfln(&b, "gamepad_deadzone=%d", s.gamepad_deadzone)
	for act in Control_Action {
		fmt.sbprintfln(&b, "%s=%d", CONTROL_ACTION_KEYS[act], int(s.key_bindings[act]))
	}
	return strings.to_string(b)
}

parse_settings :: proc(s: ^User_Settings, content: string) {
	lines := strings.split_lines(content, context.temp_allocator)
	for raw_line in lines {
		line := strings.trim_space(raw_line)
		if len(line) == 0 || line[0] == '#' {
			continue
		}
		eq := strings.index_byte(line, '=')
		if eq <= 0 {
			continue
		}
		key := strings.trim_space(line[:eq])
		val_str := strings.trim_space(line[eq + 1:])
		val, ok := strconv.parse_int(val_str)
		if !ok {
			continue
		}

		switch key {
		case "fullscreen":
			s.fullscreen = val != 0
		case "aspect_mode":
			if val >= int(render.Aspect_Mode.CRT_4_3) && val <= int(render.Aspect_Mode.Stretch) {
				s.aspect_mode = render.Aspect_Mode(val)
			}
		case "integer_scale":
			s.integer_scale = val != 0
		case "vsync":
			s.vsync = val != 0
		case "scanlines_level":
			s.scanlines_level = clamp(val, 0, len(SCANLINE_LEVELS) - 1)
		case "smooth_motion":
			s.smooth_motion = val != 0
		case "gamepad_enabled":
			s.gamepad_enabled = val != 0
		case "gamepad_swap_buttons":
			s.gamepad_swap_buttons = val != 0
		case "gamepad_deadzone":
			if val >= 5 && val <= 90 {
				s.gamepad_deadzone = val
			}
		case:
			for act in Control_Action {
				if key == CONTROL_ACTION_KEYS[act] {
					if val > 0 && val <= int(max(sdl.Scancode)) {
						s.key_bindings[act] = sdl.Scancode(val)
					}
					break
				}
			}
		}
	}
}

load_user_settings :: proc(s: ^User_Settings, path: string) -> bool {
	init_default_settings(s)
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil {
		return false
	}
	parse_settings(s, string(data))
	return true
}

save_user_settings :: proc(s: ^User_Settings, path: string) -> bool {
	text := serialize_settings(s, context.temp_allocator)
	err := os.write_entire_file(path, transmute([]byte)text)
	return err == nil
}
