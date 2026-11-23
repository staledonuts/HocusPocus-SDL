package render

import "../assets"
import "core:mem"
import sdl "vendor:sdl3"

SCREEN_WIDTH :: 320
SCREEN_HEIGHT :: 200

@(private)
PRESENT_VERT_SPV :: #load("shaders/present.vert.spv")
@(private)
PRESENT_FRAG_SPV :: #load("shaders/present.frag.spv")

Aspect_Mode :: enum {
	CRT_4_3,
	Square_16_10,
	Stretch,
}

Fade_State :: struct {
	color:    [3]f32,
	amount:   f32,
	start:    f32,
	target:   f32,
	elapsed:  f32,
	duration: f32,
	active:   bool,
}

Present_Uniforms :: struct {
	fade_color: [4]f32,
	video_opts: [4]f32,
}

GPU_Renderer :: struct {
	device:                   ^sdl.GPUDevice,
	window:                   ^sdl.Window,
	screen_texture:           ^sdl.GPUTexture,
	palette_texture:          ^sdl.GPUTexture,
	nearest_sampler:          ^sdl.GPUSampler,
	nearest_repeat_x_sampler: ^sdl.GPUSampler,
	palette_transfer:         ^sdl.GPUTransferBuffer,
	present_pipeline:         ^sdl.GPUGraphicsPipeline,
	batch:                    Quad_Batch,
	palette:                  assets.Palette,
	palette_dirty:            bool,
	fade:                     Fade_State,
	aspect_mode:              Aspect_Mode,
	integer_scale:            bool,
	scanlines:                f32,
	vsync:                    bool,
}

