package audio

import "core:math"
import "core:slice"

MIDI_SAMPLE_RATE :: 44100
MIDI_MAX_VOICES :: 24

Midi_Event_Kind :: enum u8 {
	Note_Off,
	Note_On,
	Control_Change,
	Program_Change,
	Pitch_Bend,
	Tempo,
}

Midi_Event :: struct {
	tick:    u32,
	kind:    Midi_Event_Kind,
	channel: u8,
	data1:   u8,
	data2:   u8,
	tempo:   u32,
}

Midi_Song :: struct {
	division:    u16,
	events:      []Midi_Event,
	total_ticks: u32,
}

Env_Stage :: enum u8 {
	Off,
	Attack,
	Decay,
	Sustain,
	Release,
}

OPL_Op :: struct {
	phase:       f64,
	env_level:   f32,
	stage:       Env_Stage,
	mult:        f64,
	base_gain:   f32,
	attack_rate: f32,
	decay_mul:   f32,
	sustain_lvl: f32,
	release_mul: f32,
	sustaining:  bool,
	wave:        u8,
	prev_out:    [2]f32,
}

OPL_Voice :: struct {
	active:        bool,
	released:      bool,
	age:           u32,
	channel:       u8,
	note:          u8,
	play_note:     f64,
	velocity_gain: f32,
	additive:      bool,
	feedback_amt:  f32,
	mod:           OPL_Op,
	car:           OPL_Op,
}

Midi_Channel :: struct {
	program:    u8,
	volume:     f32,
	expression: f32,
	pan:        f32,
	pitch_bend: f64,
}

Midi_Player :: struct {
	song:              Midi_Song,
	loaded:            bool,
	playing:           bool,
	looping:           bool,
	volume:            f32,
	event_idx:         int,
	current_tick:      f64,
	ticks_per_sample:  f64,
	voice_age_counter: u32,
	channels:          [16]Midi_Channel,
	voices:            [MIDI_MAX_VOICES]OPL_Voice,
}

@(private)
OPL_MULT_TABLE := [16]f64 {
	0.5,
	1.0,
	2.0,
	3.0,
	4.0,
	5.0,
	6.0,
	7.0,
	8.0,
	9.0,
	10.0,
	10.0,
	12.0,
	12.0,
	15.0,
	15.0,
}

@(private)
OPL_FEEDBACK_SCALE := [8]f32{0.0, 0.0625, 0.125, 0.25, 0.5, 1.0, 2.0, 4.0}

@(private)
read_be_u16 :: proc(b: []u8, pos: int) -> u16 {
	return (u16(b[pos]) << 8) | u16(b[pos + 1])
}

@(private)
read_be_u32 :: proc(b: []u8, pos: int) -> u32 {
	return (u32(b[pos]) << 24) | (u32(b[pos + 1]) << 16) | (u32(b[pos + 2]) << 8) | u32(b[pos + 3])
}

@(private)
read_vlq :: proc(b: []u8, pos: ^int) -> (val: u32, ok: bool) {
	v: u32 = 0
	for _ in 0 ..< 4 {
		if pos^ >= len(b) do return 0, false
		byte_val := b[pos^]
		pos^ += 1
		v = (v << 7) | u32(byte_val & 0x7F)
		if (byte_val & 0x80) == 0 {
			return v, true
		}
	}
	return v, true
}

destroy_midi_song :: proc(song: ^Midi_Song, allocator := context.allocator) {
	if song == nil do return
	if song.events != nil {
		delete(song.events, allocator)
		song.events = nil
	}
	song.division = 0
	song.total_ticks = 0
}

