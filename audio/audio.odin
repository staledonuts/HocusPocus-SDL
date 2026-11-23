package audio

import "../assets"
import "base:runtime"
import "core:c"
import sdl "vendor:sdl3"

NUM_GAME_SFX :: 16
MAX_SFX_VOICES :: 8
SFX_HEADROOM_GAIN :: f32(0.45)
SFX_DEDUP_NS :: u64(35_000_000)
LIMITER_CEILING :: f32(0.92)

Sound_Entry :: struct {
	voc_chunk: assets.Chunk_ID,
	priority:  int,
}

SOUND_ENTRIES := [NUM_GAME_SFX]Sound_Entry {
	{.SOUND08_VOC, 14},
	{.SOUND10_VOC, 13},
	{.SOUND11_VOC, 12},
	{.SOUND12_VOC, 12},
	{.SOUND15_VOC, 18},
	{.SOUND13_VOC, 17},
	{.SOUND16_VOC, 14},
	{.SOUND17_VOC, 16},
	{.SOUND18_VOC, 15},
	{.SOUND19_VOC, 15},
	{.SOUND20_VOC, 16},
	{.SOUND02_VOC, 19},
	{.SOUND07_VOC, 15},
	{.SOUND09_VOC, 14},
	{.SOUND21_VOC, 13},
	{.SOUND22_VOC, 11},
}

Clean_Sfx :: struct {
	samples:     []f32,
	sample_rate: int,
	channels:    int,
}

Sfx_Voice :: struct {
	stream:        ^sdl.AudioStream,
	sfx_id:        int,
	priority:      int,
	start_time_ns: u64,
	end_time_ns:   u64,
}

Audio_System :: struct {
	device:         sdl.AudioDeviceID,
	device_spec:    sdl.AudioSpec,
	sfx_sounds:     [NUM_GAME_SFX]Clean_Sfx,
	sfx_loaded:     [NUM_GAME_SFX]bool,
	sfx_voices:     [MAX_SFX_VOICES]Sfx_Voice,
	oneshot_stream: ^sdl.AudioStream,
	music_stream:   ^sdl.AudioStream,
	midi:           Midi_Player,
	midi_buf:       [2048]f32,
	limiter_gain:   f32,
	sfx_enabled:    bool,
	music_enabled:  bool,
	sfx_volume:     f32,
	music_volume:   f32,
}

voc_to_clean_f32 :: proc(voc: ^assets.Voc_Sound, allocator := context.allocator) -> Clean_Sfx {
	n := len(voc.samples)
	sr := max(voc.sample_rate, 1)
	ch := max(voc.channels, 1)
	if n == 0 {
		return Clean_Sfx{sample_rate = sr, channels = ch}
	}

	out := make([]f32, n, allocator)
	sum: f64 = 0.0
	for i in 0 ..< n {
		s := (f32(voc.samples[i]) - 128.0) / 128.0
		out[i] = s
		sum += f64(s)
	}

	dc := f32(sum / f64(n))
	for i in 0 ..< n {
		out[i] = clamp(out[i] - dc, -1.0, 1.0)
	}

	frames := n / ch
	fade_in := min(max(sr / 500, 1), frames / 4)
	fade_out := min(max((sr * 3) / 1000, 1), frames / 4)

	if fade_in > 1 {
		denom := f32(fade_in - 1)
		for f in 0 ..< fade_in {
			g := f32(f) / denom
			for c_idx in 0 ..< ch {
				out[f * ch + c_idx] *= g
			}
		}
	}
	if fade_out > 1 {
		denom := f32(fade_out - 1)
		start_f := frames - fade_out
		for f in 0 ..< fade_out {
			g := f32(fade_out - 1 - f) / denom
			for c_idx in 0 ..< ch {
				out[(start_f + f) * ch + c_idx] *= g
			}
		}
	}

	return Clean_Sfx{samples = out, sample_rate = sr, channels = ch}
}

destroy_clean_sfx :: proc(s: ^Clean_Sfx, allocator := context.allocator) {
	if s == nil do return
	if s.samples != nil {
		delete(s.samples, allocator)
		s.samples = nil
	}
	s.sample_rate = 0
	s.channels = 0
}

