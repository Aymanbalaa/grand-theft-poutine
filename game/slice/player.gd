class_name SlicePlayer
extends CharacterBody3D
# Third-person courier controller.
#   Move  WASD / left stick (analog: light tilt walks)   Alt  walk
#   Shift / RT   sprint (stamina)     Space / A   jump (coyote + buffer)
#   C, Ctrl, RMB / B   dive (tackles thieves)
#   LMB / X   shove        E / Y   interact
# Momentum-based: quick acceleration, a short skid on reversals, reduced air
# control. The camera is an orbiting SpringArm with speed-driven FOV and
# length, smoothed vertical follow, landing dip and trauma shake.

const WALK := 1.8
const JOG := 4.3
const SPRINT := 7.0
const ACCEL := 28.0
const DECEL := 22.0
const AIR_CONTROL := 0.3
const GRAVITY := 20.0
const FALL_GRAVITY := 30.0          # snappier fall than rise
const JUMP_V := 6.0                 # apex ~0.9 m at GRAVITY
const COYOTE := 0.13
const JUMP_BUFFER := 0.16
const DIVE_SPEED := 9.0
const DIVE_TIME := 0.62
const DIVE_CD := 0.35
const STAMINA_DRAIN := 0.2          # per second sprinting (5 s full bar)
const STAMINA_REGEN := 0.42
const STAMINA_DELAY := 0.7
const SHOVE_TIME := 0.34            # movement slowed while the shove plays
const FOV_BASE := 64.0
const STRIDE_WALK := 0.72
const STRIDE_RUN := 1.25
# compatibility with older callers
const RUN := SPRINT

signal punched(pos: Vector3, facing: Vector3)
signal rolled(pos: Vector3)
signal jumped(pos: Vector3)
signal landed(pos: Vector3, impact: float)

# Set by the game: returns true when E was used for an interaction (pickup,
# delivery), so the wave emote doesn't fire.
var interact_hook: Callable

var person: SlicePerson
var pivot: Node3D
var arm: SpringArm3D
var camera: Camera3D
var cam_yaw := PI
var cam_pitch := -0.2
var active := true
var mouse_sens := 0.0026
var stamina := 1.0
var sprinting := false
var trauma := 0.0

var _pack: Node3D
var _pack_glow: StandardMaterial3D
var _chest_bone := -1
var _skel: Skeleton3D
var _dive_dir := Vector3.ZERO
var _dive_t := 0.0
var _dive_cd := 0.0
var _shove_t := 0.0
var _lock_t := 0.0              # handoff / knocked: no control
var _knock_t := 0.0
var _coyote := 0.0
var _jump_buf := 0.0
var _air_t := 0.0
var _jumping := false
var _fall_v := 0.0
var _stam_wait := 0.0
var _winded := false            # emptied the bar: no sprint until 35 %
var _facing_yaw := 0.0
var _lean := 0.0
var _dip := 0.0                 # camera landing dip (m)
var _cam_y := 0.0
var _fov := FOV_BASE
var _arm_len := 3.5
var _steps: AudioStreamPlayer3D
var _step_acc := 0.0
var _splash: GPUParticles3D
var _noise := FastNoiseLite.new()
var _noise_t := 0.0
var _punch_alt := false