parse_midi :: proc(data: []u8, allocator := context.allocator) -> (song: Midi_Song, ok: bool) {
	if len(data) < 14 || string(data[:4]) != "MThd" {
		return {}, false
	}

	hdr_len := int(read_be_u32(data, 4))
	if hdr_len < 6 || 8 + hdr_len > len(data) {
		return {}, false
	}
	num_tracks := int(read_be_u16(data, 10))
	division := read_be_u16(data, 12)
	if division == 0 || (division & 0x8000) != 0 {
		division = 120
	}

	events := make([dynamic]Midi_Event, 0, 1024, allocator)
	max_tick: u32 = 0

	pos := 8 + hdr_len
	for _ in 0 ..< num_tracks {
		if pos + 8 > len(data) do break
		if string(data[pos:pos + 4]) != "MTrk" {
			clen := int(read_be_u32(data, pos + 4))
			pos += 8 + clen
			continue
		}
		trk_len := int(read_be_u32(data, pos + 4))
		pos += 8
		trk_end := min(pos + trk_len, len(data))

		tick: u32 = 0
		running_status: u8 = 0

		for pos < trk_end {
			delta, vok := read_vlq(data, &pos)
			if !vok || pos >= trk_end do break
			tick += delta
			if tick > max_tick do max_tick = tick

			status := data[pos]
			if status < 0x80 {
				if running_status == 0 do break
				status = running_status
			} else {
				pos += 1
				if status < 0xF0 {
					running_status = status
				}
			}

			if status == 0xFF {
				if pos >= trk_end do break
				meta_type := data[pos]
				pos += 1
				mlen, mok := read_vlq(data, &pos)
				if !mok || pos + int(mlen) > trk_end do break
				if meta_type == 0x51 && mlen == 3 {
					us_per_q :=
						(u32(data[pos]) << 16) | (u32(data[pos + 1]) << 8) | u32(data[pos + 2])
					append(
						&events,
						Midi_Event{tick = tick, kind = .Tempo, tempo = max(us_per_q, 10000)},
					)
				} else if meta_type == 0x2F {
					pos += int(mlen)
					break
				}
				pos += int(mlen)
			} else if status == 0xF0 || status == 0xF7 {
				slen, sok := read_vlq(data, &pos)
				if !sok do break
				pos = min(pos + int(slen), trk_end)
			} else {
				cmd := status & 0xF0
				ch := status & 0x0F
				switch cmd {
				case 0x80:
					if pos + 2 > trk_end do break
					append(
						&events,
						Midi_Event {
							tick = tick,
							kind = .Note_Off,
							channel = ch,
							data1 = data[pos],
							data2 = data[pos + 1],
						},
					)
					pos += 2
				case 0x90:
					if pos + 2 > trk_end do break
					vel := data[pos + 1]
					kind := Midi_Event_Kind.Note_On if vel > 0 else Midi_Event_Kind.Note_Off
					append(
						&events,
						Midi_Event {
							tick = tick,
							kind = kind,
							channel = ch,
							data1 = data[pos],
							data2 = vel,
						},
					)
					pos += 2
				case 0xA0:
					pos = min(pos + 2, trk_end)
				case 0xB0:
					if pos + 2 > trk_end do break
					append(
						&events,
						Midi_Event {
							tick = tick,
							kind = .Control_Change,
							channel = ch,
							data1 = data[pos],
							data2 = data[pos + 1],
						},
					)
					pos += 2
				case 0xC0:
					if pos + 1 > trk_end do break
					append(
						&events,
						Midi_Event {
							tick = tick,
							kind = .Program_Change,
							channel = ch,
							data1 = data[pos],
						},
					)
					pos += 1
				case 0xD0:
					pos = min(pos + 1, trk_end)
				case 0xE0:
					if pos + 2 > trk_end do break
					append(
						&events,
						Midi_Event {
							tick = tick,
							kind = .Pitch_Bend,
							channel = ch,
							data1 = data[pos],
							data2 = data[pos + 1],
						},
					)
					pos += 2
				}
			}
		}

		pos = trk_end
	}

	if len(events) == 0 {
		delete(events)
		return {}, false
	}
	shrink(&events)

	slice.stable_sort_by(events[:], proc(a, b: Midi_Event) -> bool {
		return a.tick < b.tick
	})

	return Midi_Song{division = division, events = events[:], total_ticks = max_tick}, true
}

@(private)
opl_rate_to_attack_step :: proc(rate4: u8) -> f32 {
	if rate4 == 0 do return 0.0
	if rate4 >= 15 do return 1.0
	time_sec := 5.0 * math.pow_f32(0.52, f32(rate4))
	return clamp(1.0 / max(time_sec * MIDI_SAMPLE_RATE, 1.0), 0.00001, 1.0)
}

