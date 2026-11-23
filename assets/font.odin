package assets

FONT_FIRST_CHAR :: u8('!')
FONT_LAST_CHAR :: u8('z')
FONT_NUM_GLYPHS :: int(FONT_LAST_CHAR - FONT_FIRST_CHAR) + 1
FONT_GLYPH_W :: 8
FONT_GLYPH_H :: 8
FONT_ATLAS_COLS :: 16
FONT_ATLAS_ROWS :: 6
FONT_ATLAS_W :: FONT_ATLAS_COLS * FONT_GLYPH_W
FONT_ATLAS_H :: FONT_ATLAS_ROWS * FONT_GLYPH_H

Bitmap_Font :: struct {
	glyph_widths: [FONT_NUM_GLYPHS]int,
	atlas_rg8:    [FONT_ATLAS_W * FONT_ATLAS_H * 2]u8,
	loaded:       bool,
}

load_bitmap_font :: proc(font: ^Bitmap_Font, dat: ^Dat_File) -> bool {
	if font == nil || dat == nil {
		return false
	}
	chunk, ok := get_chunk(dat, .FONT_MSK)
	if !ok || len(chunk) < FONT_NUM_GLYPHS * 8 {
		return false
	}

	font^ = {}
	for g in 0 ..< FONT_NUM_GLYPHS {
		cell_x := (g % FONT_ATLAS_COLS) * FONT_GLYPH_W
		cell_y := (g / FONT_ATLAS_COLS) * FONT_GLYPH_H

		max_col := 0
		for row in 0 ..< 8 {
			bits := chunk[g * 8 + row]
			for col in 0 ..< 8 {
				if (bits & (1 << u8(col))) != 0 {
					if col > max_col {
						max_col = col
					}
					px := cell_x + col
					py := cell_y + row
					dst := (py * FONT_ATLAS_W + px) * 2
					font.atlas_rg8[dst + 0] = 255
					font.atlas_rg8[dst + 1] = 255
				}
			}
		}
		font.glyph_widths[g] = max_col + 2
	}

	font.loaded = true
	return true
}

font_text_width :: proc(font: ^Bitmap_Font, text: string) -> int {
	if font == nil || !font.loaded {
		return 0
	}
	width := 0
	for i in 0 ..< len(text) {
		c := text[i]
		if c >= FONT_FIRST_CHAR && c <= FONT_LAST_CHAR {
			width += font.glyph_widths[c - FONT_FIRST_CHAR]
		} else if c == ' ' {
			width += 4
		}
	}
	return width
}