func _ready() -> void:
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.875
	add_child(cs)
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.3
	floor_constant_speed = true
	person = SlicePerson.new()
	add_child(person)
	person.setup("casual_man", 1.78)
	# courier jacket: Montréal-red with dark trousers, readable at night
	person.tint("LightBrown", Color(0.78, 0.16, 0.1))
	person.tint("LightBlue", Color(0.08, 0.09, 0.11))
	_build_pack()
	pivot = Node3D.new()
	pivot.position.y = 1.55
	pivot.top_level = true
	add_child(pivot)
	arm = SpringArm3D.new()
	arm.spring_length = _arm_len
	arm.margin = 0.15
	arm.position = Vector3(0.4, 0, 0)  # over-the-shoulder offset
	var sph := SphereShape3D.new()
	sph.radius = 0.2
	arm.shape = sph
	arm.add_excluded_object(get_rid())
	pivot.add_child(arm)
	# soft fill + rim that only touch the player (layer 2) so they read against bright windows
	for vi in person.find_children("*", "VisualInstance3D", true, false):
		(vi as VisualInstance3D).layers = 1 | 2
	var fill := OmniLight3D.new()
	fill.light_cull_mask = 2
	fill.light_color = Color(0.75, 0.8, 1.0)
	fill.light_energy = 0.55
	fill.omni_range = 7.0
	fill.position = Vector3(0, 0.6, 2.5)
	fill.light_specular = 0.2
	pivot.add_child(fill)
	var rim := OmniLight3D.new()
	rim.light_cull_mask = 2
	rim.light_color = Color(1.0, 0.8, 0.6)
	rim.light_energy = 0.9
	rim.omni_range = 4.0
	rim.position = Vector3(0, 0.4, -2.2)
	rim.light_specular = 0.6
	pivot.add_child(rim)
	_steps = AudioStreamPlayer3D.new()
	_steps.stream = load("res://assets/slice/audio/step_wet.wav")
	_steps.volume_db = -6.0
	add_child(_steps)
	camera = Camera3D.new()
	camera.fov = FOV_BASE
	camera.near = 0.05
	camera.far = 600.0
	arm.add_child(camera)
	_splash = _make_splash()
	add_child(_splash)
	_noise.frequency = 1.0
	_noise.seed = 42
	_cam_y = global_position.y
	_facing_yaw = person.rotation.y

# ------------------------------------------------------------------ visuals

func _build_pack() -> void:
	# Insulated delivery backpack: boxy, dark teal with a reflective band and a
	# status strip that glows amber while an order is inside.
	_skel = null
	for n in person.model.find_children("*", "Skeleton3D", true, false):
		_skel = n
	if _skel != null:
		_chest_bone = _skel.find_bone("Chest")
	_pack = Node3D.new()
	_pack.top_level = true
	add_child(_pack)
	var body := StandardMaterial3D.new()
	body.albedo_color = Color(0.05, 0.2, 0.22)
	body.roughness = 0.55
	var band := StandardMaterial3D.new()
	band.albedo_color = Color(0.85, 0.85, 0.8)
	band.metallic = 0.6
	band.roughness = 0.25
	_pack_glow = StandardMaterial3D.new()
	_pack_glow.albedo_color = Color(0.2, 0.2, 0.2)
	_pack_glow.emission_enabled = true
	_pack_glow.emission = Color(1.0, 0.62, 0.2)
	_pack_glow.emission_energy_multiplier = 0.0
	for spec in [[Vector3(0.44, 0.46, 0.27), Vector3.ZERO, body], [Vector3(0.452, 0.05, 0.282), Vector3(0, 0.08, 0), band],
			[Vector3(0.3, 0.035, 0.012), Vector3(0, -0.12, -0.14), _pack_glow], [Vector3(0.46, 0.06, 0.29), Vector3(0, 0.235, 0), body]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = spec[0]
		bm.material = spec[2]
		mi.mesh = bm
		mi.position = spec[1]
		mi.layers = 1 | 2
		_pack.add_child(mi)

func _update_pack() -> void:
	var yaw_b := Basis(Vector3.UP, person.rotation.y)
	var anchor := global_position + Vector3.UP * 1.18
	if _skel != null and _chest_bone >= 0:
		anchor = (_skel.global_transform * _skel.get_bone_global_pose(_chest_bone)).origin
	# lean forward with speed, roll with the body lean
	var tilt := Basis(Vector3.RIGHT, clampf(horizontal_speed() / SPRINT, 0.0, 1.0) * 0.22) * Basis(Vector3.FORWARD, _lean)
	var b := yaw_b * tilt
	_pack.global_transform = Transform3D(b, anchor + yaw_b * Vector3(0, -0.02, -0.27))

func set_carrying(on: bool) -> void:
	_pack_glow.emission_energy_multiplier = 3.0 if on else 0.0

func _make_splash() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 0.45
	p.local_coords = false
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.15
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 50.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.9
	pm.gravity = Vector3(0, -9.0, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.03, 0.05)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.8, 0.85, 0.95, 0.35)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = Vector3(0, 0.05, 0)
	return p

