package assets

import "core:mem"

Text_Page :: struct #packed {
	line_count:  i16le,
	line_height: i16le,
	null_height: i16le,
	line_info:   [40]i16le,
	lines:       [20][80]u8,
}
#assert(size_of(Text_Page) == 1686)

load_text_page :: proc(page: ^Text_Page, dat: ^Dat_File, id: Chunk_ID) -> bool {
	if page == nil || dat == nil do return false
	chunk, ok := get_chunk(dat, id)
	if !ok || len(chunk) < size_of(Text_Page) {
		return false
	}
	mem.copy(page, raw_data(chunk), size_of(Text_Page))
	return true
}

load_text_page_offset :: proc(
	page: ^Text_Page,
	dat: ^Dat_File,
	base_id: Chunk_ID,
	offset: int,
) -> bool {
	if page == nil || dat == nil do return false
	chunk, ok := get_chunk_offset(dat, base_id, offset)
	if !ok || len(chunk) < size_of(Text_Page) {
		return false
	}
	mem.copy(page, raw_data(chunk), size_of(Text_Page))
	return true
}

Sin_Cos_Entry :: struct #packed {
	sin_val: f32le,
	cos_val: f32le,
}
#assert(size_of(Sin_Cos_Entry) == 8)

load_sincos_table :: proc(tbl: ^[360]Sin_Cos_Entry, dat: ^Dat_File) -> bool {
	if tbl == nil || dat == nil do return false
	chunk, ok := get_chunk(dat, .SINCOS_TBL)
	if !ok || len(chunk) < 360 * size_of(Sin_Cos_Entry) {
		return false
	}
	mem.copy(tbl, raw_data(chunk), 360 * size_of(Sin_Cos_Entry))
	return true
}

cstr_slice :: proc(buf: []u8) -> string {
	n := 0
	for n < len(buf) && buf[n] != 0 {
		n += 1
	}
	return string(buf[:n])
}
