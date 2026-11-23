package ui

import "../assets"
import "../game"
import "../render"
import "core:fmt"

Text_Pic_Ref :: struct {
	chunk: assets.Chunk_ID,
	x4:    int,
	y:     int,
}

PAR_TIMES := [4][9]int {
	{150, 300, 400, 350, 350, 350, 420, 350, 400},
	{325, 275, 300, 350, 400, 350, 400, 375, 250},
	{525, 450, 520, 475, 525, 450, 550, 450, 300},
	{480, 375, 350, 300, 400, 350, 450, 400, 180},
}

STORY_PICS := [10]Text_Pic_Ref {
	{.PIC2_IMG, 4, 16},
	{.PIC1_IMG, 50, 25},
	{.PIC8_IMG, 4, 25},
	{.PIC3_IMG, 4, 21},
	{.PIC1_IMG, 50, 25},
	{.NONE, 0, 0},
	{.NONE, 0, 0},
	{.NONE, 0, 0},
	{.NONE, 0, 0},
	{.PIC1_IMG, 50, 25},
}

FINALE1_PICS := [2]Text_Pic_Ref{{.PIC7_IMG, 4, 21}, {.PIC1_IMG, 50, 25}}

FINALE2_PICS := [2]Text_Pic_Ref{{.PIC1_IMG, 50, 25}, {.PIC1_IMG, 50, 25}}

FINALE3_PICS := [4]Text_Pic_Ref {
	{.PIC6_IMG, 4, 42},
	{.PIC1_IMG, 50, 25},
	{.NONE, 0, 0},
	{.PIC1_IMG, 50, 25},
}

FINALE4_PICS := [2]Text_Pic_Ref{{.PIC5_IMG, 4, 19}, {.NONE, 0, 0}}

EPISODE_NAMES := [4]string {
	"Time Tripping",
	"Shattered Worlds",
	"Warped and Weary",
	"Destination Home",
}

draw_menu_list :: proc(
	r: ^render.GPU_Renderer,
	u: ^UI_Assets,
	headline: string,
	options: []string,
	selected: int,
	cursor_tick: int,
	bottom_hint: string,
	subtitle := "",
) {
	draw_menu_chrome(r, u, bottom_hint)

	has_headline := len(headline) > 0
	has_subtitle := len(subtitle) > 0
	total_rows := len(options) + (1 if has_headline else 0)
	line_h := 14
	if total_rows >= 8 {
		line_h = 13
	}

	area_top := 42
	area_bottom := 162 if has_subtitle else 180
	area_h := area_bottom - area_top
	block_h := total_rows * line_h + (6 if has_headline else 0)
	start_y := area_top + max((area_h - block_h) / 2, 0)

	max_w := 0
	for opt in options {
		w := text_width(&u.font, opt)
		if w > max_w do max_w = w
	}
	item_x := clamp((render.SCREEN_WIDTH - max_w) / 2 + 8, 28, 120)
	cursor_x := item_x - 20

	y := start_y
	if has_headline {
		draw_text_g_centered(r, &u.font, y, .White, headline)
		y += line_h + 6
	}

	for opt, idx in options {
		if idx == selected {
			draw_menu_cursor(r, u, cursor_x, y - 3, cursor_tick)
			draw_menu_item(r, &u.font, item_x, y, .Gold, .White, opt)
		} else {
			draw_menu_item(r, &u.font, item_x, y, .Red, .Blue, opt)
		}
		y += line_h
	}

	if has_subtitle {
		draw_text_g_centered(r, &u.font, 166, .Green, subtitle)
	}
}

