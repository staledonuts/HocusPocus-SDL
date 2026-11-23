package game

import "../assets"
import "../render"

SPR_PLAYER :: 0
SPR_SCORETAGS :: 1
SPR_MORPH :: 2
SPR_TWINKS :: 3
SPR_ENEMY_0 :: 4
MAX_SPRITES :: 10

FLASH_WHITE_COLOR :: u8(0x60)
FLASH_RED_COLOR :: u8(0x70)

Sprite_Flash :: enum {
	None,
	Red,
	White,
}

Atlas_Frame :: struct {
	x, y:  int,
	w, h:  int,
	valid: bool,
}

Sprite_Bank :: struct {
	atlas:       render.Indexed_Texture,
	infos:       [MAX_SPRITES]assets.Sprite_Info,
	frames:      [MAX_SPRITES][2][assets.MAX_SPRITE_FRAMES]Atlas_Frame,
	slot_loaded: [MAX_SPRITES]bool,
}

destroy_sprite_bank :: proc(bank: ^Sprite_Bank, r: ^render.GPU_Renderer) {
	if bank == nil || r == nil {
		return
	}
	render.destroy_indexed_texture(r, &bank.atlas)
	bank^ = {}
}

load_level_sprites :: proc(
	bank: ^Sprite_Bank,
	r: ^render.GPU_Renderer,
	dat: ^assets.Dat_File,
	lvl: ^Level_Data,
) -> bool {
	destroy_sprite_bank(bank, r)

	sprite_numbers: [MAX_SPRITES]int
	for &n in sprite_numbers {
		n = -1
	}
	sprite_numbers[SPR_PLAYER] = 0
	sprite_numbers[SPR_SCORETAGS] = 1
	sprite_numbers[SPR_MORPH] = 3
	sprite_numbers[SPR_TWINKS] = 2

	for i in 0 ..< 6 {
		if lvl.enemy_infos[i].sprite != -1 {
			sprite_numbers[SPR_ENEMY_0 + i] = int(lvl.enemy_infos[i].sprite)
		}
	}

	decoded: [MAX_SPRITES]assets.Decoded_Sprite
	defer {
		for &spr in decoded {
			assets.destroy_decoded_sprite(&spr)
		}
	}

	ATLAS_W :: 512
	PAD :: 1

	cur_x := PAD
	cur_y := PAD
	row_h := 0

	for s in 0 ..< MAX_SPRITES {
		num := sprite_numbers[s]
		if num < 0 {
			continue
		}
		spr, ok := assets.decode_sprite(dat, num)
		if !ok {
			continue
		}
		decoded[s] = spr
		bank.infos[s] = spr.info
		bank.slot_loaded[s] = true

		for d in 0 ..< 2 {
			for f in 0 ..< assets.MAX_SPRITE_FRAMES {
				fr := spr.frames[d][f]
				if !fr.valid {
					continue
				}
				if cur_x + fr.width + PAD > ATLAS_W {
					cur_x = PAD
					cur_y += row_h + PAD
					row_h = 0
				}
				bank.frames[s][d][f] = Atlas_Frame {
					x     = cur_x,
					y     = cur_y,
					w     = fr.width,
					h     = fr.height,
					valid = true,
				}
				cur_x += fr.width + PAD
				if fr.height > row_h {
					row_h = fr.height
				}
			}
		}
	}

	atlas_h := max(cur_y + row_h + PAD, 16)
	atlas_rg8 := make([]u8, ATLAS_W * atlas_h * 2, context.temp_allocator)

	for s in 0 ..< MAX_SPRITES {
		if !bank.slot_loaded[s] {
			continue
		}
		for d in 0 ..< 2 {
			for f in 0 ..< assets.MAX_SPRITE_FRAMES {
				af := bank.frames[s][d][f]
				if !af.valid {
					continue
				}
				fr := decoded[s].frames[d][f]
				for y in 0 ..< fr.height {
					for x in 0 ..< fr.width {
						src := (y * fr.width + x) * 2
						dst := ((af.y + y) * ATLAS_W + (af.x + x)) * 2
						atlas_rg8[dst + 0] = fr.pixels_rg8[src + 0]
						atlas_rg8[dst + 1] = fr.pixels_rg8[src + 1]
					}
				}
			}
		}
	}

	tex, ok := render.create_indexed_texture_rg8(r, ATLAS_W, atlas_h, atlas_rg8)
	if !ok {
		destroy_sprite_bank(bank, r)
		return false
	}
	bank.atlas = tex
	return true
}

draw_sprite_px :: proc(
	r: ^render.GPU_Renderer,
	bank: ^Sprite_Bank,
	slot: int,
	x_px: f32,
	y_px: f32,
	dir: int,
	frame: int,
	flash: Sprite_Flash = .None,
) {
	if slot < 0 || slot >= MAX_SPRITES || !bank.slot_loaded[slot] {
		return
	}
	if dir < 0 || dir >= 2 || frame < 0 || frame >= assets.MAX_SPRITE_FRAMES {
		return
	}
	af := bank.frames[slot][dir][frame]
	if !af.valid {
		return
	}

	mode := render.Quad_Mode.Textured
	color_idx: u8 = 0
	switch flash {
	case .None:
	case .Red:
		mode = .Flash
		color_idx = FLASH_RED_COLOR
	case .White:
		mode = .Flash
		color_idx = FLASH_WHITE_COLOR
	}

	render.draw_texture_region(
		&r.batch,
		bank.atlas,
		f32(af.x),
		f32(af.y),
		f32(af.w),
		f32(af.h),
		x_px,
		y_px,
		f32(af.w),
		f32(af.h),
		mode = mode,
		color_index = color_idx,
	)
}

draw_sprite :: proc(
	r: ^render.GPU_Renderer,
	bank: ^Sprite_Bank,
	slot: int,
	x_col4: int,
	y_px: int,
	dir: int,
	frame: int,
	flash: Sprite_Flash = .None,
) {
	draw_sprite_px(r, bank, slot, f32(x_col4 * 4), f32(y_px), dir, frame, flash)
}
