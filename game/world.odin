package game

import "../assets"

MAX_SNOW :: 20
MAX_ACTORS :: 8
MAX_SHOTS :: 10
MAX_ENEMYSHOTS :: 8
MAX_TWINKS :: 8
MAX_PARTICLES :: 8
PIXELS_PER_PARTICLE :: 16
MAX_SCORETAGS :: 10
MAX_SPAWNQUEUE :: 32

PLAYER_DELTA_YS := [19]int{-16, -8, -8, -4, -4, -4, -2, -1, -1, 0, 1, 1, 2, 4, 4, 4, 8, 8, 16}

PLAYER_DELTA_YS_HI := [25]int {
	-16,
	-16,
	-16,
	-16,
	-8,
	-8,
	-4,
	-4,
	-4,
	-2,
	-1,
	-1,
	0,
	1,
	1,
	2,
	4,
	4,
	4,
	8,
	8,
	16,
	16,
	16,
	16,
}

SKILL_DAMAGE := [4]int{-4, -12, -16, 0}

Input_State :: struct {
	left:        bool,
	right:       bool,
	up:          bool,
	down:        bool,
	use_down:    bool,
	use_up:      bool,
	jump_down:   bool,
	jump_up:     bool,
	fire_down:   bool,
	fire_up:     bool,
	scroll_up:   bool,
	scroll_down: bool,
}

Player_Shot :: struct {
	x:          int,
	y:          int,
	prev_x:     int,
	prev_y:     int,
	prev_valid: bool,
	dir:        int,
	fly_up:     bool,
	is_power:   bool,
}

Score_Tag :: struct {
	x, y:           int,
	prev_x, prev_y: int,
	prev_valid:     bool,
	frame:          int,
	state:          int,
	dir:            int,
}

Twink :: struct {
	x, y:           int,
	prev_x, prev_y: int,
	prev_valid:     bool,
	state:          int,
	dir:            int,
}

Particle_Pixel :: struct {
	x, y:           int,
	prev_x, prev_y: int,
	vx, vy:         int,
	color:          u8,
}

Particle_Burst :: struct {
	pixels:     [PIXELS_PER_PARTICLE]Particle_Pixel,
	state:      int,
	prev_valid: bool,
}

Snow_Particle :: struct {
	x, y:           int,
	prev_x, prev_y: int,
	prev_sub_x:     u8,
	prev_valid:     bool,
	state:          int,
	sub_x:          u8,
	visible:        bool,
}

Actor :: struct {
	type:               int,
	x, y:               int,
	prev_x, prev_y:     int,
	prev_valid:         bool,
	vx, vy:             int,
	width, height:      int,
	dir:                int,
	frame:              int,
	health:             int,
	max_health:         int,
	flashing:           int,
	tile_index:         int,
	sprite:             int,
	settings_index:     int,
	is_shooting:        bool,
	shoots_in_walk_dir: bool,
	can_shoot:          bool,
	seeking:            int,
	shot_delta_x:       int,
	move_countdown:     int,
	new_dir_countdown:  int,
	jump_countdown:     int,
	jump_speed:         int,
	countdown:          int,
	spawn_countdown:    int,
	shoot_countdown:    int,
	one:                int,
}

Enemy_Shot :: struct {
	state:          int,
	x, y:           int,
	prev_x, prev_y: int,
	prev_valid:     bool,
	width:          int,
	height:         int,
	dir:            int,
	sprite:         int,
	frame:          int,
	max_frame:      int,
	delay:          int,
	wobble:         bool,
	speed_x:        int,
	speed_y:        int,
	seeking:        bool,
}

BOSS4_XS := [4]int{128, 128, 113, 128}
BOSS4_YS := [4]int{54, 48, 42, 36}
BOSS4_TILE_OFFS := [4]int{0x3320, 0x2D80, 0x27D1, 0x2240}
BOSS4_DIRS := [4]int{1, 1, 0, 1}
BOSS4_HEALTH := [4]int{600, 400, 200, -1}

Level_Status :: enum {
	Playing,
	Won,
	Died,
}