draw_key_controls_screen :: proc(
	r: ^render.GPU_Renderer,
	u: ^UI_Assets,
	action_labels: []string,
	key_names: []string,
	selected: int,
	waiting_for_key: bool,
	cursor_tick: int,
) {
	hint :=
		"Press any key to bind - ESC to cancel" if waiting_for_key else "ENTER to rebind - ESC to return"
	draw_menu_chrome(r, u, hint)
	draw_text_g_centered(r, &u.font, 42, .White, "Define Key Controls")

	y := 58
	row_h := 12
	count := min(len(action_labels), len(key_names))

	for i in 0 ..< count {
		is_sel := (i == selected)
		if is_sel {
			draw_menu_cursor(r, u, 28, y - 3, cursor_tick)
		}
		draw_text_gradient(r, &u.font, 48, y, .White if is_sel else .Blue, action_labels[i])

		val_str := key_names[i]
		val_col: Gradient_Color = .Gold if is_sel else .Green
		if is_sel && waiting_for_key {
			val_str = "Press new key..."
			val_col = .Gold if ((cursor_tick / 10) % 2) == 0 else .White
		}
		val_x := max(276 - text_width(&u.font, val_str), 160)
		draw_text_gradient(r, &u.font, val_x, y, val_col, val_str)
		y += row_h
	}

	reset_idx := count
	y += 4
	if selected == reset_idx {
		draw_menu_cursor(r, u, 28, y - 3, cursor_tick)
		draw_menu_item(r, &u.font, 48, y, .Gold, .White, "Reset to defaults")
	} else {
		draw_menu_item(r, &u.font, 48, y, .Red, .Blue, "Reset to defaults")
	}
}

@(private)
draw_vol_bar :: proc(r: ^render.GPU_Renderer, x, y, w, h: int, frac: f32, active: bool) {
	border_col := u8(0xE0) if active else u8(0xC2)
	fill_col := u8(0xD2) if active else u8(0xC4)
	render.draw_solid_rect(&r.batch, f32(x), f32(y), f32(w), 1, border_col)
	render.draw_solid_rect(&r.batch, f32(x), f32(y + h - 1), f32(w), 1, border_col)
	render.draw_solid_rect(&r.batch, f32(x), f32(y), 1, f32(h), border_col)
	render.draw_solid_rect(&r.batch, f32(x + w - 1), f32(y), 1, f32(h), border_col)
	fill_w := int(clamp(frac, 0.0, 1.0) * f32(w - 4))
	if fill_w > 0 {
		render.draw_solid_rect(&r.batch, f32(x + 2), f32(y + 2), f32(fill_w), f32(h - 4), fill_col)
	}
}

draw_volume_screen :: proc(
	r: ^render.GPU_Renderer,
	u: ^UI_Assets,
	sfx_vol, music_vol: f32,
	selected_row: int,
	cursor_tick: int,
) {
	draw_menu_chrome(r, u, "UP/DOWN/LEFT/RIGHT to adjust - ESC when done")
	draw_text_g_centered(r, &u.font, 54, .White, "Volume Control")

	buf: [32]u8

	if selected_row == 0 {
		draw_menu_cursor(r, u, 42, 81, cursor_tick)
	}
	s1 := fmt.bprintf(buf[:], "Sound FX: %d%%", int(sfx_vol * 100.0 + 0.5))
	draw_text_gradient(r, &u.font, 64, 84, .Gold if selected_row == 0 else .Blue, s1)
	draw_vol_bar(r, 160, 83, 110, 10, sfx_vol, selected_row == 0)

	if selected_row == 1 {
		draw_menu_cursor(r, u, 42, 111, cursor_tick)
	}
	s2 := fmt.bprintf(buf[:], "Music: %d%%", int(music_vol * 100.0 + 0.5))
	draw_text_gradient(r, &u.font, 64, 114, .Gold if selected_row == 1 else .Blue, s2)
	draw_vol_bar(r, 160, 113, 110, 10, music_vol, selected_row == 1)
}

draw_text_page :: proc(
	r: ^render.GPU_Renderer,
	u: ^UI_Assets,
	page: ^assets.Text_Page,
	page_num, total_pages: int,
) {
	draw_starfield(r, &u.starfield)

	if u.page_pic.handle != nil {
		render.draw_texture_region(
			&r.batch,
			u.page_pic,
			0,
			0,
			f32(u.page_pic.width),
			f32(u.page_pic.height),
			f32(u.page_pic_x),
			f32(u.page_pic_y),
			f32(u.page_pic.width),
			f32(u.page_pic.height),
		)
	}

	line_count := clamp(int(page.line_count), 0, 20)
	line_h := max(int(page.line_height), 8)
	null_h := max(int(page.null_height), 6)

	y := 16
	for i in 0 ..< line_count {
		text := assets.cstr_slice(page.lines[i][:])
		if len(text) == 0 {
			y += null_h
			continue
		}
		lx := int(page.line_info[i * 2 + 0])
		lcol := clamp(int(page.line_info[i * 2 + 1]), 0, 9)
		if lx == -1 {
			draw_text_g_centered(r, &u.font, y, Gradient_Color(lcol), text)
		} else {
			draw_text_gradient(r, &u.font, lx, y, Gradient_Color(lcol), text)
		}
		y += line_h
	}

	if u.bottom_bar.handle != nil {
		render.draw_texture_region(
			&r.batch,
			u.bottom_bar,
			0,
			0,
			f32(u.bottom_bar.width),
			f32(u.bottom_bar.height),
			0,
			184,
			f32(u.bottom_bar.width),
			f32(u.bottom_bar.height),
		)
	}
	buf: [64]u8
	hint := fmt.bprintf(
		buf[:],
		"Page %d of %d - LEFT/RIGHT to turn - ESC to exit",
		page_num + 1,
		total_pages,
	)
	draw_text_gs_centered(r, &u.font, 188, .White, hint)
}

