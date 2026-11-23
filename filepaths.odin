package main

import "core:os"
import "core:path/filepath"
import "core:strings"
import sdl "vendor:sdl3"

PREF_APP :: "HocusPocusSDL"

App_Paths :: struct {
	user_dir:      string,
	base_dir:      string,
	sav_path:      string,
	settings_path: string,
	dat_path:      string,
}

@(private)
try_join_existing :: proc(
	parts: []string,
	allocator := context.allocator,
) -> (
	path: string,
	ok: bool,
) {
	candidate, err := filepath.join(parts, context.temp_allocator)
	if err != nil || len(candidate) == 0 {
		return "", false
	}
	if os.exists(candidate) {
		return strings.clone(candidate, allocator), true
	}
	return "", false
}

resolve_dat_path :: proc(
	user_dir, base_dir: string,
	allocator := context.allocator,
) -> (
	path: string,
	ok: bool,
) {
	dat_names := [2]string{"HOCUS.DAT", "hocus.dat"}

	if len(user_dir) > 0 {
		for name in dat_names {
			if found, fok := try_join_existing({user_dir, name}, allocator); fok {
				return found, true
			}
		}
		for name in dat_names {
			if found, fok := try_join_existing({user_dir, "data", name}, allocator); fok {
				return found, true
			}
		}
	}

	if len(base_dir) > 0 {
		for name in dat_names {
			if found, fok := try_join_existing({base_dir, "data", name}, allocator); fok {
				return found, true
			}
		}
	}

	dev_candidates := [4]string {
		"data/HOCUS.DAT",
		"Hocus/data/HOCUS.DAT",
		"files/HOCUS.DAT",
		"HOCUS.DAT",
	}
	for c in dev_candidates {
		if os.exists(c) {
			return strings.clone(c, allocator), true
		}
	}

	return "", false
}

init_app_paths :: proc(p: ^App_Paths, allocator := context.allocator) {
	if p == nil do return
	destroy_app_paths(p, allocator)

	pref_cstr := sdl.GetPrefPath(nil, PREF_APP)
	if pref_cstr != nil {
		defer sdl.free(pref_cstr)
		pref_str := strings.trim_right(string(cstring(pref_cstr)), "/\\")
		p.user_dir = strings.clone(pref_str, allocator)
	} else {
		p.user_dir = strings.clone(".", allocator)
	}

	base_cstr := sdl.GetBasePath()
	if base_cstr != nil {
		base_str := strings.trim_right(string(base_cstr), "/\\")
		p.base_dir = strings.clone(base_str, allocator)
	} else {
		p.base_dir = strings.clone(".", allocator)
	}

	sav_joined, _ := filepath.join({p.user_dir, "HOCUS.SAV"}, allocator)
	p.sav_path = sav_joined

	cfg_joined, _ := filepath.join({p.user_dir, "hocus_sdl.cfg"}, allocator)
	p.settings_path = cfg_joined

	dat_found, dat_ok := resolve_dat_path(p.user_dir, p.base_dir, allocator)
	if dat_ok {
		p.dat_path = dat_found
	}
}

destroy_app_paths :: proc(p: ^App_Paths, allocator := context.allocator) {
	if p == nil do return
	if len(p.user_dir) > 0 do delete(p.user_dir, allocator)
	if len(p.base_dir) > 0 do delete(p.base_dir, allocator)
	if len(p.sav_path) > 0 do delete(p.sav_path, allocator)
	if len(p.settings_path) > 0 do delete(p.settings_path, allocator)
	if len(p.dat_path) > 0 do delete(p.dat_path, allocator)
	p^ = {}
}
