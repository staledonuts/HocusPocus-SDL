package assets

MAX_SPRITE_FRAMES :: 20

Sprite_Info :: struct #packed {
	offset:             u32le,
	name:               [22]u8,
	width:              i16le,
	height:             i16le,
	stand_frame:        i16le,
	stand_end:          i16le,
	walk_start:         i16le,
	walk_end:           i16le,
	jump_start:         i16le,
	jump_end:           i16le,
	shoot_start:        i16le,
	shoot_end:          i16le,
	projectile_width:   i16le,
	projectile_height:  i16le,
	projectile_delta_y: i16le,
	projectile_start:   i16le,
	projectile_end:     i16le,
	layout_size:        u16le,
	pixels_size:        u16le,
	layout_starts:      [2][MAX_SPRITE_FRAMES]u16le,
	pixels_starts:      [2][MAX_SPRITE_FRAMES]u16le,
}
#assert(size_of(Sprite_Info) == 220)

Sprite_Frame :: struct {
	width:      int,
	height:     int,
	pixels_rg8: []u8,
	valid:      bool,
}

Decoded_Sprite :: struct {
	info:   Sprite_Info,
	frames: [2][MAX_SPRITE_FRAMES]Sprite_Frame,
}

destroy_decoded_sprite :: proc(spr: ^Decoded_Sprite, allocator := context.allocator) {
	if spr == nil {
		return
	}
	for d in 0 ..< 2 {
		for f in 0 ..< MAX_SPRITE_FRAMES {
			if spr.frames[d][f].pixels_rg8 != nil {
				delete(spr.frames[d][f].pixels_rg8, allocator)
				spr.frames[d][f].pixels_rg8 = nil
			}
			spr.frames[d][f].valid = false
		}
	}
}

sprite_name :: proc(info: ^Sprite_Info) -> string {
	return cstr_slice(info.name[:])
}

decode_sprite :: proc(
	dat: ^Dat_File,
	sprite_index: int,
	allocator := context.allocator,
) -> (
	spr: Decoded_Sprite,
	ok: bool,
) {
	chunk, cok := get_chunk(dat, .SPRITES_SPR)
	if !cok || sprite_index < 0 {
		return {}, false
	}

	info_off := sprite_index * size_of(Sprite_Info)
	if info_off + size_of(Sprite_Info) > len(chunk) {
		return {}, false
	}

	info := (^Sprite_Info)(raw_data(chunk[info_off:]))^
	layout_off := int(info.offset)
	layout_size := int(info.layout_size)
	pixels_off := layout_off + layout_size
	pixels_size := int(info.pixels_size)

	if layout_off < 0 || pixels_off + pixels_size > len(chunk) {
		return {}, false
	}

	layout := chunk[layout_off:layout_off + layout_size]
	pixels := chunk[pixels_off:pixels_off + pixels_size]

	spr.info = info

	canvas := make([]u8, 320 * 200 * 2, context.temp_allocator)
	dir1_start := int(info.layout_starts[1][0])

	for d in 0 ..< 2 {
		prev_lo := -1
		for f in 0 ..< MAX_SPRITE_FRAMES {
			lo := int(info.layout_starts[d][f])
			po := int(info.pixels_starts[d][f]) * 4

			if f > 0 && lo <= prev_lo {
				break
			}
			if lo >= layout_size || po >= pixels_size {
				break
			}
			if d == 0 && dir1_start > 0 && lo >= dir1_start {
				break
			}
			prev_lo = lo

			for i in 0 ..< len(canvas) {
				canvas[i] = 0
			}

			mask: u8 = 0
			col_off := 0
			cur_lo := lo
			cur_po := po
			max_x := -1
			max_y := -1

			for cur_lo < layout_size {
				flag := layout[cur_lo]
				cur_lo += 1
				if flag == 0 {
					if cur_lo >= layout_size {
						break
					}
					mask = layout[cur_lo]
					cur_lo += 1
					col_off = 0
				} else if flag == 1 {
					if cur_lo + 2 > layout_size {
						break
					}
					skip := int(u16(layout[cur_lo]) | (u16(layout[cur_lo + 1]) << 8))
					cur_lo += 2
					col_off += skip
				} else if flag == 2 {
					if cur_po + 4 > pixels_size {
						break
					}
					y := col_off / 80
					x4 := col_off % 80
					if y >= 0 && y < 200 && x4 >= 0 && x4 < 80 {
						for p in 0 ..< 4 {
							if (mask & (1 << u8(p))) != 0 {
								px := x4 * 4 + p
								dst := (y * 320 + px) * 2
								canvas[dst + 0] = pixels[cur_po + p]
								canvas[dst + 1] = 255
								if px > max_x do max_x = px
								if y > max_y do max_y = y
							}
						}
					}
					col_off += 1
					cur_po += 4
				} else {
					break
				}
			}

			fw := max_x + 1
			fh := max_y + 1
			if fw <= 0 || fh <= 0 {
				fw = 1
				fh = 1
			}

			buf := make([]u8, fw * fh * 2, allocator)
			for y in 0 ..< fh {
				for x in 0 ..< fw {
					src := (y * 320 + x) * 2
					dst := (y * fw + x) * 2
					buf[dst + 0] = canvas[src + 0]
					buf[dst + 1] = canvas[src + 1]
				}
			}

			spr.frames[d][f] = Sprite_Frame {
				width      = fw,
				height     = fh,
				pixels_rg8 = buf,
				valid      = true,
			}
		}
	}

	return spr, true
}