Intermission_Info :: struct {
	won:            bool,
	episode:        int,
	level:          int,
	skill:          int,
	treasure_found: int,
	treasure_total: int,
	seconds:        int,
	par_seconds:    int,
	treasure_bonus: i32,
	time_bonus:     i32,
}

compute_intermission :: proc(
	won: bool,
	episode, level, skill, found, total, seconds: int,
) -> Intermission_Info {
	par := PAR_TIMES[clamp(episode, 0, 3)][clamp(level, 0, 8)]
	bonus_step: i32 = 25000
	if skill == 1 do bonus_step = 50000
	if skill >= 2 do bonus_step = 75000

	t_bonus: i32 = 0
	s_bonus: i32 = 0
	if won {
		if total > 0 && found >= total {
			t_bonus = bonus_step
		}
		if seconds < par {
			s_bonus = bonus_step
		}
	}

	return Intermission_Info {
		won = won,
		episode = episode,
		level = level,
		skill = skill,
		treasure_found = found,
		treasure_total = total,
		seconds = seconds,
		par_seconds = par,
		treasure_bonus = t_bonus,
		time_bonus = s_bonus,
	}
}

draw_intermission_screen :: proc(r: ^render.GPU_Renderer, u: ^UI_Assets, info: Intermission_Info) {
	draw_menu_chrome(r, u, "Press any key to continue")

	y := 56 if info.won else 74
	title :=
		"Castle complete - congratulations!" if info.won else "Tough break - you'll get it next time!"
	draw_text_g_centered(r, &u.font, y, .White, title)
	y += 16

	buf: [96]u8
	s := fmt.bprintf(buf[:], "Results for Episode %d Level %d", info.episode + 1, info.level + 1)
	draw_text_g_centered(r, &u.font, y, .Red, s)
	y += 22

	s = fmt.bprintf(
		buf[:],
		"Treasures found: %d   Available: %d",
		info.treasure_found,
		info.treasure_total,
	)
	draw_text_g_centered(r, &u.font, y, .Green, s)
	y += 14

	pct := 0
	if info.treasure_total > 0 {
		pct = (info.treasure_found * 100) / info.treasure_total
	}
	if info.won {
		if info.treasure_bonus > 0 {
			s = fmt.bprintf(buf[:], "Accuracy: %d%%  BONUS %d points!", pct, info.treasure_bonus)
		} else {
			s = fmt.bprintf(buf[:], "Accuracy: %d%%  Less than 100%% - NO BONUS", pct)
		}
	} else {
		s = fmt.bprintf(buf[:], "Accuracy: %d%%  Castle not complete", pct)
	}
	draw_text_g_centered(r, &u.font, y, .Red, s)
	y += 22

	if info.won {
		s = fmt.bprintf(
			buf[:],
			"Time to beat: %ds   Your time: %ds",
			info.par_seconds,
			info.seconds,
		)
		draw_text_g_centered(r, &u.font, y, .Green, s)
		y += 14
		if info.time_bonus > 0 {
			s = fmt.bprintf(buf[:], "BONUS %d points!", info.time_bonus)
		} else {
			s = "Not fast enough - NO BONUS"
		}
		draw_text_g_centered(r, &u.font, y, .Red, s)
	}
}

