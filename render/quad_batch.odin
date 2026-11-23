package render

import "core:mem"
import sdl "vendor:sdl3"

MAX_BATCH_QUADS :: 4096
MAX_DRAW_CALLS :: 64

Quad_Mode :: enum u8 {
	Textured = 0,
	Solid    = 1,
	Flash    = 2,
	Gradient = 3,
}

Quad_Instance :: struct #align (16) {
	dst_rect: [4]f32,
	uv_rect:  [4]f32,
	params:   [4]f32,
}
#assert(size_of(Quad_Instance) == 48)

Scene_Uniforms :: struct {
	screen_size: [4]f32,
}

Indexed_Texture :: struct {
	handle: ^sdl.GPUTexture,
	width:  int,
	height: int,
}

Draw_Call :: struct {
	texture:        ^sdl.GPUTexture,
	repeat_x:       bool,
	scissor:        sdl.Rect,
	first_instance: u32,
	instance_count: u32,
}

Quad_Batch :: struct {
	storage_buffer:  ^sdl.GPUBuffer,
	transfer_buffer: ^sdl.GPUTransferBuffer,
	pipeline:        ^sdl.GPUGraphicsPipeline,
	dummy_texture:   ^sdl.GPUTexture,
	quads:           [MAX_BATCH_QUADS]Quad_Instance,
	quad_count:      int,
	calls:           [MAX_DRAW_CALLS]Draw_Call,
	call_count:      int,
	current_scissor: sdl.Rect,
}

@(private)
SPRITE_VERT_SPV :: #load("shaders/sprite.vert.spv")
@(private)
SPRITE_FRAG_SPV :: #load("shaders/sprite.frag.spv")

init_quad_batch :: proc(device: ^sdl.GPUDevice, b: ^Quad_Batch) -> bool {
	b^ = {}
	b.current_scissor = {0, 0, SCREEN_WIDTH, SCREEN_HEIGHT}

	buf_size := u32(MAX_BATCH_QUADS * size_of(Quad_Instance))
	b.storage_buffer = sdl.CreateGPUBuffer(
		device,
		sdl.GPUBufferCreateInfo{usage = {.GRAPHICS_STORAGE_READ}, size = buf_size},
	)
	if b.storage_buffer == nil {
		destroy_quad_batch(device, b)
		return false
	}

	b.transfer_buffer = sdl.CreateGPUTransferBuffer(
		device,
		sdl.GPUTransferBufferCreateInfo{usage = .UPLOAD, size = buf_size},
	)
	if b.transfer_buffer == nil {
		destroy_quad_batch(device, b)
		return false
	}

	b.dummy_texture = sdl.CreateGPUTexture(
		device,
		sdl.GPUTextureCreateInfo {
			type = .D2,
			format = .R8G8_UNORM,
			usage = {.SAMPLER},
			width = 1,
			height = 1,
			layer_count_or_depth = 1,
			num_levels = 1,
			sample_count = ._1,
		},
	)
	if b.dummy_texture == nil {
		destroy_quad_batch(device, b)
		return false
	}

	vert_code := SPRITE_VERT_SPV
	vert_shader := sdl.CreateGPUShader(
		device,
		sdl.GPUShaderCreateInfo {
			code_size = len(vert_code),
			code = raw_data(vert_code),
			entrypoint = "main",
			format = {.SPIRV},
			stage = .VERTEX,
			num_storage_buffers = 1,
			num_uniform_buffers = 1,
		},
	)
	if vert_shader == nil {
		destroy_quad_batch(device, b)
		return false
	}
	defer sdl.ReleaseGPUShader(device, vert_shader)

	frag_code := SPRITE_FRAG_SPV
	frag_shader := sdl.CreateGPUShader(
		device,
		sdl.GPUShaderCreateInfo {
			code_size = len(frag_code),
			code = raw_data(frag_code),
			entrypoint = "main",
			format = {.SPIRV},
			stage = .FRAGMENT,
			num_samplers = 1,
		},
	)
	if frag_shader == nil {
		destroy_quad_batch(device, b)
		return false
	}
	defer sdl.ReleaseGPUShader(device, frag_shader)

	color_target_desc := sdl.GPUColorTargetDescription {
		format = .R8G8_UNORM,
	}

	b.pipeline = sdl.CreateGPUGraphicsPipeline(
		device,
		sdl.GPUGraphicsPipelineCreateInfo {
			vertex_shader = vert_shader,
			fragment_shader = frag_shader,
			primitive_type = .TRIANGLELIST,
			rasterizer_state = {
				fill_mode = .FILL,
				cull_mode = .NONE,
				front_face = .COUNTER_CLOCKWISE,
			},
			multisample_state = {sample_count = ._1},
			target_info = {color_target_descriptions = &color_target_desc, num_color_targets = 1},
		},
	)
	if b.pipeline == nil {
		destroy_quad_batch(device, b)
		return false
	}

	return true
}