@(private)
opl_rate_to_decay_mul :: proc(rate4: u8) -> f32 {
	if rate4 == 0 do return 1.0
	time_sec := 16.0 * math.pow_f32(0.52, f32(rate4))
	return math.exp_f32(-5.5 / max(time_sec * MIDI_SAMPLE_RATE, 1.0))
}

@(private)
opl_tl_to_gain :: proc(tl6: u8) -> f32 {
	db := -0.75 * f32(tl6 & 0x3F)
	return math.pow_f32(10.0, db / 20.0)
}

@(private)
opl_sl_to_level :: proc(sl4: u8) -> f32 {
	if sl4 >= 15 do return 0.0
	db := -3.0 * f32(sl4 & 0x0F)
	return math.pow_f32(10.0, db / 20.0)
}

@(private)
init_opl_op :: proc(op: ^OPL_Op, savek, level, env1, env2, wave: u8) {
	op^ = {}
	op.mult = OPL_MULT_TABLE[savek & 0x0F]
	op.sustaining = (savek & 0x20) != 0
	op.base_gain = opl_tl_to_gain(level & 0x3F)
	op.attack_rate = opl_rate_to_attack_step((env1 >> 4) & 0x0F)
	op.decay_mul = opl_rate_to_decay_mul(env1 & 0x0F)
	op.sustain_lvl = opl_sl_to_level((env2 >> 4) & 0x0F)
	op.release_mul = opl_rate_to_decay_mul(max(env2 & 0x0F, 3))
	op.wave = wave & 0x03
	op.stage = .Attack
	op.env_level = 0.0
}

@(private)
eval_opl_wave :: #force_inline proc(phase_norm: f64, wave: u8) -> f32 {
	p := phase_norm - math.floor(phase_norm)
	switch wave {
	case 0:
		return f32(math.sin(p * math.TAU))
	case 1:
		return f32(math.sin(p * math.TAU)) if p < 0.5 else 0.0
	case 2:
		return abs(f32(math.sin(p * math.TAU)))
	case 3:
		if p < 0.25 || (p >= 0.5 && p < 0.75) {
			return abs(f32(math.sin(p * math.TAU)))
		}
		return 0.0
	}
	return f32(math.sin(p * math.TAU))
}

@(private)
step_opl_env :: #force_inline proc(op: ^OPL_Op) -> f32 {
	switch op.stage {
	case .Off:
		return 0.0
	case .Attack:
		op.env_level += op.attack_rate
		if op.env_level >= 1.0 {
			op.env_level = 1.0
			op.stage = .Decay
		}
	case .Decay:
		op.env_level *= op.decay_mul
		if op.env_level <= op.sustain_lvl {
			op.env_level = op.sustain_lvl
			op.stage = .Sustain if op.sustaining else .Release
		}
	case .Sustain:
		if !op.sustaining {
			op.stage = .Release
		}
	case .Release:
		op.env_level *= op.release_mul
		if op.env_level < 0.0005 {
			op.env_level = 0.0
			op.stage = .Off
		}
	}
	return op.env_level * op.base_gain
}

midi_player_init :: proc(p: ^Midi_Player) {
	p^ = {}
	p.volume = 0.75
	midi_player_reset_channels(p)
}

midi_player_destroy :: proc(p: ^Midi_Player, allocator := context.allocator) {
	if p == nil do return
	destroy_midi_song(&p.song, allocator)
	p.loaded = false
	p.playing = false
}

midi_player_reset_channels :: proc(p: ^Midi_Player) {
	for &ch in p.channels {
		ch = Midi_Channel {
			program    = 0,
			volume     = 1.0,
			expression = 1.0,
			pan        = 0.0,
			pitch_bend = 0.0,
		}
	}
	for &v in p.voices {
		v.active = false
	}
}