apply_master_limiter :: proc "contextless" (
	samples: []f32,
	channels, sample_rate: int,
	gain_state: ^f32,
) {
	if len(samples) == 0 || channels <= 0 || gain_state == nil {
		return
	}
	sr := max(sample_rate, 8000)
	release_alpha := clamp(1.0 / (0.08 * f32(sr)), 0.00001, 0.05)

	g := gain_state^
	if g <= 0.0 || g > 1.0 {
		g = 1.0
	}

	num_frames := len(samples) / channels
	for f in 0 ..< num_frames {
		base := f * channels
		peak: f32 = 0.0
		for c_idx in 0 ..< channels {
			a := abs(samples[base + c_idx])
			if a > peak do peak = a
		}

		target_g: f32 = 1.0
		if peak > LIMITER_CEILING {
			target_g = LIMITER_CEILING / peak
		}

		if target_g < g {
			g = target_g
		} else {
			g += (target_g - g) * release_alpha
		}

		for c_idx in 0 ..< channels {
			x := samples[base + c_idx] * g
			ax := abs(x)
			if ax > 0.95 {
				excess := ax - 0.95
				shaped := 0.95 + (0.04 * excess) / (0.04 + excess)
				x = shaped if x >= 0 else -shaped
			}
			samples[base + c_idx] = x
		}
	}

	gain_state^ = g
}

@(private)
audio_postmix_callback :: proc "c" (
	userdata: rawptr,
	spec: ^sdl.AudioSpec,
	buffer: [^]f32,
	buflen: c.int,
) {
	if userdata == nil || spec == nil || buffer == nil || buflen <= 0 {
		return
	}
	a := (^Audio_System)(userdata)
	num_floats := int(buflen) / size_of(f32)
	if num_floats <= 0 {
		return
	}
	apply_master_limiter(buffer[:num_floats], int(spec.channels), int(spec.freq), &a.limiter_gain)
}

@(private)
music_stream_callback :: proc "c" (
	userdata: rawptr,
	stream: ^sdl.AudioStream,
	additional_amount, total_amount: c.int,
) {
	if userdata == nil || additional_amount <= 0 {
		return
	}
	context = runtime.default_context()
	a := (^Audio_System)(userdata)

	bytes_needed := int(additional_amount)
	frame_bytes := size_of(f32) * 2
	max_frames := len(a.midi_buf) / 2

	for bytes_needed > 0 {
		frames := min((bytes_needed + frame_bytes - 1) / frame_bytes, max_frames)
		if frames <= 0 do break

		if a.music_enabled && a.midi.playing {
			midi_player_render(&a.midi, a.midi_buf[:frames * 2], frames)
		} else {
			for i in 0 ..< frames * 2 {
				a.midi_buf[i] = 0.0
			}
		}

		put_bytes := frames * frame_bytes
		_ = sdl.PutAudioStreamData(stream, raw_data(a.midi_buf[:]), c.int(put_bytes))
		bytes_needed -= put_bytes
	}
}

init_audio :: proc(a: ^Audio_System, dat: ^assets.Dat_File) -> bool {
	if a == nil || dat == nil {
		return false
	}

	a^ = {}
	a.sfx_enabled = true
	a.music_enabled = true
	a.sfx_volume = 0.85
	a.music_volume = 0.75
	a.limiter_gain = 1.0
	midi_player_init(&a.midi)
	a.midi.volume = a.music_volume

	desired := sdl.AudioSpec {
		format   = .F32,
		channels = 2,
		freq     = MIDI_SAMPLE_RATE,
	}
	a.device = sdl.OpenAudioDevice(sdl.AUDIO_DEVICE_DEFAULT_PLAYBACK, &desired)
	if a.device == 0 {
		return false
	}
	a.device_spec = desired

	_ = sdl.SetAudioPostmixCallback(a.device, audio_postmix_callback, a)

	for i in 0 ..< NUM_GAME_SFX {
		if chunk, ok := assets.get_chunk(dat, SOUND_ENTRIES[i].voc_chunk); ok {
			if voc, dok := assets.decode_voc(chunk); dok {
				a.sfx_sounds[i] = voc_to_clean_f32(&voc)
				a.sfx_loaded[i] = len(a.sfx_sounds[i].samples) > 0
				assets.destroy_voc(&voc)
			}
		}
	}

	default_sfx_spec := sdl.AudioSpec {
		format   = .F32,
		channels = 1,
		freq     = 11111,
	}
	eff_sfx_gain := a.sfx_volume * SFX_HEADROOM_GAIN
	for i in 0 ..< MAX_SFX_VOICES {
		a.sfx_voices[i].sfx_id = -1
		st := sdl.CreateAudioStream(&default_sfx_spec, &a.device_spec)
		if st != nil {
			_ = sdl.SetAudioStreamGain(st, eff_sfx_gain)
			_ = sdl.BindAudioStream(a.device, st)
			a.sfx_voices[i].stream = st
		}
	}
	a.oneshot_stream = sdl.CreateAudioStream(&default_sfx_spec, &a.device_spec)
	if a.oneshot_stream != nil {
		_ = sdl.SetAudioStreamGain(a.oneshot_stream, eff_sfx_gain)
		_ = sdl.BindAudioStream(a.device, a.oneshot_stream)
	}

	a.music_stream = sdl.CreateAudioStream(&a.device_spec, &a.device_spec)
	if a.music_stream != nil {
		_ = sdl.SetAudioStreamGetCallback(a.music_stream, music_stream_callback, a)
		_ = sdl.BindAudioStream(a.device, a.music_stream)
	}

	_ = sdl.ResumeAudioDevice(a.device)
	return true
}

