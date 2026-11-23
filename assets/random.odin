package assets

Rand_Table :: struct {
	values: [1000]i16,
	index:  int,
}

load_rand_table :: proc(rt: ^Rand_Table, dat: ^Dat_File) -> bool {
	chunk, ok := get_chunk(dat, .RANDOM_TBL)
	if !ok || len(chunk) < 2000 {
		return false
	}
	raw := (^[1000]i16le)(raw_data(chunk))
	for i in 0 ..< 1000 {
		rt.values[i] = i16(raw[i])
	}
	rt.index = 0
	return true
}

rand_reset :: proc(rt: ^Rand_Table) {
	rt.index = 0
}

rand_next :: proc(rt: ^Rand_Table, max_val: i16) -> i16 {
	if max_val <= 0 {
		return 0
	}
	rt.index += 1
	if rt.index > 999 {
		rt.index = 0
	}
	return rt.values[rt.index] % max_val
}