destroy_quad_batch :: proc(device: ^sdl.GPUDevice, b: ^Quad_Batch) {
	if device == nil || b == nil {
		return
	}
	if b.pipeline != nil {
		sdl.ReleaseGPUGraphicsPipeline(device, b.pipeline)
		b.pipeline = nil
	}
	if b.dummy_texture != nil {
		sdl.ReleaseGPUTexture(device, b.dummy_texture)
		b.dummy_texture = nil
	}
	if b.transfer_buffer != nil {
		sdl.ReleaseGPUTransferBuffer(device, b.transfer_buffer)
		b.transfer_buffer = nil
	}
	if b.storage_buffer != nil {
		sdl.ReleaseGPUBuffer(device, b.storage_buffer)
		b.storage_buffer = nil
	}
}

batch_begin :: proc(b: ^Quad_Batch) {
	b.quad_count = 0
	b.call_count = 0
	b.current_scissor = {0, 0, SCREEN_WIDTH, SCREEN_HEIGHT}
}

batch_set_scissor :: proc(b: ^Quad_Batch, x, y, w, h: i32) {
	b.current_scissor = {x, y, w, h}
}

batch_reset_scissor :: proc(b: ^Quad_Batch) {
	b.current_scissor = {0, 0, SCREEN_WIDTH, SCREEN_HEIGHT}
}

batch_push_quad :: proc(
	b: ^Quad_Batch,
	tex: ^sdl.GPUTexture,
	dst_rect: [4]f32,
	uv_rect: [4]f32,
	mode: Quad_Mode = .Textured,
	color_index: u8 = 0,
	repeat_x := false,
) {
	if b.quad_count >= MAX_BATCH_QUADS {
		return
	}

	actual_tex := tex if tex != nil else b.dummy_texture

	if b.call_count > 0 {
		last := &b.calls[b.call_count - 1]
		if last.texture == actual_tex &&
		   last.repeat_x == repeat_x &&
		   last.scissor == b.current_scissor {
			b.quads[b.quad_count] = Quad_Instance {
				dst_rect = dst_rect,
				uv_rect  = uv_rect,
				params   = {f32(mode), f32(color_index), 0, 0},
			}
			b.quad_count += 1
			last.instance_count += 1
			return
		}
	}

	if b.call_count >= MAX_DRAW_CALLS {
		return
	}

	b.calls[b.call_count] = Draw_Call {
		texture        = actual_tex,
		repeat_x       = repeat_x,
		scissor        = b.current_scissor,
		first_instance = u32(b.quad_count),
		instance_count = 1,
	}
	b.call_count += 1

	b.quads[b.quad_count] = Quad_Instance {
		dst_rect = dst_rect,
		uv_rect  = uv_rect,
		params   = {f32(mode), f32(color_index), 0, 0},
	}
	b.quad_count += 1
}

draw_texture_region :: proc(
	b: ^Quad_Batch,
	tex: Indexed_Texture,
	src_x, src_y, src_w, src_h: f32,
	dst_x, dst_y, dst_w, dst_h: f32,
	mode: Quad_Mode = .Textured,
	color_index: u8 = 0,
	repeat_x := false,
) {
	if tex.handle == nil || tex.width <= 0 || tex.height <= 0 {
		return
	}
	inv_w := 1.0 / f32(tex.width)
	inv_h := 1.0 / f32(tex.height)
	uv := [4]f32{src_x * inv_w, src_y * inv_h, (src_x + src_w) * inv_w, (src_y + src_h) * inv_h}
	batch_push_quad(b, tex.handle, {dst_x, dst_y, dst_w, dst_h}, uv, mode, color_index, repeat_x)
}

draw_solid_rect :: proc(b: ^Quad_Batch, x, y, w, h: f32, color_index: u8) {
	batch_push_quad(b, nil, {x, y, w, h}, {0, 0, 1, 1}, .Solid, color_index, false)
}

batch_upload :: proc(device: ^sdl.GPUDevice, b: ^Quad_Batch, copy_pass: ^sdl.GPUCopyPass) {
	if b.quad_count == 0 {
		return
	}
	byte_size := u32(b.quad_count * size_of(Quad_Instance))
	mapped := sdl.MapGPUTransferBuffer(device, b.transfer_buffer, true)
	if mapped != nil {
		mem.copy(mapped, raw_data(b.quads[:]), int(byte_size))
		sdl.UnmapGPUTransferBuffer(device, b.transfer_buffer)
		sdl.UploadToGPUBuffer(
			copy_pass,
			sdl.GPUTransferBufferLocation{transfer_buffer = b.transfer_buffer, offset = 0},
			sdl.GPUBufferRegion{buffer = b.storage_buffer, offset = 0, size = byte_size},
			true,
		)
	}
}
