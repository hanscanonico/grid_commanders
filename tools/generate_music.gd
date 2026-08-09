extends SceneTree
## Generates the looping background music as 16-bit mono WAVs.
## Two chiptune marches on a "cheerful war" register — a jaunty parade for the
## menu and a driving quickstep for the battle — square lead over an oom-pah
## or eighth-note bass with a light march kit, like the generated sfx.
##
## Run with:  make music

const RATE := 22050

## Notes are [midi, beats]; midi -1 is a rest. Each bar sums to 4 beats so the
## melody, the bass and the drums end on the same sample and the loop is clean.
const PARADE_MELODY := [
	[72, 0.75],
	[72, 0.25],
	[74, 0.5],
	[76, 0.5],
	[79, 1.0],
	[76, 1.0],
	[77, 0.5],
	[76, 0.5],
	[74, 0.5],
	[72, 0.5],
	[74, 2.0],
	[74, 0.75],
	[74, 0.25],
	[76, 0.5],
	[77, 0.5],
	[81, 1.0],
	[77, 1.0],
	[79, 0.5],
	[77, 0.5],
	[76, 0.5],
	[74, 0.5],
	[72, 1.5],
	[-1, 0.5],
	[76, 0.5],
	[79, 0.5],
	[84, 1.0],
	[83, 0.5],
	[81, 0.5],
	[79, 1.0],
	[81, 0.5],
	[79, 0.5],
	[77, 0.5],
	[76, 0.5],
	[74, 2.0],
	[72, 0.75],
	[72, 0.25],
	[76, 0.5],
	[79, 0.5],
	[84, 1.0],
	[79, 1.0],
	[77, 0.5],
	[74, 0.5],
	[71, 0.5],
	[74, 0.5],
	[72, 1.5],
	[-1, 0.5],
]
const PARADE_ROOTS := [48, 43, 50, 48, 48, 41, 48, 43]

const ADVANCE_MELODY := [
	[67, 0.5],
	[71, 0.5],
	[74, 0.5],
	[71, 0.5],
	[79, 1.0],
	[74, 1.0],
	[76, 0.5],
	[74, 0.5],
	[72, 0.5],
	[71, 0.5],
	[69, 2.0],
	[69, 0.5],
	[72, 0.5],
	[76, 0.5],
	[72, 0.5],
	[81, 1.0],
	[76, 1.0],
	[79, 0.5],
	[78, 0.5],
	[76, 0.5],
	[74, 0.5],
	[71, 2.0],
	[67, 0.5],
	[71, 0.5],
	[74, 0.5],
	[79, 0.5],
	[83, 1.0],
	[79, 1.0],
	[81, 0.5],
	[79, 0.5],
	[78, 0.5],
	[76, 0.5],
	[74, 2.0],
	[72, 0.5],
	[76, 0.5],
	[79, 0.5],
	[76, 0.5],
	[84, 1.0],
	[83, 0.5],
	[81, 0.5],
	[79, 0.5],
	[74, 0.5],
	[71, 0.5],
	[74, 0.5],
	[79, 1.5],
	[-1, 0.5],
]
const ADVANCE_ROOTS := [43, 45, 45, 50, 43, 50, 48, 43]


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/music"))
	_save("parade", _render(112.0, PARADE_MELODY, _oompah(PARADE_ROOTS), false))
	_save("advance", _render(144.0, ADVANCE_MELODY, _drive(ADVANCE_ROOTS), true))
	print("generate_music: wrote 2 music wavs")
	quit()


## Root then fifth on the quarters — the tuba half of a parade band.
func _oompah(roots: Array) -> Array:
	var notes := []
	for root: int in roots:
		notes.append_array([[root, 1.0], [root + 7, 1.0], [root, 1.0], [root + 7, 1.0]])
	return notes


## Straight eighths with an octave pop off the beat — a bass that marches.
func _drive(roots: Array) -> Array:
	var notes := []
	for root: int in roots:
		for i in 8:
			notes.append([root + 12 if i % 4 == 2 else root, 0.5])
	return notes