init_renderer :: proc(
	r: ^GPU_Renderer,
	device: ^sdl.GPUDevice,
	window: ^sdl.Window,
) -> (
	ok: bool,
) {
	if r == nil || device == nil || window == nil {
		return false
	}

	r^ = {}
	r.device = device
	r.window = window
	r.aspect_mode = .CRT_4_3
	r.vsync = true
	assets.palette_clear(&r.palette)
	r.palette_dirty = true
	defer if !ok {
		destroy_renderer(r)
	}

	r.screen_texture = sdl.CreateGPUTexture(
		device,
		sdl.GPUTextureCreateInfo {
			type = .D2,
			format = .R8G8_UNORM,
			usage = {.SAMPLER, .COLOR_TARGET},
			width = SCREEN_WIDTH,
			height = SCREEN_HEIGHT,
			layer_count_or_depth = 1,
			num_levels = 1,
			sample_count = ._1,
		},
	)
	if r.screen_texture == nil do return false

	r.palette_texture = sdl.CreateGPUTexture(
		device,
		sdl.GPUTextureCreateInfo {
			type = .D2,
			format = .R8G8B8A8_UNORM,
			usage = {.SAMPLER},
			width = 256,
			height = 1,
			layer_count_or_depth = 1,
			num_levels = 1,
			sample_count = ._1,
		},
	)
	if r.palette_texture == nil do return false

	r.nearest_sampler = sdl.CreateGPUSampler(
		device,
		sdl.GPUSamplerCreateInfo {
			min_filter = .NEAREST,
			mag_filter = .NEAREST,
			mipmap_mode = .NEAREST,
			address_mode_u = .CLAMP_TO_EDGE,
			address_mode_v = .CLAMP_TO_EDGE,
			address_mode_w = .CLAMP_TO_EDGE,
		},
	)
	if r.nearest_sampler == nil do return false

	r.nearest_repeat_x_sampler = sdl.CreateGPUSampler(
		device,
		sdl.GPUSamplerCreateInfo {
			min_filter = .NEAREST,
			mag_filter = .NEAREST,
			mipmap_mode = .NEAREST,
			address_mode_u = .REPEAT,
			address_mode_v = .CLAMP_TO_EDGE,
			address_mode_w = .CLAMP_TO_EDGE,
		},
	)
	if r.nearest_repeat_x_sampler == nil do return false

	r.palette_transfer = sdl.CreateGPUTransferBuffer(
		device,
		sdl.GPUTransferBufferCreateInfo{usage = .UPLOAD, size = u32(size_of(assets.Palette))},
	)
	if r.palette_transfer == nil do return false

	vert_code := PRESENT_VERT_SPV
	vert_shader := sdl.CreateGPUShader(
		device,
		sdl.GPUShaderCreateInfo {
			code_size = len(vert_code),
			code = raw_data(vert_code),
			entrypoint = "main",
			format = {.SPIRV},
			stage = .VERTEX,
		},
	)
	if vert_shader == nil do return false
	defer sdl.ReleaseGPUShader(device, vert_shader)

	frag_code := PRESENT_FRAG_SPV
	frag_shader := sdl.CreateGPUShader(
		device,
		sdl.GPUShaderCreateInfo {
			code_size = len(frag_code),
			code = raw_data(frag_code),
			entrypoint = "main",
			format = {.SPIRV},
			stage = .FRAGMENT,
			num_samplers = 2,
			num_uniform_buffers = 1,
		},
	)
	if frag_shader == nil do return false
	defer sdl.ReleaseGPUShader(device, frag_shader)

	swapchain_format := sdl.GetGPUSwapchainTextureFormat(device, window)
	color_target_desc := sdl.GPUColorTargetDescription {
		format = swapchain_format,
	}

	r.present_pipeline = sdl.CreateGPUGraphicsPipeline(
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
	if r.present_pipeline == nil do return false

	if !init_quad_batch(device, &r.batch) do return false

	return true
}

destroy_renderer :: proc(r: ^GPU_Renderer) {
	if r == nil || r.device == nil {
		return
	}
	_ = sdl.WaitForGPUIdle(r.device)

	destroy_quad_batch(r.device, &r.batch)

	if r.present_pipeline != nil {
		sdl.ReleaseGPUGraphicsPipeline(r.device, r.present_pipeline)
		r.present_pipeline = nil
	}
	if r.palette_transfer != nil {
		sdl.ReleaseGPUTransferBuffer(r.device, r.palette_transfer)
		r.palette_transfer = nil
	}
	if r.nearest_repeat_x_sampler != nil {
		sdl.ReleaseGPUSampler(r.device, r.nearest_repeat_x_sampler)
		r.nearest_repeat_x_sampler = nil
	}
	if r.nearest_sampler != nil {
		sdl.ReleaseGPUSampler(r.device, r.nearest_sampler)
		r.nearest_sampler = nil
	}
	if r.palette_texture != nil {
		sdl.ReleaseGPUTexture(r.device, r.palette_texture)
		r.palette_texture = nil
	}
	if r.screen_texture != nil {
		sdl.ReleaseGPUTexture(r.device, r.screen_texture)
		r.screen_texture = nil
	}
}

create_indexed_texture_from_indices :: proc(
	r: ^GPU_Renderer,
	width, height: int,
	indices: []u8,
) -> (
	tex: Indexed_Texture,
	ok: bool,
) {
	if r == nil || r.device == nil || width <= 0 || height <= 0 || len(indices) < width * height {
		return {}, false
	}
	rg8 := make([]u8, width * height * 2, context.temp_allocator)
	for i in 0 ..< width * height {
		rg8[i * 2 + 0] = indices[i]
		rg8[i * 2 + 1] = 255
	}
	return create_indexed_texture_rg8(r, width, height, rg8)
}

create_indexed_texture_rg8 :: proc(
	r: ^GPU_Renderer,
	width, height: int,
	rg8: []u8,
) -> (
	tex: Indexed_Texture,
	ok: bool,
) {
	if r == nil || r.device == nil || width <= 0 || height <= 0 || len(rg8) < width * height * 2 {
		return {}, false
	}

	gpu_tex := sdl.CreateGPUTexture(
		r.device,
		sdl.GPUTextureCreateInfo {
			type = .D2,
			format = .R8G8_UNORM,
			usage = {.SAMPLER},
			width = u32(width),
			height = u32(height),
			layer_count_or_depth = 1,
			num_levels = 1,
			sample_count = ._1,
		},
	)
	if gpu_tex == nil {
		return {}, false
	}

	byte_size := u32(width * height * 2)
	tb := sdl.CreateGPUTransferBuffer(
		r.device,
		sdl.GPUTransferBufferCreateInfo{usage = .UPLOAD, size = byte_size},
	)
	if tb == nil {
		sdl.ReleaseGPUTexture(r.device, gpu_tex)
		return {}, false
	}
	defer sdl.ReleaseGPUTransferBuffer(r.device, tb)

	mapped := sdl.MapGPUTransferBuffer(r.device, tb, false)
	if mapped == nil {
		sdl.ReleaseGPUTexture(r.device, gpu_tex)
		return {}, false
	}
	mem.copy(mapped, raw_data(rg8), int(byte_size))
	sdl.UnmapGPUTransferBuffer(r.device, tb)

	cmd := sdl.AcquireGPUCommandBuffer(r.device)
	if cmd == nil {
		sdl.ReleaseGPUTexture(r.device, gpu_tex)
		return {}, false
	}
	copy_pass := sdl.BeginGPUCopyPass(cmd)
	if copy_pass == nil {
		_ = sdl.CancelGPUCommandBuffer(cmd)
		sdl.ReleaseGPUTexture(r.device, gpu_tex)
		return {}, false
	}
	sdl.UploadToGPUTexture(
		copy_pass,
		sdl.GPUTextureTransferInfo {
			transfer_buffer = tb,
			offset = 0,
			pixels_per_row = u32(width),
			rows_per_layer = u32(height),
		},
		sdl.GPUTextureRegion{texture = gpu_tex, w = u32(width), h = u32(height), d = 1},
		false,
	)
	sdl.EndGPUCopyPass(copy_pass)
	if !sdl.SubmitGPUCommandBuffer(cmd) {
		sdl.ReleaseGPUTexture(r.device, gpu_tex)
		return {}, false
	}

	return Indexed_Texture{handle = gpu_tex, width = width, height = height}, true
}

destroy_indexed_texture :: proc(r: ^GPU_Renderer, tex: ^Indexed_Texture) {
	if r == nil || r.device == nil || tex == nil || tex.handle == nil {
		return
	}
	sdl.ReleaseGPUTexture(r.device, tex.handle)
	tex^ = {}
}

set_palette :: proc(r: ^GPU_Renderer, pal: assets.Palette) {
	r.palette = pal
	r.palette_dirty = true
}

fade_from_black :: proc(r: ^GPU_Renderer, duration_sec: f32) {
	r.fade = Fade_State {
		color    = {0, 0, 0},
		amount   = 1.0,
		start    = 1.0,
		target   = 0.0,
		elapsed  = 0.0,
		duration = max(duration_sec, 0.001),
		active   = true,
	}
}

fade_to_black :: proc(r: ^GPU_Renderer, duration_sec: f32) {
	r.fade = Fade_State {
		color    = {0, 0, 0},
		amount   = r.fade.amount,
		start    = r.fade.amount,
		target   = 1.0,
		elapsed  = 0.0,
		duration = max(duration_sec, 0.001),
		active   = true,
	}
}

fade_to_white :: proc(r: ^GPU_Renderer, duration_sec: f32) {
	r.fade = Fade_State {
		color    = {1, 1, 1},
		amount   = 0.0,
		start    = 0.0,
		target   = 1.0,
		elapsed  = 0.0,
		duration = max(duration_sec, 0.001),
		active   = true,
	}
}

update_fade :: proc(r: ^GPU_Renderer, dt: f32) {
	if !r.fade.active {
		return
	}
	r.fade.elapsed += dt
	t := clamp(r.fade.elapsed / r.fade.duration, 0.0, 1.0)
	r.fade.amount = r.fade.start + (r.fade.target - r.fade.start) * t
	if t >= 1.0 {
		r.fade.amount = r.fade.target
		r.fade.active = false
	}
}

set_vsync :: proc(r: ^GPU_Renderer, enabled: bool) {
	if r == nil || r.device == nil || r.window == nil {
		return
	}
	r.vsync = enabled
	mode: sdl.GPUPresentMode = .VSYNC if enabled else .IMMEDIATE
	if !sdl.SetGPUSwapchainParameters(r.device, r.window, .SDR, mode) && !enabled {
		_ = sdl.SetGPUSwapchainParameters(r.device, r.window, .SDR, .VSYNC)
	}
}

compute_present_viewport :: proc(
	win_w, win_h: u32,
	mode: Aspect_Mode,
	integer_scale := false,
) -> sdl.GPUViewport {
	fw := f32(win_w)
	fh := f32(win_h)
	if fw <= 0 || fh <= 0 {
		return {0, 0, 1, 1, 0, 1}
	}

	if mode == .Stretch {
		return {0, 0, fw, fh, 0, 1}
	}

	if integer_scale {
		base_w: u32 = SCREEN_WIDTH
		base_h: u32 = 240 if mode == .CRT_4_3 else SCREEN_HEIGHT
		scale := min(win_w / base_w, win_h / base_h)
		if scale >= 1 {
			vp_w := f32(base_w * scale)
			vp_h := f32(base_h * scale)
			return sdl.GPUViewport {
				x = f32(int((fw - vp_w) * 0.5)),
				y = f32(int((fh - vp_h) * 0.5)),
				w = vp_w,
				h = vp_h,
				min_depth = 0.0,
				max_depth = 1.0,
			}
		}
	}

	target_aspect: f32
	switch mode {
	case .CRT_4_3:
		target_aspect = 4.0 / 3.0
	case .Square_16_10:
		target_aspect = f32(SCREEN_WIDTH) / f32(SCREEN_HEIGHT)
	case .Stretch:
		return {0, 0, fw, fh, 0, 1}
	}

	win_aspect := fw / fh
	vp_w, vp_h: f32
	if win_aspect > target_aspect {
		vp_h = fh
		vp_w = fh * target_aspect
	} else {
		vp_w = fw
		vp_h = fw / target_aspect
	}

	return sdl.GPUViewport {
		x = (fw - vp_w) * 0.5,
		y = (fh - vp_h) * 0.5,
		w = vp_w,
		h = vp_h,
		min_depth = 0.0,
		max_depth = 1.0,
	}
}

begin_scene :: proc(r: ^GPU_Renderer) {
	batch_begin(&r.batch)
}

present_frame :: proc(r: ^GPU_Renderer) -> bool {
	cmd := sdl.AcquireGPUCommandBuffer(r.device)
	if cmd == nil {
		return false
	}

	has_scene_quads := r.batch.quad_count > 0 && r.batch.call_count > 0

	if r.palette_dirty || has_scene_quads {
		if r.palette_dirty {
			mapped := sdl.MapGPUTransferBuffer(r.device, r.palette_transfer, true)
			if mapped != nil {
				mem.copy(mapped, &r.palette, size_of(assets.Palette))
				sdl.UnmapGPUTransferBuffer(r.device, r.palette_transfer)
			}
		}

		copy_pass := sdl.BeginGPUCopyPass(cmd)
		if copy_pass != nil {
			if r.palette_dirty {
				sdl.UploadToGPUTexture(
					copy_pass,
					sdl.GPUTextureTransferInfo {
						transfer_buffer = r.palette_transfer,
						offset = 0,
						pixels_per_row = 256,
						rows_per_layer = 1,
					},
					sdl.GPUTextureRegion{texture = r.palette_texture, w = 256, h = 1, d = 1},
					true,
				)
				r.palette_dirty = false
			}
			if has_scene_quads {
				batch_upload(r.device, &r.batch, copy_pass)
			}
			sdl.EndGPUCopyPass(copy_pass)
		}
	}

	if has_scene_quads {
		scene_target := sdl.GPUColorTargetInfo {
			texture     = r.screen_texture,
			clear_color = {0, 1, 0, 1},
			load_op     = .CLEAR,
			store_op    = .STORE,
			cycle       = true,
		}
		scene_pass := sdl.BeginGPURenderPass(cmd, &scene_target, 1, nil)
		if scene_pass != nil {
			sdl.BindGPUGraphicsPipeline(scene_pass, r.batch.pipeline)
			sdl.SetGPUViewport(
				scene_pass,
				sdl.GPUViewport{0, 0, SCREEN_WIDTH, SCREEN_HEIGHT, 0, 1},
			)

			scene_uniforms := Scene_Uniforms {
				screen_size = {SCREEN_WIDTH, SCREEN_HEIGHT, 0, 0},
			}
			sdl.PushGPUVertexUniformData(cmd, 0, &scene_uniforms, u32(size_of(scene_uniforms)))

			storage_bufs := [1]^sdl.GPUBuffer{r.batch.storage_buffer}
			sdl.BindGPUVertexStorageBuffers(scene_pass, 0, raw_data(storage_bufs[:]), 1)

			for i in 0 ..< r.batch.call_count {
				call := r.batch.calls[i]
				sdl.SetGPUScissor(scene_pass, call.scissor)

				sampler := r.nearest_repeat_x_sampler if call.repeat_x else r.nearest_sampler
				tex_binding := [1]sdl.GPUTextureSamplerBinding {
					{texture = call.texture, sampler = sampler},
				}
				sdl.BindGPUFragmentSamplers(scene_pass, 0, raw_data(tex_binding[:]), 1)
				sdl.DrawGPUPrimitives(scene_pass, 6, call.instance_count, 0, call.first_instance)
			}

			sdl.EndGPURenderPass(scene_pass)
		}
		batch_begin(&r.batch)
	}

	swapchain_tex: ^sdl.GPUTexture
	swap_w, swap_h: u32
	if !sdl.WaitAndAcquireGPUSwapchainTexture(cmd, r.window, &swapchain_tex, &swap_w, &swap_h) {
		_ = sdl.CancelGPUCommandBuffer(cmd)
		return false
	}

	if swapchain_tex != nil && swap_w > 0 && swap_h > 0 {
		color_target := sdl.GPUColorTargetInfo {
			texture     = swapchain_tex,
			clear_color = {0, 0, 0, 1},
			load_op     = .CLEAR,
			store_op    = .STORE,
		}
		pass := sdl.BeginGPURenderPass(cmd, &color_target, 1, nil)
		if pass != nil {
			sdl.BindGPUGraphicsPipeline(pass, r.present_pipeline)

			vp := compute_present_viewport(swap_w, swap_h, r.aspect_mode, r.integer_scale)
			sdl.SetGPUViewport(pass, vp)

			bindings := [2]sdl.GPUTextureSamplerBinding {
				{texture = r.screen_texture, sampler = r.nearest_sampler},
				{texture = r.palette_texture, sampler = r.nearest_sampler},
			}
			sdl.BindGPUFragmentSamplers(pass, 0, raw_data(bindings[:]), u32(len(bindings)))

			uniforms := Present_Uniforms {
				fade_color = {r.fade.color.r, r.fade.color.g, r.fade.color.b, r.fade.amount},
				video_opts = {r.scanlines, SCREEN_HEIGHT, 0, 0},
			}
			sdl.PushGPUFragmentUniformData(cmd, 0, &uniforms, u32(size_of(uniforms)))

			sdl.DrawGPUPrimitives(pass, 3, 1, 0, 0)
			sdl.EndGPURenderPass(pass)
		}
	}

	return sdl.SubmitGPUCommandBuffer(cmd)
}