# ------------------------------------------------------------------ input

func _unhandled_input(e: InputEvent) -> void:
	if not active:
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam_yaw -= e.relative.x * mouse_sens
		cam_pitch = clampf(cam_pitch - e.relative.y * mouse_sens * 0.8, -1.1, 0.45)
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_LEFT:
			shove()
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			dive()
	elif e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_SPACE:
				_jump_buf = JUMP_BUFFER
			KEY_C, KEY_CTRL:
				dive()
			KEY_E:
				interact()
	elif e is InputEventJoypadButton and e.pressed:
		match e.button_index:
			JOY_BUTTON_A:
				_jump_buf = JUMP_BUFFER
			JOY_BUTTON_B:
				dive()
			JOY_BUTTON_X:
				shove()
			JOY_BUTTON_Y:
				interact()

func interact() -> void:
	if interact_hook.is_valid() and interact_hook.call():
		return
	if _lock_t <= 0.0 and _dive_t <= 0.0 and is_on_floor() and horizontal_speed() < 0.5:
		person.play("wave", 0.15)
		_lock_t = 0.9

func shove() -> void:
	if _shove_t > 0.0 or _dive_t > 0.0 or _lock_t > 0.0:
		return
	_shove_t = SHOVE_TIME
	_punch_alt = not _punch_alt
	person.play("punch", 0.06, 1.6)
	_emit_punch_later()

func dive() -> void:
	if _dive_t > 0.0 or _dive_cd > 0.0 or _lock_t > 0.0 or not is_on_floor():
		return
	var d := _move_dir()
	if d.length() < 0.2:
		d = facing()
	_dive_dir = d.normalized()
	_facing_yaw = atan2(_dive_dir.x, _dive_dir.z)
	person.rotation.y = _facing_yaw
	_dive_t = DIVE_TIME
	_shove_t = 0.0
	person.play("roll", 0.05, 1.45)
	trauma = maxf(trauma, 0.18)
	rolled.emit(global_position)

# The game hands over / receives an order: brief rooted interact animation.
func handoff() -> void:
	_lock_t = 0.45
	_dive_t = 0.0
	person.play("interact", 0.08, 2.2)

# Knocked down by a car or a big collision.
func knock(from_dir: Vector3, strength := 1.0) -> void:
	var d := from_dir
	d.y = 0
	if d.length() < 0.01:
		d = -facing()
	velocity = d.normalized() * 6.0 * strength + Vector3.UP * 3.0 * strength
	_lock_t = 0.9 * strength
	_knock_t = _lock_t
	_dive_t = 0.0
	person.play("hit", 0.04, 0.8)
	trauma = maxf(trauma, 0.75 * strength)

func add_trauma(t: float) -> void:
	trauma = clampf(trauma + t, 0.0, 1.0)

func facing() -> Vector3:
	return Vector3(sin(person.rotation.y), 0, cos(person.rotation.y))

func _emit_punch_later() -> void:
	await get_tree().create_timer(0.16).timeout   # contact frame of the shove
	punched.emit(global_position, facing())

func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()

func rolling() -> bool:
	return _dive_t > 0.0

func knocked() -> bool:
	return _knock_t > 0.0

# ------------------------------------------------------------------ movement

func _stick() -> Vector2:
	var v := Vector2.ZERO
	if not active:
		return v
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): v.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): v.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): v.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): v.y += 1
	v += Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var joy := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if joy.length() > 0.18:
		v += joy
	return v.limit_length(1.0)

func _move_dir() -> Vector3:
	var s := _stick()
	return Basis(Vector3.UP, cam_yaw) * Vector3(s.x, 0, s.y)

func _wants_sprint() -> bool:
	return active and (Input.is_key_pressed(KEY_SHIFT) or Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.4)

