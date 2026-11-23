package assets

Image_Info :: struct #packed {
	width_div4: i16le,
	height:     i16le,
}

#assert(size_of(Image_Info) == 4)

Planar_Image :: struct {
	width:  int,
	height: int,
	pixels: []u8,
}

destroy_planar_image :: proc(img: ^Planar_Image, allocator := context.allocator) {
	if img == nil {
		return
	}
	if img.pixels != nil {
		delete(img.pixels, allocator)
		img.pixels = nil
	}
	img.width = 0
	img.height = 0
}

decode_planar_image :: proc(
	data: []u8,
	allocator := context.allocator,
) -> (
	img: Planar_Image,
	ok: bool,
) {
	if len(data) < size_of(Image_Info) {
		return {}, false
	}

	info := (^Image_Info)(raw_data(data))^
	w4 := int(info.width_div4)
	h := int(info.height)
	if w4 <= 0 || h <= 0 {
		return {}, false
	}

	expected_bytes := size_of(Image_Info) + 4 * w4 * h
	if len(data) < expected_bytes {
		return {}, false
	}

	width := w4 * 4
	pixels := make([]u8, width * h, allocator)
	if pixels == nil {
		return {}, false
	}

	pos := size_of(Image_Info)
	for plane in 0 ..< 4 {
		for y in 0 ..< h {
			row_base := y * width
			for x4 in 0 ..< w4 {
				pixels[row_base + x4 * 4 + plane] = data[pos]
				pos += 1
			}
		}
	}

	return Planar_Image{width = width, height = h, pixels = pixels}, true
}