destroy_audio :: proc(a: ^Audio_System) {
	if a == nil {
		return
	}

	if a.device != 0 {
		_ = sdl.SetAudioPostmixCallback(a.device, nil, nil)
	}

	if a.music_stream != nil {
		_ = sdl.LockAudioStream(a.music_stream)
		midi_player_destroy(&a.midi)
		_ = sdl.UnlockAudioStream(a.music_stream)
		sdl.DestroyAudioStream(a.music_stream)
		a.music_stream = nil
	} else {
		midi_player_destroy(&a.midi)
	}

	if a.oneshot_stream != nil {
		sdl.DestroyAudioStream(a.oneshot_stream)
		a.oneshot_stream = nil
	}
	for &v in a.sfx_voices {
		if v.stream != nil {
			sdl.DestroyAudioStream(v.stream)
			v.stream = nil
		}
	}
	if a.device != 0 {
		sdl.CloseAudioDevice(a.device)
		a.device = 0
	}

	for i in 0 ..< NUM_GAME_SFX {
		if a.sfx_loaded[i] {
			destroy_clean_sfx(&a.sfx_sounds[i])
			a.sfx_loaded[i] = false
		}
	}
}

play_sfx :: proc(a: ^Audio_System, sfx_id: int) {
	if a == nil || a.device == 0 || !a.sfx_enabled {
		return
	}
	if sfx_id < 0 || sfx_id >= NUM_GAME_SFX || !a.sfx_loaded[sfx_id] {
		return
	}

	sfx := &a.sfx_sounds[sfx_id]
	prio := SOUND_ENTRIES[sfx_id].priority
	now_ns := sdl.GetTicksNS()

	slot := -1
	lowest_prio := 999
	oldest_start := max(u64)
	lowest_slot := -1

	same_count := 0
	same_oldest_slot := -1
	same_oldest_start := max(u64)

	for i in 0 ..< MAX_SFX_VOICES {
		v := &a.sfx_voices[i]
		st := v.stream
		if st == nil do continue

		stream_empty := sdl.GetAudioStreamAvailable(st) <= 0 && sdl.GetAudioStreamQueued(st) <= 0
		timed_out := v.end_time_ns > 0 && now_ns >= v.end_time_ns + 50_000_000
		if stream_empty || timed_out {
			v.sfx_id = -1
			v.priority = 0
			v.end_time_ns = 0
			if slot < 0 {
				slot = i
			}
			continue
		}

		if v.sfx_id == sfx_id {
			if now_ns >= v.start_time_ns && (now_ns - v.start_time_ns) < SFX_DEDUP_NS {
				return
			}
			same_count += 1
			if v.start_time_ns < same_oldest_start {
				same_oldest_start = v.start_time_ns
				same_oldest_slot = i
			}
		}

		if v.priority < lowest_prio ||
		   (v.priority == lowest_prio && v.start_time_ns < oldest_start) {
			lowest_prio = v.priority
			oldest_start = v.start_time_ns
			lowest_slot = i
		}
	}

	if same_count >= 2 && same_oldest_slot >= 0 {
		slot = same_oldest_slot
	}

	if slot < 0 {
		if lowest_slot >= 0 && prio >= lowest_prio {
			slot = lowest_slot
		} else {
			return
		}
	}

	sr := max(sfx.sample_rate, 1)
	ch := max(sfx.channels, 1)
	duration_ns := (u64(len(sfx.samples)) * 1_000_000_000) / u64(sr * ch)

	v := &a.sfx_voices[slot]
	st := v.stream
	v.sfx_id = sfx_id
	v.priority = prio
	v.start_time_ns = now_ns
	v.end_time_ns = now_ns + duration_ns

	_ = sdl.ClearAudioStream(st)
	src_spec := sdl.AudioSpec {
		format   = .F32,
		channels = c.int(ch),
		freq     = c.int(sr),
	}
	_ = sdl.SetAudioStreamFormat(st, &src_spec, nil)
	_ = sdl.SetAudioStreamGain(st, a.sfx_volume * SFX_HEADROOM_GAIN)
	_ = sdl.PutAudioStreamData(st, raw_data(sfx.samples), c.int(len(sfx.samples) * size_of(f32)))
	_ = sdl.FlushAudioStream(st)
}

