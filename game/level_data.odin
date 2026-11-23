package game

import "../assets"
import "core:mem"

MAP_WIDTH :: 240
MAP_HEIGHT :: 60
MAP_TILES :: MAP_WIDTH * MAP_HEIGHT

TILE_SIZE :: 16
TILESET_COLS :: 20
VIEWPORT_W :: 320
VIEWPORT_H :: 160
HUD_Y :: 160
EMPTY_TILE :: u8(255)
EMPTY_INFO :: i16(30000)

Coordinates :: struct #packed {
	_zero:      i16le,
	player_x:   i16le,
	player_y:   i16le,
	randomness: i16le,
}
#assert(size_of(Coordinates) == 8)

Tile_Animation :: struct #packed {
	first: u8,
	last:  u8,
	type:  u8,
}
#assert(size_of(Tile_Animation) == 3)

Tile_Info :: struct #packed {
	back_tile:        u8,
	switch_down_tile: u8,
	switch_up_tile:   u8,
	shootable_tile:   u8,
	anim:             [240]Tile_Animation,
}
#assert(size_of(Tile_Info) == 724)

Message :: struct #packed {
	pos_x: i16le,
	pos_y: i16le,
	lines: [10][50]u8,
}
#assert(size_of(Message) == 504)

Teleporter :: struct #packed {
	start_off: i16le,
	end_off:   i16le,
}
#assert(size_of(Teleporter) == 4)

Switch :: struct #packed {
	type:           u8,
	_padding:       u8,
	switch_offsets: [4]i16le,
	desired_tiles:  [4]u8,
	left:           i16le,
	top:            i16le,
	right:          i16le,
	bottom:         i16le,
}
#assert(size_of(Switch) == 22)

Trigger :: struct #packed {
	required_key: i16le,
	replace_tile: u8,
	_padding:     u8,
	left:         i16le,
	top:          i16le,
	right:        i16le,
	bottom:       i16le,
}
#assert(size_of(Trigger) == 12)

Enemy_Info :: struct #packed {
	sprite:              i16le,
	health:              i16le,
	projectile_speed_x:  i16le,
	projectile_speed_y:  i16le,
	projectile_delta_x:  i16le,
	projectile_seeking:  i16le,
	shoot_in_walk_dir:   i16le,
	can_shoot:           i16le,
	_unused:             i16le,
	projectile_tumbling: i16le,
	move_countdown:      i16le,
	type:                i16le,
}
#assert(size_of(Enemy_Info) == 24)

Enemy_Trigger :: struct #packed {
	flags:   [8]i16le,
	offsets: [8]i16le,
}
#assert(size_of(Enemy_Trigger) == 32)

Item_Info :: struct {
	name:      string,
	score:     i16,
	heal:      u8,
	firepower: u8,
	type:      u8,
}

ITEM_INFOS := [23]Item_Info {
	{"Ruby", 100, 0, 0, 0},
	{"Diamond", 250, 0, 0, 0},
	{"Goblet", 500, 0, 0, 0},
	{"Crown", 1000, 0, 0, 0},
	{"Heal (green)", 0, 10, 0, 0},
	{"Crystal", 0, 0, 0, 1},
	{"Hurt", 0, 0, 0, 2},
	{"Add shot", 0, 0, 1, 0},
	{"Invisible (black)", 0, 0, 0, 3},
	{"Super jump (yellow)", 0, 0, 0, 4},
	{"Super shot (white)", 0, 0, 0, 5},
	{"Smart bomb", 0, 0, 0, 6},
	{"Silver Key", 0, 0, 0, 7},
	{"Gold Key", 0, 0, 0, 8},
	{"Kill", 0, 0, 0, 9},
	{"Wizard note", 0, 0, 0, 10},
	{"Laser Shot", 0, 0, 0, 11},
	{"FISCHER PRICE", 0, 0, 0, 12},
	{"Unused", 0, 0, 0, 0},
	{"Unused", 0, 0, 0, 0},
	{"Unused", 0, 0, 0, 0},
	{"Unused", 0, 0, 0, 0},
	{"Unused", 0, 0, 0, 0},
}

