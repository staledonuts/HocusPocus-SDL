package assets

import "core:os"

Dat_File :: struct {
	version:       Dat_Version,
	data:          []u8,
	fat:           []Fat_Entry,
	index_by_name: [Chunk_ID]int,
}

DEFAULT_DAT_PATHS :: [?]string {
	"data/HOCUS.DAT",
	"Hocus/data/HOCUS.DAT",
	"files/HOCUS.DAT",
	"HOCUS.DAT",
}

open_dat_default :: proc(
	allocator := context.allocator,
) -> (
	dat: Dat_File,
	loaded_path: string,
	ok: bool,
) {
	for path in DEFAULT_DAT_PATHS {
		d, loaded := open_dat(path, allocator)
		if loaded {
			return d, path, true
		}
	}
	return {}, "", false
}

open_dat :: proc(path: string, allocator := context.allocator) -> (dat: Dat_File, ok: bool) {
	raw, err := os.read_entire_file(path, allocator)
	if err != nil {
		return {}, false
	}

	version: Dat_Version
	fat: []Fat_Entry

	switch len(raw) {
	case DAT_SIZE_SHAREWARE_11:
		version = .Shareware_11
		fat = FAT_SHAREWARE_11[:]
	case DAT_SIZE_REGISTERED_10:
		version = .Registered_10
		fat = FAT_REGISTERED_10[:]
	case DAT_SIZE_REGISTERED_11:
		version = .Registered_11
		fat = FAT_REGISTERED_11[:]
	case:
		delete(raw, allocator)
		return {}, false
	}

	dat.version = version
	dat.data = raw
	dat.fat = fat
	for &idx in dat.index_by_name {
		idx = -1
	}
	for entry, i in fat {
		dat.index_by_name[entry.name] = i
	}

	return dat, true
}

close_dat :: proc(dat: ^Dat_File, allocator := context.allocator) {
	if dat == nil {
		return
	}
	if dat.data != nil {
		delete(dat.data, allocator)
		dat.data = nil
	}
	dat.fat = nil
	dat.version = .Unknown
}

is_registered :: proc(dat: ^Dat_File) -> bool {
	return dat != nil && (dat.version == .Registered_10 || dat.version == .Registered_11)
}

has_chunk :: proc(dat: ^Dat_File, id: Chunk_ID) -> bool {
	return dat != nil && dat.index_by_name[id] >= 0
}

get_chunk :: proc(dat: ^Dat_File, id: Chunk_ID) -> (chunk: []u8, ok: bool) {
	if dat == nil {
		return nil, false
	}
	idx := dat.index_by_name[id]
	if idx < 0 {
		return nil, false
	}
	return get_chunk_by_index(dat, idx)
}

get_chunk_offset :: proc(
	dat: ^Dat_File,
	base_id: Chunk_ID,
	offset: int,
) -> (
	chunk: []u8,
	ok: bool,
) {
	if dat == nil {
		return nil, false
	}
	base_idx := dat.index_by_name[base_id]
	if base_idx < 0 {
		return nil, false
	}
	return get_chunk_by_index(dat, base_idx + offset)
}

get_chunk_by_index :: proc(dat: ^Dat_File, index: int) -> (chunk: []u8, ok: bool) {
	if dat == nil || index < 0 || index >= len(dat.fat) {
		return nil, false
	}
	entry := dat.fat[index]
	start := int(entry.offset)
	end := start + int(entry.size)
	if start < 0 || end > len(dat.data) {
		return nil, false
	}
	return dat.data[start:end], true
}