func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()
	_dive_cd -= delta
	_lock_t -= delta
	_knock_t -= delta
	_shove_t -= delta
	_jump_buf -= delta
	_coyote = COYOTE if on_floor else _coyote - delta
	var stick := _stick()
	var dir := _move_dir()
	var mag := stick.length()
	var walk_key := Input.is_key_pressed(KEY_ALT)
	# --- stamina
	sprinting = _wants_sprint() and mag > 0.3 and not _winded and _dive_t <= 0.0 and horizontal_speed() > 2.0
	if sprinting:
		stamina = maxf(0.0, stamina - STAMINA_DRAIN * delta)
		_stam_wait = STAMINA_DELAY
		if stamina <= 0.0:
			_winded = true
	else:
		_stam_wait -= delta
		if _stam_wait <= 0.0:
			stamina = minf(1.0, stamina + STAMINA_REGEN * delta)
	if _winded and stamina > 0.35:
		_winded = false
	# --- target horizontal velocity
	var speed := JOG
	if walk_key or (mag < 0.55 and mag > 0.0 and not _keyboard_moving()):
		speed = WALK
	if sprinting or (_wants_sprint() and mag > 0.3 and not _winded):
		speed = SPRINT
	var hv := Vector3(velocity.x, 0, velocity.z)
	var target := dir.normalized() * speed * minf(1.0, mag * 1.4) if mag > 0.05 else Vector3.ZERO
	if _lock_t > 0.0:
		target = Vector3.ZERO
	if _dive_t > 0.0:
		_dive_t -= delta
		var k := clampf(_dive_t / DIVE_TIME, 0.0, 1.0)
		var steer := dir * 1.6 if mag > 0.1 else Vector3.ZERO
		hv = _dive_dir * DIVE_SPEED * (0.35 + 0.65 * k) + steer
		if _dive_t <= 0.0:
			_dive_cd = DIVE_CD
	elif _knock_t > 0.0:
		hv = hv.move_toward(Vector3.ZERO, 9.0 * delta)
	else:
		if _shove_t > 0.0:
			target *= 0.35
		var rate := ACCEL if target.length() > 0.1 else DECEL
		if hv.length() > 1.0 and target.length() > 0.1:
			var rev := -hv.normalized().dot(target.normalized())
			rate *= 1.0 + 1.2 * maxf(0.0, rev)     # reversal: plant and push off
		if not on_floor:
			rate *= AIR_CONTROL
		hv = hv.move_toward(target, rate * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	# --- jump
	if _jump_buf > 0.0 and _coyote > 0.0 and _lock_t <= 0.0 and _dive_t <= 0.0:
		velocity.y = JUMP_V
		_jump_buf = 0.0
		_coyote = 0.0
		_jumping = true
		on_floor = false
		person.pose("run", 0.3, 0.08)
		jumped.emit(global_position)
	if not on_floor:
		var g := GRAVITY if velocity.y > 0.0 and _jumping else FALL_GRAVITY
		velocity.y -= g * delta
		_air_t += delta
		_fall_v = minf(_fall_v, velocity.y)
	move_and_slide()
	var now_floor := is_on_floor()
	if now_floor and _air_t > 0.0:
		var impact := clampf(-_fall_v / 9.0, 0.0, 1.0)
		if _air_t > 0.18:
			_dip = 0.08 + 0.18 * impact
			_steps.pitch_scale = 0.8
			_steps.volume_db = -2.0
			_steps.play()
			landed.emit(global_position, impact)
		_air_t = 0.0
		_fall_v = 0.0
		_jumping = false
	_animate(delta, dir, mag)

func _keyboard_moving() -> bool:
	return Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_D) \
		or Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_RIGHT)

