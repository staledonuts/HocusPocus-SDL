package assets

Palette :: [256][4]u8

vga6_to_u8 :: proc(v: u8) -> u8 {
	c := v & 0x3F
	return (c << 2) | (c >> 4)
}

palette_clear :: proc(pal: ^Palette) {
	for i in 0 ..< 256 {
		pal[i] = {0, 0, 0, 255}
	}
}

load_vga_palette_chunk :: proc(pal: ^Palette, data: []u8, first_color: int) -> bool {
	num_colors := len(data) / 3
	if first_color < 0 || first_color + num_colors > 256 {
		return false
	}
	for i in 0 ..< num_colors {
		r := vga6_to_u8(data[i * 3 + 0])
		g := vga6_to_u8(data[i * 3 + 1])
		b := vga6_to_u8(data[i * 3 + 2])
		pal[first_color + i] = {r, g, b, 255}
	}
	return true
}

load_rgb8_palette :: proc(pal: ^Palette, data: []u8) -> bool {
	if len(data) < 768 {
		return false
	}
	for i in 0 ..< 256 {
		pal[i] = {data[i * 3 + 0], data[i * 3 + 1], data[i * 3 + 2], 255}
	}
	return true
}