LEVEL_TILESET_NUMBERS := [4][10]int {
	{0, 0, 1, 1, 2, 2, 3, 3, 3, 0},
	{4, 4, 5, 5, 6, 6, 7, 7, 7, 0},
	{8, 8, 9, 9, 10, 10, 11, 11, 11, 0},
	{12, 12, 13, 13, 14, 14, 15, 15, 15, 0},
}

LEVEL_NUMBERS := [4][10]int {
	{0, 1, 2, 3, 4, 5, 6, 7, 8, 0},
	{9, 10, 11, 12, 13, 14, 15, 16, 17, 0},
	{18, 19, 20, 21, 22, 23, 24, 25, 26, 0},
	{27, 28, 29, 30, 31, 32, 33, 34, 35, 0},
}

LEVEL_BACKDROP_NUMBERS := [4][10]int {
	{0, 0, 1, 1, 2, 2, 3, 3, 3, 0},
	{4, 4, 5, 5, 6, 6, 7, 7, 7, 0},
	{8, 8, 9, 9, 10, 10, 11, 11, 11, 0},
	{12, 12, 13, 13, 14, 14, 15, 15, 15, 0},
}

LEVEL_MUSIC_NUMBERS := [4][9]int {
	{3, 3, 4, 4, 0, 0, 2, 2, 2},
	{9, 9, 7, 7, 8, 8, 1, 1, 1},
	{4, 4, 0, 0, 7, 7, 6, 6, 6},
	{2, 2, 8, 8, 9, 9, 5, 5, 5},
}

LEVEL_ELEVATOR_TILES := [4][10][2]int {
	{
		{-1, -1},
		{-1, -1},
		{-1, -1},
		{-1, -1},
		{-1, -1},
		{-1, -1},
		{-1, -1},
		{-1, -1},
		{-1, -1},
		{-1, -1},
	},
	{
		{-1, -1},
		{-1, -1},
		{-1, -1},
		{-1, -1},
		{-1, -1},
		{-1, -1},
		{-1, -1},
		{-1, -1},
		{-1, -1},
		{-1, -1},
	},
	{
		{78, 79},
		{78, 79},
		{62, 63},
		{62, 63},
		{40, 41},
		{40, 41},
		{85, 86},
		{85, 86},
		{85, 86},
		{-1, -1},
	},
	{
		{58, 59},
		{58, 59},
		{122, 123},
		{122, 123},
		{70, 71},
		{70, 71},
		{60, 61},
		{60, 61},
		{60, 61},
		{-1, -1},
	},
}

Level_Data :: struct {
	episode:        int,
	level:          int,
	tileset_index:  int,
	backdrop_index: int,
	coordinates:    Coordinates,
	tile_info:      Tile_Info,
	messages:       [10]Message,
	teleporters:    [10]Teleporter,
	switches:       [23]Switch,
	inserts:        [25]Trigger,
	keyholes:       [25]Trigger,
	enemy_infos:    [10]Enemy_Info,
	enemy_triggers: [250]Enemy_Trigger,
	map_back:       [MAP_TILES]u8,
	map_main:       [MAP_TILES]u8,
	map_insert:     [MAP_TILES]u8,
	map_info:       [MAP_TILES]i16,
	map_triggered:  [MAP_TILES]u8,
	crystals_total: int,
	treasure_total: int,
	tile_countdown: int,
}

@(private)
copy_chunk_into :: proc(
	dat: ^assets.Dat_File,
	base_id: assets.Chunk_ID,
	offset: int,
	dst: rawptr,
	expected_size: int,
) -> bool {
	chunk, ok := assets.get_chunk_offset(dat, base_id, offset)
	if !ok || len(chunk) < expected_size {
		return false
	}
	mem.copy(dst, raw_data(chunk), expected_size)
	return true
}