func _animate(delta: float, dir: Vector3, mag: float) -> void:
	var flat := Vector2(velocity.x, velocity.z)
	var sp := flat.length()
	var grounded := is_on_floor()
	# facing: follow velocity (or input while accelerating from rest)
	if _dive_t <= 0.0 and _knock_t <= 0.0 and _lock_t <= 0.0:
		var want := _facing_yaw
		if sp > 0.4:
			want = atan2(flat.x, flat.y)
		elif mag > 0.2:
			want = atan2(dir.x, dir.z)
		var turn_rate := lerpf(16.0, 9.0, clampf(sp / SPRINT, 0.0, 1.0))
		var prev := _facing_yaw
		_facing_yaw = lerp_angle(_facing_yaw, want, clampf(delta * turn_rate, 0, 1))
		var yaw_rate := wrapf(_facing_yaw - prev, -PI, PI) / maxf(delta, 1e-4)
		_lean = lerpf(_lean, clampf(-yaw_rate * sp * 0.012, -0.22, 0.22), clampf(delta * 8.0, 0, 1))
	else:
		_lean = lerpf(_lean, 0.0, clampf(delta * 8.0, 0, 1))
	person.rotation = Vector3(0, _facing_yaw, _lean)
	# footsteps + splashes
	if grounded and sp > 0.6:
		_step_acc += sp * delta
		var stride := STRIDE_WALK if sp < 3.0 else STRIDE_RUN
		if _step_acc > stride:
			_step_acc = 0.0
			_steps.pitch_scale = randf_range(0.88, 1.12) * (1.08 if sp > 5.0 else 1.0)
			_steps.volume_db = -8.0 if sp < 3.0 else -4.0
			_steps.play()
	_splash.emitting = grounded and sp > 3.5
	# clips
	if _dive_t > 0.0 or _knock_t > 0.0 or _lock_t > 0.0 or _shove_t > 0.0:
		return
	if not grounded and _air_t > 0.08:
		person.pose("run", 0.3 if velocity.y > 0.0 else 0.55, 0.15)
		return
	if sp > 3.0:
		person.play("run", 0.15, clampf(sp / 5.6, 0.8, 1.35))
	elif sp > 0.3:
		person.play("walk", 0.2, clampf(sp / WALK * 0.85, 0.6, 1.6))
	else:
		person.play("idle", 0.25)

# ------------------------------------------------------------------ camera

func _process(delta: float) -> void:
	if active:
		var look := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
		if look.length() > 0.15:
			cam_yaw -= look.x * 2.6 * delta
			cam_pitch = clampf(cam_pitch - look.y * 1.8 * delta, -1.1, 0.45)
	var sp := horizontal_speed()
	var spd_k := clampf((sp - JOG) / (SPRINT - JOG), 0.0, 1.0)
	# vertical follow is softer so kerbs and jumps don't jolt the frame
	var on_floor := is_on_floor()
	_cam_y = lerpf(_cam_y, global_position.y, clampf(delta * (10.0 if on_floor else 3.5), 0, 1))
	_dip = lerpf(_dip, 0.0, clampf(delta * 7.0, 0, 1))
	var fp := Vector3(global_position.x, _cam_y + 1.55 - _dip, global_position.z)
	pivot.global_position = pivot.global_position.lerp(fp, clampf(delta * 16.0, 0, 1))
	pivot.rotation = Vector3(cam_pitch, cam_yaw, 0)
	var want_fov := FOV_BASE + 9.0 * spd_k + (7.0 if _dive_t > 0.0 else 0.0)
	_fov = lerpf(_fov, want_fov, clampf(delta * 4.0, 0, 1))
	camera.fov = _fov
	_arm_len = lerpf(_arm_len, 3.5 + 0.6 * spd_k, clampf(delta * 3.0, 0, 1))
	arm.spring_length = _arm_len
	# trauma shake (squared for a soft falloff)
	trauma = maxf(0.0, trauma - delta * 1.4)
	_noise_t += delta * 18.0
	var s := trauma * trauma
	camera.rotation = Vector3(_noise.get_noise_2d(_noise_t, 0.0) * 0.06 * s, _noise.get_noise_2d(0.0, _noise_t) * 0.06 * s, _noise.get_noise_2d(_noise_t, _noise_t) * 0.08 * s)
	_update_pack()
