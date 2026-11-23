package game

import "../assets"
import "core:strings"

Demo_Frame :: struct #packed {
	up:    u8,
	left:  u8,
	right: u8,
	fire:  u8,
	jump:  u8,
	down:  u8,
}
#assert(size_of(Demo_Frame) == 6)

Demo_Player :: struct {
	frames:    []Demo_Frame,
	index:     int,
	level_idx: int,
	active:    bool,
}

load_demo :: proc(dp: ^Demo_Player, dat: ^assets.Dat_File, demo_num: int) -> bool {
	if dp == nil || dat == nil || demo_num < 0 || demo_num >= 5 {
		return false
	}
	chunk, ok := assets.get_chunk_offset(dat, .DEMO1_DMO, demo_num)
	if !ok || len(chunk) < 2 {
		return false
	}
	count := int((^i16le)(raw_data(chunk))^)
	if count <= 0 || 2 + count * size_of(Demo_Frame) > len(chunk) {
		return false
	}

	dp.frames = ([^]Demo_Frame)(raw_data(chunk[2:]))[:count]
	dp.index = 0
	dp.level_idx = demo_num * 2
	dp.active = true
	return true
}

demo_stop :: proc(dp: ^Demo_Player) {
	dp^ = {}
}

demo_next_input :: proc(dp: ^Demo_Player, inp: ^Input_State) -> bool {
	if dp == nil || !dp.active || dp.index >= len(dp.frames) {
		return false
	}

	f := dp.frames[dp.index]
	dp.index += 1

	inp.fire_down = f.fire != 0
	inp.jump_down = f.jump != 0
	inp.left = f.left != 0
	inp.right = f.right != 0
	inp.use_down = f.up != 0
	inp.up = false
	inp.down = false
	inp.fire_up = !inp.fire_down
	inp.use_up = !inp.use_down
	inp.jump_up = !inp.jump_down

	return true
}

Cheat_Detector :: struct {
	buf: [16]u8,
	len: int,
}

cheat_reset :: proc(cd: ^Cheat_Detector) {
	cd^ = {}
}

cheat_feed_char :: proc(cd: ^Cheat_Detector, ch: u8, w: ^World, is_registered: bool) -> string {
	c := ch
	if c >= 'a' && c <= 'z' {
		c -= 32
	}
	if c < 'A' || c > 'Z' {
		return ""
	}

	if cd.len < len(cd.buf) {
		cd.buf[cd.len] = c
		cd.len += 1
	} else {
		for i in 0 ..< len(cd.buf) - 1 {
			cd.buf[i] = cd.buf[i + 1]
		}
		cd.buf[len(cd.buf) - 1] = c
	}

	typed := string(cd.buf[:cd.len])

	if strings.has_suffix(typed, "FEELGOOD") {
		w.player_health = 100
		cheat_reset(cd)
		world_play_sound(w, SFX_HEAL)
		return "FEELGOOD: Full Health!"
	}
	if strings.has_suffix(typed, "BLAKE") {
		w.got_key1 = true
		w.got_key2 = true
		cheat_reset(cd)
		world_play_sound(w, SFX_YAHOO)
		return "BLAKE: All Keys Granted!"
	}
	if is_registered && strings.has_suffix(typed, "QUARK") {
		if w.rapid_fire_countdown == 0 {
			w.old_firepower = w.player_firepower
			w.player_firepower = 5
		}
		w.rapid_fire_countdown = 600
		cheat_reset(cd)
		world_play_sound(w, SFX_YAHOO)
		return "QUARK: Rapid Fire!"
	}
	if is_registered && strings.has_suffix(typed, "BANANA") {
		if w.powershots_left == 0 {
			w.powershots_left = 3
		}
		w.tick1 = 1
		w.tick5 = 5
		cheat_reset(cd)
		world_play_sound(w, SFX_YAHOO)
		return "BANANA: Laser Shots!"
	}

	return ""
}
