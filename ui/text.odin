package ui

import "../assets"
import "../render"

Gradient_Color :: enum u8 {
	Black     = 0,
	Blue      = 1,
	Red       = 2,
	Green     = 3,
	White     = 4,
	Gold      = 5,
	Pink      = 6,
	Red_Hi    = 7,
	Yellow_Hi = 8,
	Green2    = 9,
}

GRADIENT_BASE_COLORS := [10]u8{0x80, 0xC0, 0xC8, 0xD0, 0xD8, 0xE0, 0xE8, 0x70, 0x68, 0xD0}

GPU_Font :: struct {
	data: assets.Bitmap_Font,
	tex:  render.Indexed_Texture,
}

init_gpu_font :: proc(f: ^GPU_Font, r: ^render.GPU_Renderer, dat: ^assets.Dat_File) -> bool {
	if !assets.load_bitmap_font(&f.data, dat) {
		return false
	}
	tex, ok := render.create_indexed_texture_rg8(
		r,
		assets.FONT_ATLAS_W,
		assets.FONT_ATLAS_H,
		f.data.atlas_rg8[:],
	)
	if !ok {
		return false
	}
	f.tex = tex
	return true
}

destroy_gpu_font :: proc(f: ^GPU_Font, r: ^render.GPU_Renderer) {
	if f == nil || r == nil do return
	render.destroy_indexed_texture(r, &f.tex)
	f^ = {}
}

text_width :: proc(f: ^GPU_Font, text: string) -> int {
	return assets.font_text_width(&f.data, text)
}

draw_text_plain :: proc(
	r: ^render.GPU_Renderer,
	f: ^GPU_Font,
	x, y: int,
	color_idx: u8,
	text: string,
) {
	if !f.data.loaded || f.tex.handle == nil do return
	cx := x
	for i in 0 ..< len(text) {
		c := text[i]
		if c >= assets.FONT_FIRST_CHAR && c <= assets.FONT_LAST_CHAR {
			g := int(c - assets.FONT_FIRST_CHAR)
			sx := f32((g % assets.FONT_ATLAS_COLS) * assets.FONT_GLYPH_W)
			sy := f32((g / assets.FONT_ATLAS_COLS) * assets.FONT_GLYPH_H)
			render.draw_texture_region(
				&r.batch,
				f.tex,
				sx,
				sy,
				assets.FONT_GLYPH_W,
				assets.FONT_GLYPH_H,
				f32(cx),
				f32(y),
				assets.FONT_GLYPH_W,
				assets.FONT_GLYPH_H,
				mode = .Flash,
				color_index = color_idx,
			)
			cx += f.data.glyph_widths[g]
		} else if c == ' ' {
			cx += 4
		}
	}
}

draw_text_gradient :: proc(
	r: ^render.GPU_Renderer,
	f: ^GPU_Font,
	x, y: int,
	grd: Gradient_Color,
	text: string,
) {
	if !f.data.loaded || f.tex.handle == nil do return
	if grd == .Black {
		draw_text_plain(r, f, x, y, 0x80, text)
		return
	}
	base_color := GRADIENT_BASE_COLORS[int(grd)]
	cx := x
	for i in 0 ..< len(text) {
		c := text[i]
		if c >= assets.FONT_FIRST_CHAR && c <= assets.FONT_LAST_CHAR {
			g := int(c - assets.FONT_FIRST_CHAR)
			sx := f32((g % assets.FONT_ATLAS_COLS) * assets.FONT_GLYPH_W)
			sy := f32((g / assets.FONT_ATLAS_COLS) * assets.FONT_GLYPH_H)
			render.draw_texture_region(
				&r.batch,
				f.tex,
				sx,
				sy,
				assets.FONT_GLYPH_W,
				assets.FONT_GLYPH_H,
				f32(cx),
				f32(y),
				assets.FONT_GLYPH_W,
				assets.FONT_GLYPH_H,
				mode = .Gradient,
				color_index = base_color,
			)
			cx += f.data.glyph_widths[g]
		} else if c == ' ' {
			cx += 4
		}
	}
}

draw_text_gs :: proc(
	r: ^render.GPU_Renderer,
	f: ^GPU_Font,
	x, y: int,
	grd: Gradient_Color,
	text: string,
) {
	draw_text_plain(r, f, x + 1, y + 1, 0x80, text)
	draw_text_gradient(r, f, x, y, grd, text)
}

draw_text_gob :: proc(
	r: ^render.GPU_Renderer,
	f: ^GPU_Font,
	x, y: int,
	grd: Gradient_Color,
	text: string,
) {
	draw_text_plain(r, f, x + 1, y, 1, text)
	draw_text_plain(r, f, x - 1, y, 1, text)
	draw_text_plain(r, f, x, y + 1, 1, text)
	draw_text_plain(r, f, x, y - 1, 1, text)
	draw_text_gradient(r, f, x, y, grd, text)
}

draw_text_g_centered :: proc(
	r: ^render.GPU_Renderer,
	f: ^GPU_Font,
	y: int,
	grd: Gradient_Color,
	text: string,
) {
	x := (render.SCREEN_WIDTH - text_width(f, text)) / 2
	draw_text_gradient(r, f, x, y, grd, text)
}

draw_text_gs_centered :: proc(
	r: ^render.GPU_Renderer,
	f: ^GPU_Font,
	y: int,
	grd: Gradient_Color,
	text: string,
) {
	x := (render.SCREEN_WIDTH - text_width(f, text)) / 2
	draw_text_gs(r, f, x, y, grd, text)
}

draw_menu_item :: proc(
	r: ^render.GPU_Renderer,
	f: ^GPU_Font,
	x, y: int,
	first_grd, rest_grd: Gradient_Color,
	text: string,
) {
	if len(text) == 0 do return
	draw_text_gradient(r, f, x, y, rest_grd, text)
	draw_text_gradient(r, f, x, y, first_grd, text[:1])
}

draw_ingame_text_centered :: proc(r: ^render.GPU_Renderer, f: ^GPU_Font, y: int, text: string) {
	x := (render.SCREEN_WIDTH - text_width(f, text)) / 2
	draw_text_plain(r, f, x + 1, y + 1, 1, text)
	draw_text_plain(r, f, x, y, 0x68, text)
}