load_level_data :: proc(lvl: ^Level_Data, dat: ^assets.Dat_File, episode, level: int) -> bool {
	if lvl == nil || dat == nil {
		return false
	}
	if episode < 0 || episode >= 4 || level < 0 || level >= 9 {
		return false
	}
	if !assets.is_registered(dat) && episode > 0 {
		return false
	}

	lvl^ = {}
	lvl.episode = episode
	lvl.level = level
	lvl.tileset_index = LEVEL_TILESET_NUMBERS[episode][level]
	lvl.backdrop_index = LEVEL_BACKDROP_NUMBERS[episode][level]
	level_num := LEVEL_NUMBERS[episode][level]

	if !copy_chunk_into(dat, .E1L1_000, level_num, &lvl.coordinates, size_of(lvl.coordinates)) do return false
	if !copy_chunk_into(dat, .E1L1_001, level_num, &lvl.tile_info, size_of(lvl.tile_info)) do return false
	if !copy_chunk_into(dat, .E1L1_002, level_num, &lvl.messages, size_of(lvl.messages)) do return false
	if !copy_chunk_into(dat, .E1L1_003, level_num, &lvl.teleporters, size_of(lvl.teleporters)) do return false
	if !copy_chunk_into(dat, .E1L1_004, level_num, &lvl.switches, size_of(lvl.switches)) do return false
	if !copy_chunk_into(dat, .E1L1_005, level_num, &lvl.inserts, size_of(lvl.inserts)) do return false
	if !copy_chunk_into(dat, .E1L1_006, level_num, &lvl.keyholes, size_of(lvl.keyholes)) do return false
	if !copy_chunk_into(dat, .E1L1_007, level_num, &lvl.enemy_infos, size_of(lvl.enemy_infos)) do return false
	if !copy_chunk_into(dat, .E1L1_008, level_num, &lvl.enemy_triggers, size_of(lvl.enemy_triggers)) do return false
	if !copy_chunk_into(dat, .E1L1_009, level_num, &lvl.map_back, size_of(lvl.map_back)) do return false
	if !copy_chunk_into(dat, .E1L1_010, level_num, &lvl.map_main, size_of(lvl.map_main)) do return false
	if !copy_chunk_into(dat, .E1L1_011, level_num, &lvl.map_insert, size_of(lvl.map_insert)) do return false

	info_chunk, info_ok := assets.get_chunk_offset(dat, .E1L1_012, level_num)
	if !info_ok || len(info_chunk) < MAP_TILES * 2 {
		return false
	}
	raw_info := (^[MAP_TILES]i16le)(raw_data(info_chunk))
	for i in 0 ..< MAP_TILES {
		lvl.map_info[i] = i16(raw_info[i])
	}

	crystals := 0
	treasures := 0
	for i in 0 ..< MAP_TILES {
		val := lvl.map_info[i]
		if val >= 0 && val < 23 {
			if ITEM_INFOS[val].type == 1 {
				crystals += 1
			}
			if ITEM_INFOS[val].score != 0 {
				treasures += 1
			}
		}
	}
	lvl.crystals_total = crystals
	lvl.treasure_total = treasures

	return true
}

count_tileset_tiles :: proc(tileset_pcx: ^assets.Pcx_Image) -> int {
	if tileset_pcx == nil || tileset_pcx.width < 320 {
		return 0
	}
	max_tiles := (tileset_pcx.height / TILE_SIZE) * TILESET_COLS
	max_tiles = min(max_tiles, 240)
	for i in 0 ..< max_tiles {
		tx := (i % TILESET_COLS) * TILE_SIZE
		ty := (i / TILESET_COLS) * TILE_SIZE
		if tileset_pcx.pixels[ty * tileset_pcx.width + tx] == 255 {
			return i
		}
	}
	return max_tiles
}