World :: struct {
	level:                     Level_Data,
	rng:                       assets.Rand_Table,
	episode:                   int,
	level_idx:                 int,
	skill:                     int,
	status:                    Level_Status,
	tick_count:                int,
	tile_tick:                 bool,
	score:                     i32,
	old_score:                 i32,
	player_health:             int,
	player_firepower:          int,
	old_firepower:             int,
	crystals_collected:        int,
	treasure_found:            int,
	got_key1:                  bool,
	got_key2:                  bool,
	hud_level_num_flash:       int,
	player_x:                  int,
	player_y:                  int,
	player_x_pix:              int,
	player_tile_x:             int,
	player_tile_y:             int,
	player_screen_x:           int,
	player_screen_y:           int,
	old_player_x:              int,
	old_player_y:              int,
	player_dir:                int,
	player_frame:              int,
	player_walking:            bool,
	player_firing:             bool,
	player_aiming_up:          bool,
	player_jumping:            bool,
	player_falling:            bool,
	was_falling:               bool,
	player_jump_index:         int,
	max_jump_index:            int,
	max_delta_y_index:         int,
	using_hi_jump:             bool,
	super_jump:                bool,
	super_jump_counter:        int,
	rapid_fire_countdown:      int,
	hide_countdown:            int,
	hurt_countdown:            int,
	player_death_countdown:    int,
	level_done_countdown:      int,
	powershots_left:           int,
	tick1:                     int,
	tick5:                     int,
	teleport_counter:          int,
	teleport_end_x:            int,
	teleport_end_y:            int,
	elevator_tile1:            int,
	elevator_tile2:            int,
	wizard_activated:          bool,
	active_wizard_msg:         int,
	cam_x_t8:                  int,
	cam_x:                     int,
	odd_cam_x:                 int,
	cam_y:                     int,
	cam_warp:                  bool,
	cam_scrolled:              bool,
	look_delta_y:              int,
	up_key_counter:            int,
	down_key_counter:          int,
	prev_cam_x_t8:             int,
	prev_cam_y:                int,
	prev_player_x:             int,
	prev_player_y:             int,
	shots:                     [MAX_SHOTS]Player_Shot,
	player_shots_active:       int,
	twinks:                    [MAX_TWINKS]Twink,
	twink_index:               int,
	score_tags:                [MAX_SCORETAGS]Score_Tag,
	particles:                 [MAX_PARTICLES]Particle_Burst,
	particle_index:            int,
	snow:                      [MAX_SNOW]Snow_Particle,
	snow_index:                int,
	level_flash_red_countdown: int,
	actors:                    [MAX_ACTORS]Actor,
	enemy_shots:               [MAX_ENEMYSHOTS]Enemy_Shot,
	spawn_tile_index:          [MAX_SPAWNQUEUE]int,
	boss4_stage:               int,
	num_enemies_total:         int,
	num_enemies_killed:        int,
	next_spawn_sound_tick:     int,
	sound_userdata:            rawptr,
	on_sound:                  proc(userdata: rawptr, sfx_id: int),
}

init_input_state :: proc(inp: ^Input_State) {
	inp^ = {
		use_up  = true,
		jump_up = true,
		fire_up = true,
	}
}

world_play_sound :: proc(w: ^World, sfx_id: int) {
	if w.on_sound != nil {
		w.on_sound(w.sound_userdata, sfx_id)
	}
}

