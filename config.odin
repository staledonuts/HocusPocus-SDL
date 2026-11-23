package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"

NUM_SAVEGAMES :: 9
NUM_EPISODES :: 4
NUM_HIGHSCORES :: 5
MAX_NAME_LEN :: 25
NUM_CONTROLS :: 8

Game_Config :: struct #packed {
	sound_on:             u16le,
	music_on:             u16le,
	control_mode:         u16le,
	game_speed:           u16le,
	joy_lo_x:             u16le,
	joy_mi_x:             u16le,
	joy_hi_x:             u16le,
	joy_lo_y:             u16le,
	joy_mi_y:             u16le,
	joy_hi_y:             u16le,
	joy_fire_button:      u16le,
	control_keys:         [NUM_CONTROLS]u8,
	sg_episodes:          [NUM_SAVEGAMES]i16le,
	sg_levels:            [NUM_SAVEGAMES]i16le,
	sg_skill:             [NUM_SAVEGAMES]i16le,
	sg_names:             [NUM_SAVEGAMES][MAX_NAME_LEN + 1]u8,
	_unused:              [10]u8,
	sg_scores:            [NUM_SAVEGAMES]i32le,
	hs_names:             [NUM_EPISODES][NUM_HIGHSCORES][MAX_NAME_LEN + 1]u8,
	hs_scores:            [NUM_EPISODES][NUM_HIGHSCORES]i32le,
	sound_card:           i16le,
	num_voices:           u16le,
	mix_bits:             u16le,
	music_card:           i16le,
	midi_port:            u16le,
	sound_card_index:     i16le,
	num_voices_index:     i16le,
	mixing_quality_index: i16le,
	music_card_index:     i16le,
	midi_port_index:      i16le,
	sound_volume:         i16le,
	music_volume:         i16le,
	uses_gravis:          u16le,
}
#assert(size_of(Game_Config) == 990)

@(private)
copy_str_into :: proc(dst: []u8, src: string) {
	for i in 0 ..< len(dst) {
		dst[i] = 0
	}
	n := min(len(src), len(dst) - 1)
	for i in 0 ..< n {
		dst[i] = src[i]
	}
}

init_default_config :: proc(cfg: ^Game_Config) {
	cfg^ = {}
	cfg.sound_on = 1
	cfg.music_on = 1
	cfg.game_speed = 1
	cfg.sound_volume = 220
	cfg.music_volume = 190

	for i in 0 ..< NUM_SAVEGAMES {
		cfg.sg_episodes[i] = -1
		cfg.sg_levels[i] = -1
		cfg.sg_skill[i] = 1
		copy_str_into(cfg.sg_names[i][:], "Empty")
	}

	default_names := [NUM_HIGHSCORES]string {
		"Hocus Pocus",
		"Andre Foucault",
		"Jamie Cook",
		"Karim Sultan",
		"Chris tenDen",
	}
	default_scores := [NUM_HIGHSCORES]i32le{50000, 40000, 30000, 20000, 10000}

	for ep in 0 ..< NUM_EPISODES {
		for i in 0 ..< NUM_HIGHSCORES {
			copy_str_into(cfg.hs_names[ep][i][:], default_names[i])
			cfg.hs_scores[ep][i] = default_scores[i]
		}
	}
}

load_game_config :: proc(cfg: ^Game_Config, sav_path: string) -> bool {
	init_default_config(cfg)

	read_path := sav_path
	data, err := os.read_entire_file(read_path, context.temp_allocator)
	if err != nil {
		slash := strings.last_index_any(sav_path, "/\\")
		lower_path := "hocus.sav" if slash < 0 else fmt.tprintf("%shocus.sav", sav_path[:slash + 1])
		if lower_path != sav_path {
			data, err = os.read_entire_file(lower_path, context.temp_allocator)
		}
	}
	if err == nil && len(data) >= size_of(Game_Config) {
		mem.copy(cfg, raw_data(data), size_of(Game_Config))
		if cfg.game_speed > 2 do cfg.game_speed = 1
		if cfg.sound_volume <= 0 || cfg.sound_volume > 255 do cfg.sound_volume = 220
		if cfg.music_volume <= 0 || cfg.music_volume > 255 do cfg.music_volume = 190
		return true
	}

	return false
}

save_game_config :: proc(cfg: ^Game_Config, path: string) -> bool {
	bytes := ([^]u8)(cfg)[:size_of(Game_Config)]
	err := os.write_entire_file(path, bytes)
	return err == nil
}

check_highscore_rank :: proc(cfg: ^Game_Config, ep: int, points: i32) -> int {
	if ep < 0 || ep >= NUM_EPISODES || points <= 0 {
		return -1
	}
	for i in 0 ..< NUM_HIGHSCORES {
		if points > i32(cfg.hs_scores[ep][i]) {
			return i
		}
	}
	return -1
}

insert_highscore :: proc(cfg: ^Game_Config, ep, rank: int, name: string, points: i32) {
	if ep < 0 || ep >= NUM_EPISODES || rank < 0 || rank >= NUM_HIGHSCORES {
		return
	}
	for i := NUM_HIGHSCORES - 1; i > rank; i -= 1 {
		cfg.hs_scores[ep][i] = cfg.hs_scores[ep][i - 1]
		cfg.hs_names[ep][i] = cfg.hs_names[ep][i - 1]
	}
	cfg.hs_scores[ep][rank] = i32le(points)
	copy_str_into(cfg.hs_names[ep][rank][:], name)
}