func _render(bpm: float, melody: Array, bass: Array, driving: bool) -> PackedFloat32Array:
	var spb := 60.0 / bpm
	var bars := int(roundf(_beats(melody) / 4.0))
	var total := int(_beats(melody) * spb * RATE)
	var mixed := PackedFloat32Array()
	mixed.resize(total)
	_add(mixed, _channel(melody, spb, true, 0.16))
	_add(mixed, _channel(bass, spb, false, 0.18))
	_add(mixed, _drums(bars, spb, driving))
	for i in total:
		mixed[i] = clampf(mixed[i], -1.0, 1.0)
	return mixed


func _beats(notes: Array) -> float:
	var beats := 0.0
	for note: Array in notes:
		beats += note[1]
	return beats


## One voice played through in sequence: square for the lead, triangle for the
## bass. Every note decays a little (the jaunty, plucked read) and gets a short
## attack and release ramp so no note edge clicks.
func _channel(notes: Array, spb: float, square: bool, volume: float) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	for note: Array in notes:
		var midi: int = note[0]
		var count := int(float(note[1]) * spb * RATE)
		if midi < 0:
			var rest := samples.size()
			samples.resize(rest + count)
			continue
		var freq := 440.0 * pow(2.0, (midi - 69) / 12.0)
		for i in count:
			var phase := fmod(float(i) / RATE * freq, 1.0)
			var value := (1.0 if phase < 0.5 else -1.0) if square else 4.0 * absf(phase - 0.5) - 1.0
			var attack := minf(1.0, float(i) / (0.005 * RATE))
			var release := minf(1.0, float(count - i) / (0.015 * RATE))
			var decay := 1.0 - 0.6 * float(i) / count
			samples.append(value * volume * attack * release * decay)
	return samples


## A light march kit: thump on the strong beats, snare crack on the backbeats,
## ticking eighths under everything. The driving kit doubles the second thump.
func _drums(bars: int, spb: float, driving: bool) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	samples.resize(int(bars * 4 * spb * RATE))
	var snare := _crack(0.09, 0.3, 6.0)
	var tick := _crack(0.03, 0.09, 9.0)
	var thump := _thump(0.11, 0.5)
	for bar in bars:
		var start := bar * 4.0
		for beat in [0.0, 2.0]:
			_place(samples, thump, (start + beat) * spb)
		if driving:
			_place(samples, thump, (start + 2.5) * spb)
		for beat in [1.0, 3.0]:
			_place(samples, snare, (start + beat) * spb)
		for eighth in 8:
			_place(samples, tick, (start + eighth * 0.5) * spb)
	return samples


## The sfx generator's random-walk noise, cut short and gated hard — a snare or
## a closed hat depending on length. Seeded so the art is reproducible.
func _crack(length: float, volume: float, decay: float) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var count := int(length * RATE)
	var last := 0.0
	for i in count:
		last = last * 0.5 + rng.randf_range(-1.0, 1.0) * 0.5
		samples.append(last * volume * exp(-decay * float(i) / count))
	return samples


## A low sine that drops in pitch as it fades — the kick.
func _thump(length: float, volume: float) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	var count := int(length * RATE)
	for i in count:
		var t := float(i) / count
		samples.append(sin(TAU * float(i) / RATE * (90.0 - 40.0 * t)) * volume * (1.0 - t))
	return samples


func _place(into: PackedFloat32Array, hit: PackedFloat32Array, at_seconds: float) -> void:
	var start := int(at_seconds * RATE)
	for i in hit.size():
		if start + i >= into.size():
			return
		into[start + i] += hit[i]


func _add(into: PackedFloat32Array, channel: PackedFloat32Array) -> void:
	for i in mini(into.size(), channel.size()):
		into[i] += channel[i]


func _save(name: String, samples: PackedFloat32Array) -> void:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(samples[i] * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	var err := wav.save_to_wav("res://assets/music/%s.wav" % name)
	if err != OK:
		push_error("generate_music: failed to save %s (%d)" % [name, err])
