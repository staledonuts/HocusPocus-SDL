package assets

Pcx_Header :: struct #packed {
	manufacturer:   u8,
	version:        u8,
	encoding:       u8,
	bits_per_pixel: u8,
	x_min:          u16le,
	y_min:          u16le,
	x_max:          u16le,
	y_max:          u16le,
	h_dpi:          u16le,
	v_dpi:          u16le,
	colormap:       [48]u8,
	reserved:       u8,
	n_planes:       u8,
	bytes_per_line: u16le,
	palette_info:   u16le,
	h_screen_size:  u16le,
	v_screen_size:  u16le,
	filler:         [54]u8,
}

#assert(size_of(Pcx_Header) == 128)

Pcx_Image :: struct {
	width:       int,
	height:      int,
	pixels:      []u8,
	palette:     Palette,
	has_palette: bool,
}

destroy_pcx :: proc(img: ^Pcx_Image, allocator := context.allocator) {
	if img == nil {
		return
	}
	if img.pixels != nil {
		delete(img.pixels, allocator)
		img.pixels = nil
	}
	img.width = 0
	img.height = 0
	img.has_palette = false
}

decode_pcx :: proc(data: []u8, allocator := context.allocator) -> (img: Pcx_Image, ok: bool) {
	if len(data) < size_of(Pcx_Header) {
		return {}, false
	}

	header := (^Pcx_Header)(raw_data(data))^
	if header.manufacturer != 0x0A || header.bits_per_pixel != 8 || header.n_planes != 1 {
		return {}, false
	}

	if header.x_max < header.x_min || header.y_max < header.y_min {
		return {}, false
	}

	width := int(header.x_max - header.x_min) + 1
	height := int(header.y_max - header.y_min) + 1
	bytes_per_line := int(header.bytes_per_line)
	if width <= 0 || height <= 0 || bytes_per_line < width {
		return {}, false
	}

	pixels := make([]u8, width * height, allocator)
	if pixels == nil {
		return {}, false
	}

	pixel_data_end := len(data)
	has_palette := false
	palette: Palette
	if len(data) >= size_of(Pcx_Header) + 769 && data[len(data) - 769] == 0x0C {
		has_palette = load_rgb8_palette(&palette, data[len(data) - 768:])
		pixel_data_end = len(data) - 769
	} else if len(data) >= size_of(Pcx_Header) + 768 {
		has_palette = load_rgb8_palette(&palette, data[len(data) - 768:])
		pixel_data_end = len(data) - 768
	}

	pos := size_of(Pcx_Header)
	for y in 0 ..< height {
		row_base := y * width
		x := 0
		for x < bytes_per_line && pos < pixel_data_end {
			b := data[pos]
			pos += 1
			if (b & 0xC0) == 0xC0 {
				count := int(b & 0x3F)
				if pos >= pixel_data_end {
					break
				}
				val := data[pos]
				pos += 1
				for _ in 0 ..< count {
					if x < width {
						pixels[row_base + x] = val
					}
					x += 1
					if x >= bytes_per_line {
						break
					}
				}
			} else {
				if x < width {
					pixels[row_base + x] = b
				}
				x += 1
			}
		}
	}

	return Pcx_Image {
			width = width,
			height = height,
			pixels = pixels,
			palette = palette,
			has_palette = has_palette,
		},
		true
}