draw_highscores_screen :: proc(
	r: ^render.GPU_Renderer,
	u: ^UI_Assets,
	ep: int,
	names: [5]string,
	scores: [5]i32,
) {
	draw_menu_chrome(r, u, "LEFT/RIGHT switch episode - ESC to exit")

	buf: [64]u8
	hdr := fmt.bprintf(buf[:], "High Scores - %s", EPISODE_NAMES[clamp(ep, 0, 3)])
	draw_text_g_centered(r, &u.font, 48, .Gold, hdr)

	y := 72
	for i in 0 ..< 5 {
		row_name := fmt.bprintf(buf[:], "%d. %s", i + 1, names[i])
		draw_text_gradient(r, &u.font, 44, y, .White if i == 0 else .Blue, row_name)

		sbuf: [24]u8
		sstr := fmt.bprintf(sbuf[:], "%d", scores[i])
		sx := 276 - text_width(&u.font, sstr)
		draw_text_gradient(r, &u.font, sx, y, .Gold if i == 0 else .Green, sstr)
		y += 18
	}
}

draw_save_restore_screen :: proc(
	r: ^render.GPU_Renderer,
	u: ^UI_Assets,
	is_save: bool,
	selected: int,
	slot_labels: [9]string,
	editing_name: bool,
	edit_text: string,
	cursor_tick: int,
) {
	hint :=
		"Type name & ENTER to save - ESC cancel" if editing_name else "UP/DOWN select - ENTER confirm - ESC exit"
	draw_menu_chrome(r, u, hint)

	title := "Save Game - Select a slot" if is_save else "Restore an Old Game"
	draw_text_g_centered(r, &u.font, 42, .White, title)

	y := 58
	for i in 0 ..< 9 {
		if i == selected {
			draw_menu_cursor(r, u, 20, y - 3, cursor_tick)
		}
		buf: [64]u8
		label := slot_labels[i]
		if editing_name && i == selected {
			blink := "_" if ((cursor_tick / 12) % 2) == 0 else ""
			label = fmt.bprintf(buf[:], "%d) %s%s", i + 1, edit_text, blink)
			draw_text_gradient(r, &u.font, 40, y, .Gold, label)
		} else {
			line := fmt.bprintf(buf[:], "%d) %s", i + 1, label)
			draw_text_gradient(r, &u.font, 40, y, .White if i == selected else .Blue, line)
		}
		y += 13
	}
}

draw_enter_highscore_screen :: proc(
	r: ^render.GPU_Renderer,
	u: ^UI_Assets,
	ep: int,
	points: i32,
	edit_text: string,
	cursor_tick: int,
) {
	draw_menu_chrome(r, u, "Enter your name then press ENTER")
	draw_text_g_centered(r, &u.font, 60, .Gold, "New High Score!")

	buf: [64]u8
	s := fmt.bprintf(buf[:], "%s - %d points", EPISODE_NAMES[clamp(ep, 0, 3)], points)
	draw_text_g_centered(r, &u.font, 80, .White, s)

	blink := "_" if ((cursor_tick / 12) % 2) == 0 else ""
	prompt := fmt.bprintf(buf[:], "%s%s", edit_text, blink)
	draw_text_g_centered(r, &u.font, 112, .Green, prompt)
}

draw_paused_overlay :: proc(r: ^render.GPU_Renderer, u: ^UI_Assets) {
	draw_ingame_text_centered(r, &u.font, 76, "Game Paused")
}

draw_wizard_overlay :: proc(r: ^render.GPU_Renderer, u: ^UI_Assets, w: ^game.World, msg_idx: int) {
	if msg_idx < 0 || msg_idx >= 10 do return
	msg := &w.level.messages[msg_idx]

	num_lines := 0
	for i in 0 ..< 10 {
		if len(assets.cstr_slice(msg.lines[i][:])) == 0 {
			break
		}
		num_lines += 1
	}
	if num_lines == 0 do return

	text_y := max(80 - 6 * num_lines, 8)
	for i in 0 ..< num_lines {
		line := assets.cstr_slice(msg.lines[i][:])
		draw_ingame_text_centered(r, &u.font, text_y + i * 12, line)
	}
}

draw_crystal_popup :: proc(r: ^render.GPU_Renderer, u: ^UI_Assets) {
	if u.crystal_box.handle == nil do return
	render.draw_texture_region(
		&r.batch,
		u.crystal_box,
		0,
		0,
		f32(u.crystal_box.width),
		f32(u.crystal_box.height),
		48,
		46,
		f32(u.crystal_box.width),
		f32(u.crystal_box.height),
	)
}