world_capture_prev_state :: proc(w: ^World) {
	w.prev_cam_x_t8 = w.cam_x_t8
	w.prev_cam_y = w.cam_y
	w.prev_player_x = w.player_x
	w.prev_player_y = w.player_y

	for &a in w.actors {
		if a.type != -1 && a.spawn_countdown == 0 {
			a.prev_x = a.x
			a.prev_y = a.y
			a.prev_valid = true
		} else {
			a.prev_valid = false
		}
	}
	for &es in w.enemy_shots {
		if es.state != -1 && es.delay == 0 {
			es.prev_x = es.x
			es.prev_y = es.y
			es.prev_valid = true
		} else {
			es.prev_valid = false
		}
	}
	for &s in w.shots {
		if s.x != -99 {
			s.prev_x = s.x
			s.prev_y = s.y
			s.prev_valid = true
		} else {
			s.prev_valid = false
		}
	}
	for &st in w.score_tags {
		if st.state > 0 {
			st.prev_x = st.x
			st.prev_y = st.y
			st.prev_valid = true
		} else {
			st.prev_valid = false
		}
	}
	for &burst in w.particles {
		if burst.state > 0 {
			burst.prev_valid = true
			for &p in burst.pixels {
				p.prev_x = p.x
				p.prev_y = p.y
			}
		} else {
			burst.prev_valid = false
		}
	}
	for &tw in w.twinks {
		if tw.state > 0 {
			tw.prev_x = tw.x
			tw.prev_y = tw.y
			tw.prev_valid = true
		} else {
			tw.prev_valid = false
		}
	}
	for &sn in w.snow {
		if sn.x != -99 {
			sn.prev_x = sn.x
			sn.prev_y = sn.y
			sn.prev_sub_x = sn.sub_x
			sn.prev_valid = true
		} else {
			sn.prev_valid = false
		}
	}
}

world_init_level :: proc(
	w: ^World,
	dat: ^assets.Dat_File,
	sprites: ^Sprite_Bank,
	episode, level_idx, skill: int,
	carry_score: i32 = 0,
) -> bool {
	saved_ud := w.sound_userdata
	saved_hook := w.on_sound
	w^ = {}
	w.sound_userdata = saved_ud
	w.on_sound = saved_hook

	if !load_level_data(&w.level, dat, episode, level_idx) {
		return false
	}
	_ = assets.load_rand_table(&w.rng, dat)

	w.episode = episode
	w.level_idx = level_idx
	w.skill = clamp(skill, 0, 3)
	w.status = .Playing

	w.score = carry_score
	w.old_score = carry_score
	w.player_health = 100
	w.player_firepower = 1
	w.old_firepower = 1
	w.look_delta_y = 5
	w.active_wizard_msg = -1

	w.elevator_tile1 = LEVEL_ELEVATOR_TILES[episode][level_idx][0]
	w.elevator_tile2 = LEVEL_ELEVATOR_TILES[episode][level_idx][1]

	w.player_x = int(w.level.coordinates.player_x) << 1
	w.player_y = int(w.level.coordinates.player_y) << 4
	w.old_player_x = w.player_x
	w.old_player_y = w.player_y
	w.player_dir = 0
	if sprites != nil && sprites.slot_loaded[SPR_PLAYER] {
		w.player_frame = int(sprites.infos[SPR_PLAYER].stand_frame)
	}

	for &s in w.shots {
		s.x = -99
	}
	for &p in w.particles {
		p.state = -1
	}
	for &sn in w.snow {
		sn.x = -99
	}
	for &sq in w.spawn_tile_index {
		sq = -1
	}
	for &a in w.actors {
		a.type = -1
		a.tile_index = -1
	}
	for &es in w.enemy_shots {
		es.state = -1
	}

	for i in 0 ..< MAP_TILES {
		v := int(w.level.map_info[i])
		if v >= 106 && v <= 115 && w.level.enemy_infos[v - 106].health != -1 {
			w.num_enemies_total += 1
		}
	}

	w.cam_warp = true
	update_camera(w)
	w.cam_warp = false

	if episode == 3 && level_idx == 8 {
		w.boss4_stage = 0
		spawn_actor(w, sprites, 0, BOSS4_XS[0] << 2, BOSS4_YS[0] << 4, BOSS4_TILE_OFFS[0])
		w.actors[0].dir = BOSS4_DIRS[0]
		w.actors[0].vx = 0
		w.actors[0].move_countdown = 100
		w.actors[0].seeking = 10 + int(assets.rand_next(&w.rng, 20))
		w.actors[0].shot_delta_x = 0
	}

	world_capture_prev_state(w)
	return true
}

world_get_hud :: proc(w: ^World) -> HUD_State {
	return HUD_State {
		level_number = w.level_idx + 1,
		score = w.score,
		health = w.player_health,
		crystals_collected = w.crystals_collected,
		crystals_total = w.level.crystals_total,
		got_key1 = w.got_key1,
		got_key2 = w.got_key2,
		flash_level_num = w.hud_level_num_flash,
	}
}