@(private)
midi_set_tempo :: proc(p: ^Midi_Player, us_per_quarter: u32) {
	div := f64(max(p.song.division, 1))
	sec_per_quarter := f64(max(us_per_quarter, 10000)) / 1_000_000.0
	ticks_per_sec := div / sec_per_quarter
	p.ticks_per_sample = ticks_per_sec / f64(MIDI_SAMPLE_RATE)
}

midi_player_load_and_play :: proc(
	p: ^Midi_Player,
	data: []u8,
	looping: bool,
	allocator := context.allocator,
) -> bool {
	destroy_midi_song(&p.song, allocator)
	p.loaded = false
	p.playing = false

	song, ok := parse_midi(data, allocator)
	if !ok do return false

	p.song = song
	p.loaded = true
	p.looping = looping
	p.event_idx = 0
	p.current_tick = 0.0
	midi_set_tempo(p, 500_000)
	midi_player_reset_channels(p)
	p.playing = true
	return true
}

midi_player_stop :: proc(p: ^Midi_Player) {
	p.playing = false
	for &v in p.voices {
		v.active = false
	}
}

@(private)
midi_note_on :: proc(p: ^Midi_Player, ch_idx, note, vel: u8) {
	ch := &p.channels[ch_idx]

	timbre_idx: int
	play_note: f64
	if ch_idx == 9 {
		dm := PERCUSSION_TABLE[note & 0x7F]
		timbre_idx = int(dm.timbre)
		play_note = f64(dm.key)
	} else {
		timbre_idx = int(ch.program & 0x7F)
		play_note = f64(note)
	}
	if timbre_idx < 0 || timbre_idx >= len(ADLIB_TIMBRE_BANK) {
		timbre_idx = 0
	}
	t := ADLIB_TIMBRE_BANK[timbre_idx]

	slot := -1
	best_released := -1
	oldest_released_age := max(u32)
	oldest_any := 0
	oldest_any_age := max(u32)

	for i in 0 ..< MIDI_MAX_VOICES {
		v := &p.voices[i]
		if !v.active {
			slot = i
			break
		}
		if v.released && v.age < oldest_released_age {
			oldest_released_age = v.age
			best_released = i
		}
		if v.age < oldest_any_age {
			oldest_any_age = v.age
			oldest_any = i
		}
	}
	if slot < 0 {
		slot = best_released if best_released >= 0 else oldest_any
	}

	p.voice_age_counter += 1
	v := &p.voices[slot]
	v^ = {}
	v.active = true
	v.released = false
	v.age = p.voice_age_counter
	v.channel = ch_idx
	v.note = note
	v.play_note = play_note
	v.velocity_gain = math.pow_f32(f32(vel) / 127.0, 1.4)
	v.additive = (t.feedback & 1) != 0
	v.feedback_amt = OPL_FEEDBACK_SCALE[(t.feedback >> 1) & 7]

	init_opl_op(&v.mod, t.savek[0], t.level[0], t.env1[0], t.env2[0], t.wave[0])
	init_opl_op(&v.car, t.savek[1], t.level[1], t.env1[1], t.env2[1], t.wave[1])
}

@(private)
midi_note_off :: proc(p: ^Midi_Player, ch_idx, note: u8) {
	for &v in p.voices {
		if v.active && !v.released && v.channel == ch_idx && v.note == note {
			v.released = true
			v.mod.stage = .Release
			v.car.stage = .Release
		}
	}
}

@(private)
midi_dispatch_event :: proc(p: ^Midi_Player, ev: Midi_Event) {
	ch := &p.channels[ev.channel & 0x0F]
	switch ev.kind {
	case .Tempo:
		midi_set_tempo(p, ev.tempo)
	case .Program_Change:
		ch.program = ev.data1 & 0x7F
	case .Control_Change:
		switch ev.data1 {
		case 7:
			ch.volume = f32(ev.data2 & 0x7F) / 127.0
		case 10:
			ch.pan = (f32(ev.data2 & 0x7F) - 64.0) / 64.0
		case 11:
			ch.expression = f32(ev.data2 & 0x7F) / 127.0
		case 120, 123:
			for &v in p.voices {
				if v.active && v.channel == (ev.channel & 0x0F) {
					v.released = true
					v.mod.stage = .Release
					v.car.stage = .Release
				}
			}
		}
	case .Pitch_Bend:
		raw14 := int(ev.data1 & 0x7F) | (int(ev.data2 & 0x7F) << 7)
		ch.pitch_bend = (f64(raw14 - 8192) / 8192.0) * 2.0
	case .Note_On:
		midi_note_on(p, ev.channel & 0x0F, ev.data1 & 0x7F, ev.data2 & 0x7F)
	case .Note_Off:
		midi_note_off(p, ev.channel & 0x0F, ev.data1 & 0x7F)
	}
}

