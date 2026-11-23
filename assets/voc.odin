package assets

Voc_Sound :: struct {
	samples:     []u8,
	sample_rate: int,
	channels:    int,
}

destroy_voc :: proc(v: ^Voc_Sound, allocator := context.allocator) {
	if v == nil {
		return
	}
	if v.samples != nil {
		delete(v.samples, allocator)
		v.samples = nil
	}
	v.sample_rate = 0
	v.channels = 0
}

decode_voc :: proc(data: []u8, allocator := context.allocator) -> (voc: Voc_Sound, ok: bool) {
	if len(data) < 26 {
		return {}, false
	}
	if string(data[:19]) != "Creative Voice File" {
		return {}, false
	}

	header_size := int(u16(data[20]) | (u16(data[21]) << 8))
	if header_size < 26 || header_size >= len(data) {
		return {}, false
	}

	out := make([dynamic]u8, 0, len(data) - header_size, allocator)
	sample_rate := 11111
	channels := 1

	pos := header_size
	for pos < len(data) {
		block_type := data[pos]
		pos += 1
		if block_type == 0 {
			break
		}
		if pos + 3 > len(data) {
			break
		}
		block_len := int(u32(data[pos]) | (u32(data[pos + 1]) << 8) | (u32(data[pos + 2]) << 16))
		pos += 3
		if block_len < 0 || pos + block_len > len(data) {
			block_len = len(data) - pos
		}
		block := data[pos:pos + block_len]
		pos += block_len

		switch block_type {
		case 1:
			if len(block) >= 2 {
				sr_div := int(block[0])
				codec := block[1]
				if sr_div < 256 {
					sample_rate = 1_000_000 / max(256 - sr_div, 1)
				}
				if codec == 0 {
					append(&out, ..block[2:])
				}
			}
		case 2:
			append(&out, ..block)
		case 3:
			if len(block) >= 3 {
				sil_len := int(u16(block[0]) | (u16(block[1]) << 8)) + 1
				sr_div := int(block[2])
				if sr_div < 256 {
					sample_rate = 1_000_000 / max(256 - sr_div, 1)
				}
				for _ in 0 ..< sil_len {
					append(&out, u8(128))
				}
			}
		case 9:
			if len(block) >= 12 {
				sr := int(
					u32(block[0]) |
					(u32(block[1]) << 8) |
					(u32(block[2]) << 16) |
					(u32(block[3]) << 24),
				)
				bits := block[4]
				ch := int(block[5])
				if sr > 0 do sample_rate = sr
				if ch > 0 do channels = ch
				if bits == 8 {
					append(&out, ..block[12:])
				}
			}
		}
	}

	if len(out) == 0 {
		delete(out)
		return {}, false
	}
	shrink(&out)

	return Voc_Sound{samples = out[:], sample_rate = sample_rate, channels = channels}, true
}
