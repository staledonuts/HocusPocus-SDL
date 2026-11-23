package ui

import "../assets"
import "../render"

UI_Assets :: struct {
	font:         GPU_Font,
	starfield:    Starfield,
	menu_palette: assets.Palette,
	hocus_logo:   render.Indexed_Texture,
	bottom_bar:   render.Indexed_Texture,
	bullit:       render.Indexed_Texture,
	crystal_box:  render.Indexed_Texture,
	regist_bar:   render.Indexed_Texture,
	screen_pcx:   render.Indexed_Texture,
	screen_pal:   assets.Palette,
	page_pic:     render.Indexed_Texture,
	page_pic_x:   int,
	page_pic_y:   int,
}

@(private)
load_planar_tex :: proc(
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

init_ui_assets :: proc(u: ^UI_Assets, r: ^render.GPU_Renderer, dat: ^assets.Dat_File) -> bool {
	destroy_ui_assets(u, r)
	u^ = {}

	if !init_gpu_font(&u.font, r, dat) {
		destroy_ui_assets(u, r)
		return false
	}
	_ = init_starfield(&u.starfield, dat)

	assets.palette_clear(&u.menu_palette)
	if gp, ok := assets.get_chunk(dat, .GAMEPAL_PAL); ok {
		assets.load_vga_palette_chunk(&u.menu_palette, gp, 0)
	}
	if mp, ok := assets.get_chunk(dat, .MENUPAL_PAL); ok {
		assets.load_vga_palette_chunk(&u.menu_palette, mp, 128)
	}

	u.hocus_logo, _ = load_planar_tex(r, dat, .HOCUS_IMG)
	u.bottom_bar, _ = load_planar_tex(r, dat, .BOTTOM_IMG)
	u.bullit, _ = load_planar_tex(r, dat, .BULLIT_IMG)
	u.crystal_box, _ = load_planar_tex(r, dat, .CRYSTAL_IMG)
	if assets.has_chunk(dat, .REGIST_IMG) {
		u.regist_bar, _ = load_planar_tex(r, dat, .REGIST_IMG)
	}

	return true
}

destroy_ui_assets :: proc(u: ^UI_Assets, r: ^render.GPU_Renderer) {
	if u == nil || r == nil do return
	destroy_gpu_font(&u.font, r)
	render.destroy_indexed_texture(r, &u.hocus_logo)
	render.destroy_indexed_texture(r, &u.bottom_bar)
	render.destroy_indexed_texture(r, &u.bullit)
	render.destroy_indexed_texture(r, &u.crystal_box)
	render.destroy_indexed_texture(r, &u.regist_bar)
	render.destroy_indexed_texture(r, &u.screen_pcx)
	render.destroy_indexed_texture(r, &u.page_pic)
}

load_screen_pcx :: proc(
	u: ^UI_Assets,
	r: ^render.GPU_Renderer,
	dat: ^assets.Dat_File,
	id: assets.Chunk_ID,
) -> bool {
	render.destroy_indexed_texture(r, &u.screen_pcx)
	chunk, cok := assets.get_chunk(dat, id)
	if !cok do return false
	pcx, dok := assets.decode_pcx(chunk)
	if !dok do return false
	defer assets.destroy_pcx(&pcx)

	tex, tok := render.create_indexed_texture_from_indices(r, pcx.width, pcx.height, pcx.pixels)
	if !tok do return false
	u.screen_pcx = tex
	u.screen_pal = pcx.palette
	return true
}

load_page_pic :: proc(
	u: ^UI_Assets,
	r: ^render.GPU_Renderer,
	dat: ^assets.Dat_File,
	id: assets.Chunk_ID,
	x_col4, y_px: int,
) {
	render.destroy_indexed_texture(r, &u.page_pic)
	if id == .NONE do return
	if tex, ok := load_planar_tex(r, dat, id); ok {
		u.page_pic = tex
		u.page_pic_x = x_col4 * 4
		u.page_pic_y = y_px
	}
}

draw_menu_chrome :: proc(r: ^render.GPU_Renderer, u: ^UI_Assets, bottom_hint: string) {
	draw_starfield(r, &u.starfield)
	if u.hocus_logo.handle != nil {
		render.draw_texture_region(
			&r.batch,
			u.hocus_logo,
			0,
			0,
			f32(u.hocus_logo.width),
			f32(u.hocus_logo.height),
			0,
			0,
			f32(u.hocus_logo.width),
			f32(u.hocus_logo.height),
		)
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
	if len(bottom_hint) > 0 {
		draw_text_gs_centered(r, &u.font, 188, .White, bottom_hint)
	}
}

draw_menu_cursor :: proc(
	r: ^render.GPU_Renderer,
	u: ^UI_Assets,
	x_px, y_px: int,
	cursor_tick: int,
) {
	if u.bullit.handle == nil do return
	frame := (cursor_tick / 5) % 8
	render.draw_texture_region(
		&r.batch,
		u.bullit,
		f32(frame * 16),
		0,
		16,
		15,
		f32(x_px),
		f32(y_px),
		16,
		15,
	)
}
