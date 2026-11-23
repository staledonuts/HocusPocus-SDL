package game

import "../assets"
import "../render"
import "core:fmt"
import "core:math"

Level_Graphics :: struct {
	tileset:   render.Indexed_Texture,
	backdrop:  render.Indexed_Texture,
	hud_bg:    render.Indexed_Texture,
	hud_stuff: render.Indexed_Texture,
	palette:   assets.Palette,
	num_tiles: int,
}

HUD_State :: struct {
	level_number:       int,
	score:              i32,
	health:             int,
	crystals_collected: int,
	crystals_total:     int,
	got_key1:           bool,
	got_key2:           bool,
	flash_level_num:    int,
}

@(private)
load_planar_chunk_tex :: proc(
	r: ^render.GPU_Renderer,
	dat: ^assets.Dat_File,
	id: assets.Chunk_ID,
) -> (
	tex: render.Indexed_Texture,
	ok: bool,
) {
	chunk, cok := assets.get_chunk(dat, id)
	if !cok do return {}, false
	img, dok := assets.decode_planar_image(chunk)
	if !dok do return {}, false
	defer assets.destroy_planar_image(&img)
	return render.create_indexed_texture_from_indices(r, img.width, img.height, img.pixels)
}

load_level_graphics :: proc(
	gfx: ^Level_Graphics,
	r: ^render.GPU_Renderer,
	dat: ^assets.Dat_File,
	lvl: ^Level_Data,
) -> (
	ok: bool,
) {
	destroy_level_graphics(gfx, r)
	defer if !ok {
		destroy_level_graphics(gfx, r)
	}

	tiles_chunk, tiles_ok := assets.get_chunk_offset(dat, .TILES01_PCX, lvl.tileset_index)
	if !tiles_ok do return false
	tiles_pcx, tdec_ok := assets.decode_pcx(tiles_chunk)
	if !tdec_ok do return false
	defer assets.destroy_pcx(&tiles_pcx)

	gfx.num_tiles = count_tileset_tiles(&tiles_pcx)
	gfx.tileset = render.create_indexed_texture_from_indices(
		r,
		tiles_pcx.width,
		tiles_pcx.height,
		tiles_pcx.pixels,
	) or_return

	back_chunk, back_ok := assets.get_chunk_offset(dat, .BACK01_PCX, lvl.backdrop_index)
	if !back_ok do return false
	back_pcx, bdec_ok := assets.decode_pcx(back_chunk)
	if !bdec_ok do return false
	defer assets.destroy_pcx(&back_pcx)

	gfx.backdrop = render.create_indexed_texture_from_indices(
		r,
		back_pcx.width,
		back_pcx.height,
		back_pcx.pixels,
	) or_return

	gfx.hud_bg = load_planar_chunk_tex(r, dat, .NEW_HUD_IMG) or_return
	gfx.hud_stuff = load_planar_chunk_tex(r, dat, .HUDSTUFF_IMG) or_return

	assets.palette_clear(&gfx.palette)
	if gp, gok := assets.get_chunk(dat, .GAMEPAL_PAL); gok {
		assets.load_vga_palette_chunk(&gfx.palette, gp, 0)
	}
	if bp, bok := assets.get_chunk_offset(dat, .BACK01_PAL, lvl.backdrop_index); bok {
		assets.load_vga_palette_chunk(&gfx.palette, bp, 128)
	}

	return true
}

destroy_level_graphics :: proc(gfx: ^Level_Graphics, r: ^render.GPU_Renderer) {
	if gfx == nil || r == nil {
		return
	}
	render.destroy_indexed_texture(r, &gfx.tileset)
	render.destroy_indexed_texture(r, &gfx.backdrop)
	render.destroy_indexed_texture(r, &gfx.hud_bg)
	render.destroy_indexed_texture(r, &gfx.hud_stuff)
}