midi_player_render :: proc(p: ^Midi_Player, out: []f32, num_frames: int) {
	if !p.loaded || !p.playing || p.volume <= 0.0001 {
		for i in 0 ..< num_frames * 2 {
			out[i] = 0.0
		}
		return
	}

	master_gain := p.volume * 0.14
	inv_sr := 1.0 / f64(MIDI_SAMPLE_RATE)

	for frame in 0 ..< num_frames {
		for p.event_idx < len(p.song.events) &&
		    f64(p.song.events[p.event_idx].tick) <= p.current_tick {
			midi_dispatch_event(p, p.song.events[p.event_idx])
			p.event_idx += 1
		}

		p.current_tick += p.ticks_per_sample

		if p.event_idx >= len(p.song.events) && p.current_tick >= f64(p.song.total_ticks) {
			if p.looping {
				p.event_idx = 0
				p.current_tick = 0.0
				midi_set_tempo(p, 500_000)
				for &v in p.voices {
					if v.active {
						v.released = true
						v.mod.stage = .Release
						v.car.stage = .Release
					}
				}
			} else {
				p.playing = false
				for i in frame ..< num_frames {
					out[i * 2 + 0] = 0.0
					out[i * 2 + 1] = 0.0
				}
				return
			}
		}

		mix_l: f32 = 0.0
		mix_r: f32 = 0.0

		for i in 0 ..< MIDI_MAX_VOICES {
			v := &p.voices[i]
			if !v.active {
				continue
			}

			ch := &p.channels[v.channel]
			bend := 0.0 if v.channel == 9 else ch.pitch_bend
			freq := 440.0 * math.pow(2.0, (v.play_note + bend - 69.0) / 12.0)

			mod_env := step_opl_env(&v.mod)
			car_env := step_opl_env(&v.car)

			if v.car.stage == .Off && (!v.additive || v.mod.stage == .Off) {
				v.active = false
				continue
			}

			fb := 0.5 * (v.mod.prev_out[0] + v.mod.prev_out[1]) * v.feedback_amt
			mod_sample := eval_opl_wave(v.mod.phase + f64(fb) * 0.25, v.mod.wave) * mod_env
			v.mod.prev_out[1] = v.mod.prev_out[0]
			v.mod.prev_out[0] = mod_sample

			sample: f32
			if v.additive {
				car_sample := eval_opl_wave(v.car.phase, v.car.wave) * car_env
				sample = (mod_sample + car_sample) * 0.65
			} else {
				sample = eval_opl_wave(v.car.phase + f64(mod_sample) * 0.85, v.car.wave) * car_env
			}

			v.mod.phase += freq * v.mod.mult * inv_sr
			v.car.phase += freq * v.car.mult * inv_sr
			if v.mod.phase >= 1.0 do v.mod.phase -= math.floor(v.mod.phase)
			if v.car.phase >= 1.0 do v.car.phase -= math.floor(v.car.phase)

			gain := v.velocity_gain * ch.volume * ch.expression
			s := sample * gain
			pan_r := clamp((ch.pan + 1.0) * 0.5, 0.0, 1.0)
			pan_l := 1.0 - pan_r
			mix_l += s * (0.5 + 0.5 * pan_l)
			mix_r += s * (0.5 + 0.5 * pan_r)
		}

		sl := mix_l * master_gain
		sr := mix_r * master_gain
		out[frame * 2 + 0] = sl / (1.0 + abs(sl))
		out[frame * 2 + 1] = sr / (1.0 + abs(sr))
	}
}