play_voc_chunk :: proc(a: ^Audio_System, dat: ^assets.Dat_File, chunk_id: assets.Chunk_ID) {
	if a == nil || a.device == 0 || !a.sfx_enabled || a.oneshot_stream == nil {
		return
	}
	chunk, ok := assets.get_chunk(dat, chunk_id)
	if !ok do return
	voc, dok := assets.decode_voc(chunk, context.temp_allocator)
	if !dok do return
	clean := voc_to_clean_f32(&voc, context.temp_allocator)
	if len(clean.samples) == 0 do return

	_ = sdl.ClearAudioStream(a.oneshot_stream)
	src_spec := sdl.AudioSpec {
		format   = .F32,
		channels = c.int(max(clean.channels, 1)),
		freq     = c.int(max(clean.sample_rate, 1)),
	}
	_ = sdl.SetAudioStreamFormat(a.oneshot_stream, &src_spec, nil)
	_ = sdl.SetAudioStreamGain(a.oneshot_stream, a.sfx_volume * SFX_HEADROOM_GAIN)
	_ = sdl.PutAudioStreamData(
		a.oneshot_stream,
		raw_data(clean.samples),
		c.int(len(clean.samples) * size_of(f32)),
	)
	_ = sdl.FlushAudioStream(a.oneshot_stream)
}

play_music_chunk :: proc(
	a: ^Audio_System,
	dat: ^assets.Dat_File,
	chunk_id: assets.Chunk_ID,
	looping := true,
) -> bool {
	if a == nil || dat == nil {
		return false
	}
	chunk, ok := assets.get_chunk(dat, chunk_id)
	if !ok do return false
	return play_music_bytes(a, chunk, looping)
}

play_level_music :: proc(
	a: ^Audio_System,
	dat: ^assets.Dat_File,
	music_offset: int,
	looping := true,
) -> bool {
	if a == nil || dat == nil {
		return false
	}
	chunk, ok := assets.get_chunk_offset(dat, .MUSIC01_MID, music_offset)
	if !ok do return false
	return play_music_bytes(a, chunk, looping)
}

@(private)
play_music_bytes :: proc(a: ^Audio_System, data: []u8, looping: bool) -> bool {
	if a.music_stream != nil {
		_ = sdl.LockAudioStream(a.music_stream)
	}
	ok := midi_player_load_and_play(&a.midi, data, looping)
	if a.music_stream != nil {
		_ = sdl.UnlockAudioStream(a.music_stream)
		_ = sdl.ClearAudioStream(a.music_stream)
	}
	return ok
}

set_sfx_enabled :: proc(a: ^Audio_System, enabled: bool) {
	if a == nil do return
	a.sfx_enabled = enabled
}

set_music_enabled :: proc(a: ^Audio_System, enabled: bool) {
	if a == nil do return
	if a.music_stream != nil {
		_ = sdl.LockAudioStream(a.music_stream)
	}
	a.music_enabled = enabled
	if a.music_stream != nil {
		_ = sdl.UnlockAudioStream(a.music_stream)
	}
}

set_sfx_volume :: proc(a: ^Audio_System, vol: f32) {
	if a == nil do return
	a.sfx_volume = clamp(vol, 0.0, 1.0)
	eff_gain := a.sfx_volume * SFX_HEADROOM_GAIN
	for v in a.sfx_voices {
		if v.stream != nil {
			_ = sdl.SetAudioStreamGain(v.stream, eff_gain)
		}
	}
	if a.oneshot_stream != nil {
		_ = sdl.SetAudioStreamGain(a.oneshot_stream, eff_gain)
	}
}

set_music_volume :: proc(a: ^Audio_System, vol: f32) {
	if a == nil do return
	a.music_volume = clamp(vol, 0.0, 1.0)
	if a.music_stream != nil {
		_ = sdl.LockAudioStream(a.music_stream)
	}
	a.midi.volume = a.music_volume
	if a.music_stream != nil {
		_ = sdl.UnlockAudioStream(a.music_stream)
	}
}