draw_level_viewport_px :: proc(
	r: ^render.GPU_Renderer,
	lvl: ^Level_Data,
	gfx: ^Level_Graphics,
	cam_x_px: f32,
	cam_y_px: f32,
) {
	max_cam_x := f32((MAP_WIDTH - 20) * TILE_SIZE)
	max_cam_y := f32((MAP_HEIGHT - 10) * TILE_SIZE)
	cx := clamp(cam_x_px, 0.0, max_cam_x)
	cy := clamp(cam_y_px, 0.0, max_cam_y)

	render.batch_set_scissor(&r.batch, 0, 0, VIEWPORT_W, VIEWPORT_H)

	backdrop_scroll_x := math.mod(cx * 0.5, f32(VIEWPORT_W))
	render.draw_texture_region(
		&r.batch,
		gfx.backdrop,
		backdrop_scroll_x,
		0,
		f32(VIEWPORT_W),
		f32(VIEWPORT_H),
		0,
		0,
		f32(VIEWPORT_W),
		f32(VIEWPORT_H),
		repeat_x = true,
	)

	first_col := int(math.floor(cx / f32(TILE_SIZE)))
	first_row := int(math.floor(cy / f32(TILE_SIZE)))
	off_x := cx - f32(first_col * TILE_SIZE)
	off_y := cy - f32(first_row * TILE_SIZE)
	num_cols := 21 if off_x > 0.001 else 20
	num_rows := 11 if off_y > 0.001 else 10

	for ty in 0 ..< num_rows {
		map_y := first_row + ty
		if map_y < 0 || map_y >= MAP_HEIGHT {
			continue
		}
		row_base := map_y * MAP_WIDTH
		dst_y := f32(ty * TILE_SIZE) - off_y

		for tx in 0 ..< num_cols {
			map_x := first_col + tx
			if map_x < 0 || map_x >= MAP_WIDTH {
				continue
			}
			ti := row_base + map_x
			tile := lvl.map_main[ti]
			if tile == EMPTY_TILE {
				tile = lvl.map_back[ti]
			}
			if tile == EMPTY_TILE {
				continue
			}

			src_x := f32((int(tile) % TILESET_COLS) * TILE_SIZE)
			src_y := f32((int(tile) / TILESET_COLS) * TILE_SIZE)
			dst_x := f32(tx * TILE_SIZE) - off_x

			render.draw_texture_region(
				&r.batch,
				gfx.tileset,
				src_x,
				src_y,
				TILE_SIZE,
				TILE_SIZE,
				dst_x,
				dst_y,
				TILE_SIZE,
				TILE_SIZE,
			)
		}
	}

	render.batch_reset_scissor(&r.batch)
}

@(private)
draw_hud_digit :: proc(
	r: ^render.GPU_Renderer,
	gfx: ^Level_Graphics,
	dst_x, dst_y: f32,
	digit: int,
) {
	d := clamp(digit, 0, 10)
	render.draw_texture_region(&r.batch, gfx.hud_stuff, f32(d * 8), 0, 8, 8, dst_x, dst_y, 8, 8)
}

@(private)
draw_hud_key :: proc(
	r: ^render.GPU_Renderer,
	gfx: ^Level_Graphics,
	dst_x, dst_y: f32,
	key_tile: int,
) {
	k := clamp(key_tile, 0, 2)
	render.draw_texture_region(
		&r.batch,
		gfx.hud_stuff,
		f32(88 + k * 8),
		0,
		8,
		11,
		dst_x,
		dst_y,
		8,
		11,
	)
}

draw_hud :: proc(r: ^render.GPU_Renderer, gfx: ^Level_Graphics, hud: HUD_State) {
	render.draw_texture_region(
		&r.batch,
		gfx.hud_bg,
		0,
		0,
		f32(gfx.hud_bg.width),
		f32(gfx.hud_bg.height),
		0,
		HUD_Y,
		f32(gfx.hud_bg.width),
		f32(gfx.hud_bg.height),
	)

	if hud.flash_level_num > 0 && hud.flash_level_num < 10 {
		draw_hud_digit(r, gfx, 296, 182, 10)
	} else {
		draw_hud_digit(r, gfx, 296, 182, clamp(hud.level_number, 0, 9))
	}

	score_buf: [16]u8
	score_str := fmt.bprintf(score_buf[:], "%d", max(hud.score, 0))
	score_len := len(score_str)
	for i in 0 ..< score_len {
		ch := score_str[i]
		if ch >= '0' && ch <= '9' {
			draw_hud_digit(r, gfx, f32(40 - score_len * 4 + i * 8), 181, int(ch - '0'))
		}
	}

	hp := clamp(hud.health, 0, 100)
	hp_buf: [8]u8
	hp_str := fmt.bprintf(hp_buf[:], "%d", hp)
	hp_len := len(hp_str)
	for i in 0 ..< 3 {
		draw_hud_digit(r, gfx, f32(88 + i * 8), 181, 10)
	}
	for i in 0 ..< hp_len {
		ch := hp_str[i]
		if ch >= '0' && ch <= '9' {
			draw_hud_digit(r, gfx, f32(100 - hp_len * 4 + i * 8), 181, int(ch - '0'))
		}
	}

	draw_hud_digit(r, gfx, 156, 181, clamp(hud.crystals_collected, 0, 9))
	draw_hud_digit(r, gfx, 172, 181, clamp(hud.crystals_total, 0, 9))

	draw_hud_key(r, gfx, 212, 180, 2)
	draw_hud_key(r, gfx, 220, 180, 2)
	if hud.got_key1 && hud.got_key2 {
		draw_hud_key(r, gfx, 212, 180, 0)
		draw_hud_key(r, gfx, 220, 180, 1)
	} else if hud.got_key1 {
		draw_hud_key(r, gfx, 216, 180, 0)
	} else if hud.got_key2 {
		draw_hud_key(r, gfx, 216, 180, 1)
	}
}
