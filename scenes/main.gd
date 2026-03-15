extends Node2D

const ROUND_DURATION_SECONDS := 15
const LOW_TIME_TRIGGER_SECONDS := 10
const LOW_TIME_SCALE := 0.75
const HELPER_ROBOT_SCENE := preload("res://scenes/RobotHelper.tscn")
const EXHILARATE_TRACK_PATH := "res://assets/sound/music/Exhilarate.mp3"

var remainingSeconds: int = ROUND_DURATION_SECONDS
var tick_volume_quiet_db := -20.0
var tick_volume_loud_db := -4.0
var danger_seconds_threshold := 10
var timer_shake_amplitude_min := 0.8
var timer_shake_amplitude_max := 3.8
var timer_shake_speed_min := 12.0
var timer_shake_speed_max := 50.0
var uhoh_light_ramp_up_speed := 1.2
var uhoh_light_ramp_down_speed := 2.5
var camera_shake_amplitude_min := 0.15
var camera_shake_amplitude_max := 1.2
var round_music_base_pitch := 1.0
var round_music_base_volume_db := -8.0
var round_music_distortion_pitch_range := 0.12
var round_music_distortion_speed_min := 2.5
var round_music_distortion_speed_max := 9.0
var round_music_distortion_volume_drop_db := 2.0
var exhilarate_bpm := 170.0
var exhilarate_beat_zoom_amount := 0.035
var exhilarate_beat_zoom_decay := 0.2
var exhilarate_beat_start_delay := 0.764
var ui_default_alpha := 1.0
var ui_occluded_alpha := 0.72
var ui_alpha_lerp_speed := 8.0
var pto_shake_duration := 0.45
var pto_shake_amplitude := 10.0
var pto_shake_speed := 38.0

var _timer_label_base_position := Vector2.ZERO
var _camera_base_offset := Vector2.ZERO
var _camera_base_zoom := Vector2.ONE
var _timer_shake_time := 0.0
var _is_timer_shaking := false
var _helperRobots: Array = []
var _roundMusicDistortionTime := 0.0
var _ptoShakeTime := 0.0
var _ptoShakeRemaining := 0.0
@onready var _roundMusic: Node = get_node_or_null("RoundMusic")
@onready var _ui: CanvasItem = $Camera2D/CanvasLayer/UI

func _on_pto_consumed() -> void:
	_ptoShakeRemaining = pto_shake_duration
	_ptoShakeTime = 0.0

func _loadRoundMusic() -> AudioStream:
	if Global.wave >= Global.bestWave && Global.bestWave > 1:
		return load("res://assets/sound/music/Exhilarate.mp3")
	else:
		return load("res://assets/sound/music/Local Forecast.mp3")

func _getDesiredHelperRobotCount() -> int:
	if !Global.helperRobotUnlocked:
		return 0
	return 2 if Global.doubleCleanerBotUnlocked else 1

func _ensureHelperRobots() -> void:
	_helperRobots = _helperRobots.filter(func(robot): return robot != null && is_instance_valid(robot))
	var desiredCount := _getDesiredHelperRobotCount()
	if _helperRobots.size() >= desiredCount:
		return

	var shapeGeneratorNode := get_node_or_null("ShapeGenerator")
	var spawnBasePosition := Vector2(640, 360)
	if shapeGeneratorNode is Node2D:
		spawnBasePosition = (shapeGeneratorNode as Node2D).global_position

	var spawnOffsets := [Vector2(64, 24), Vector2(-64, 24)]
	while _helperRobots.size() < desiredCount:
		var robotInstance := HELPER_ROBOT_SCENE.instantiate()
		if !(robotInstance is Node2D):
			return
		var robotNode := robotInstance as Node2D
		add_child(robotNode)
		var spawnIndex: int = min(_helperRobots.size(), spawnOffsets.size() - 1)
		robotNode.global_position = spawnBasePosition + spawnOffsets[spawnIndex]
		_helperRobots.append(robotNode)

func _updateRoundTimeScale() -> void:
	var shouldSlowTime: bool = Global.lowTimeSlowMoUnlocked && !$Timer.is_stopped() && remainingSeconds > 0 && remainingSeconds <= LOW_TIME_TRIGGER_SECONDS
	Engine.time_scale = LOW_TIME_SCALE if shouldSlowTime else 1.0

func _playRoundMusic() -> void:
	if _roundMusic == null || !is_instance_valid(_roundMusic):
		return
	_roundMusic.stream = _loadRoundMusic()
	if "pitch_scale" in _roundMusic:
		_roundMusic.pitch_scale = round_music_base_pitch
	if "volume_db" in _roundMusic:
		_roundMusic.volume_db = round_music_base_volume_db
	if _roundMusic.has_method("play"):
		_roundMusic.play()

func _stopRoundMusic() -> void:
	if _roundMusic == null || !is_instance_valid(_roundMusic):
		return
	if _roundMusic.has_method("stop"):
		_roundMusic.stop()
	if "pitch_scale" in _roundMusic:
		_roundMusic.pitch_scale = round_music_base_pitch
	if "volume_db" in _roundMusic:
		_roundMusic.volume_db = round_music_base_volume_db
	_roundMusicDistortionTime = 0.0

func _updateRoundMusic(delta: float) -> void:
	if _roundMusic == null || !is_instance_valid(_roundMusic):
		return
	if !$Timer.is_stopped() && remainingSeconds > 0 && remainingSeconds <= danger_seconds_threshold:
		var dangerRatio := _getTimerDangerRatio()
		var shakeStrength := pow(dangerRatio, 1.2)
		var distortionSpeed: float = lerp(round_music_distortion_speed_min, round_music_distortion_speed_max, shakeStrength)
		_roundMusicDistortionTime += delta * distortionSpeed
		var distortionWave := sin(_roundMusicDistortionTime * 3.0) * round_music_distortion_pitch_range * shakeStrength
		if "pitch_scale" in _roundMusic:
			_roundMusic.pitch_scale = max(0.05, round_music_base_pitch * Engine.time_scale + distortionWave)
		if "volume_db" in _roundMusic:
			_roundMusic.volume_db = round_music_base_volume_db - round_music_distortion_volume_drop_db * shakeStrength
	else:
		if "pitch_scale" in _roundMusic:
			_roundMusic.pitch_scale = max(0.05, round_music_base_pitch * Engine.time_scale)
		if "volume_db" in _roundMusic:
			_roundMusic.volume_db = round_music_base_volume_db

func _isExhilaratePlaying() -> bool:
	if _roundMusic == null || !is_instance_valid(_roundMusic):
		return false
	if !(_roundMusic is AudioStreamPlayer2D):
		return false
	var round_music_player := _roundMusic as AudioStreamPlayer2D
	if !round_music_player.playing || round_music_player.stream == null:
		return false
	return round_music_player.stream.resource_path == EXHILARATE_TRACK_PATH

func _getExhilarateBeatZoom() -> Vector2:
	if !_isExhilaratePlaying() || exhilarate_bpm <= 0.0:
		return _camera_base_zoom

	var round_music_player := _roundMusic as AudioStreamPlayer2D
	var playback_position := round_music_player.get_playback_position()
	if playback_position < exhilarate_beat_start_delay:
		return _camera_base_zoom

	var beat_duration := 60.0 / exhilarate_bpm
	if beat_duration <= 0.0:
		return _camera_base_zoom

	var beat_phase := fposmod(playback_position - exhilarate_beat_start_delay, beat_duration) / beat_duration
	var pulse_strength := exp(-beat_phase / exhilarate_beat_zoom_decay)
	var zoom_scale: float = max(0.1, 1.0 - exhilarate_beat_zoom_amount * pulse_strength)
	return _camera_base_zoom * zoom_scale

func _updateTickVolume() -> void:
	var elapsed_ratio: float = clamp(1.0 - (float(remainingSeconds) / float(ROUND_DURATION_SECONDS)), 0.0, 1.0)
	$Camera2D/CanvasLayer/UI/TimerTick.volume_db = lerp(tick_volume_quiet_db, tick_volume_loud_db, elapsed_ratio)

func _setTimerLabelShake(active: bool) -> void:
	if _is_timer_shaking == active:
		return

	_is_timer_shaking = active
	if !_is_timer_shaking:
		_timer_shake_time = 0.0
		$Camera2D/CanvasLayer/UI/TimerLabel.position = _timer_label_base_position
		$Camera2D.offset = _camera_base_offset

func _getTimerDangerRatio() -> float:
	if danger_seconds_threshold <= 1:
		return 1.0
	var remaining_in_danger: int = clamp(remainingSeconds, 1, danger_seconds_threshold)
	return clamp(1.0 - (float(remaining_in_danger - 1) / float(danger_seconds_threshold - 1)), 0.0, 1.0)

func _getShapeScreenRect(shape_node: Node2D) -> Rect2:
	var screen_position: Vector2 = get_viewport().get_canvas_transform() * shape_node.global_position
	var half_extents := Vector2(12, 12)
	var sprite := shape_node.get_node_or_null("Sprite2D")
	if sprite is Sprite2D && sprite.texture != null:
		half_extents = (sprite.texture.get_size() * sprite.scale) * 0.5
	return Rect2(screen_position - half_extents, half_extents * 2.0)

func _isAnyShapeBehindUI() -> bool:
	if _ui == null || !_ui.visible || !(_ui is Control):
		return false

	var ui_rect: Rect2 = (_ui as Control).get_global_rect()
	for candidate in get_tree().get_nodes_in_group("shapes"):
		if !(candidate is Node2D):
			continue
		if candidate.is_queued_for_deletion() || !candidate.visible:
			continue
		if ui_rect.intersects(_getShapeScreenRect(candidate as Node2D)):
			return true
	return false

func _updateUIOcclusionFade(delta: float) -> void:
	if _ui == null:
		return

	var target_alpha := ui_default_alpha
	if _isAnyShapeBehindUI():
		target_alpha = ui_occluded_alpha

	_ui.modulate.a = move_toward(_ui.modulate.a, target_alpha, ui_alpha_lerp_speed * delta)

func _process(delta: float) -> void:
	_ensureHelperRobots()
	_updateRoundTimeScale()
	_updateRoundMusic(delta)
	_updateUIOcclusionFade(delta)
	var camera_offset := _camera_base_offset
	var target_light_energy := 0.0
	if _is_timer_shaking:
		var danger_ratio := _getTimerDangerRatio()
		var shake_strength := pow(danger_ratio, 1.2)
		var shake_speed: float = lerp(timer_shake_speed_min, timer_shake_speed_max, shake_strength)
		var shake_amplitude: float = lerp(timer_shake_amplitude_min, timer_shake_amplitude_max, shake_strength)
		var camera_shake_amplitude: float = lerp(camera_shake_amplitude_min, camera_shake_amplitude_max, shake_strength)

		_timer_shake_time += delta * shake_speed
		var shake_offset = Vector2(sin(_timer_shake_time * 1.7), cos(_timer_shake_time * 2.3)) * shake_amplitude
		$Camera2D/CanvasLayer/UI/TimerLabel.position = _timer_label_base_position + shake_offset

		var camera_shake_offset = Vector2(cos(_timer_shake_time * 2.1), sin(_timer_shake_time * 1.5)) * camera_shake_amplitude
		camera_offset += camera_shake_offset

		target_light_energy = danger_ratio
	else:
		$Camera2D/CanvasLayer/UI/TimerLabel.position = _timer_label_base_position

	if _ptoShakeRemaining > 0.0:
		_ptoShakeRemaining = max(_ptoShakeRemaining - delta, 0.0)
		var pto_intensity: float = _ptoShakeRemaining / max(pto_shake_duration, 0.001)
		_ptoShakeTime += delta * pto_shake_speed
		var pto_shake_offset: Vector2 = Vector2(cos(_ptoShakeTime * 2.9), sin(_ptoShakeTime * 3.7)) * pto_shake_amplitude * pto_intensity
		camera_offset += pto_shake_offset

	$Camera2D.offset = camera_offset
	$Camera2D.zoom = _getExhilarateBeatZoom()

	var current_light_energy: float = $UhOhLights.energy
	var ramp_speed := uhoh_light_ramp_up_speed if target_light_energy > current_light_energy else uhoh_light_ramp_down_speed
	$UhOhLights.energy = move_toward(current_light_energy, target_light_energy, ramp_speed * delta)

func _ready() -> void:
	Engine.time_scale = 1.0
	$Camera2D/CanvasLayer/AnimationPlayer.play("Fade In")
	Global.loss.connect(_playBuzzerSound)
	Global.loss.connect(_stopRoundMusic)
	Global.ptoConsumed.connect(_on_pto_consumed)
	Global.nextWave.connect(_on_next_wave)
	Global.stopTimerEarly.connect(_stopTimer)
	_timer_label_base_position = $Camera2D/CanvasLayer/UI/TimerLabel.position
	_camera_base_offset = $Camera2D.offset
	_camera_base_zoom = $Camera2D.zoom
	$UhOhLights.energy = 0.0
	$Camera2D/CanvasLayer/UI.hide()
	_roundMusic.stream = _loadRoundMusic()
	Global.startGame()
	var fired_label := $Camera2D/CanvasLayer/LossScreen/VBoxContainer/Label as Label
	if fired_label != null:
		var base_font := fired_label.get_theme_font("font") as FontFile
		if base_font != null:
			var font_copy := base_font.duplicate() as FontFile
			font_copy.fallbacks = [ThemeDB.fallback_font]
			fired_label.add_theme_font_override("font", font_copy)

func _playBuzzerSound() -> void:
	$LoudBuzzerIdk.play()

func _stopTimer() -> void:
	Engine.time_scale = 1.0
	_stopRoundMusic()
	_setTimerLabelShake(false)
	$Camera2D/CanvasLayer/UI.hide()
	$Camera2D.zoom = _camera_base_zoom
	$Timer.stop()

func _on_next_wave() -> void:
	Engine.time_scale = 1.0
	remainingSeconds = ROUND_DURATION_SECONDS + Global.timeBonus
	_roundMusic.stream = _loadRoundMusic()
	_setTimerLabelShake(false)
	$Camera2D/CanvasLayer/UI/TimerLabel.text = str(remainingSeconds)
	$Camera2D/CanvasLayer/UI/WaveLabel.text = "WAVE " + str(Global.wave)
	_updateTickVolume()
	_playRoundMusic()
	$Camera2D/CanvasLayer/UI.show()
	$Timer.start()

func _on_timer_timeout() -> void:
	remainingSeconds -= 1
	_setTimerLabelShake(remainingSeconds > 0 && remainingSeconds <= danger_seconds_threshold)
	_updateTickVolume()
	$Camera2D/CanvasLayer/UI/TimerTick.play()
	$Camera2D/CanvasLayer/UI/TimerLabel.text = str(remainingSeconds)
	if remainingSeconds <= 0:
		Engine.time_scale = 1.0
		_stopRoundMusic()
		_setTimerLabelShake(false)
		$Timer.stop()
		$Camera2D.zoom = _camera_base_zoom
		Global._tryOpenAllDepots()
		$Camera2D/CanvasLayer/UI.hide()

func _exit_tree() -> void:
	Engine.time_scale = 1.0
	_stopRoundMusic()
	$Camera2D.zoom = _camera_base_zoom

func _on_retry_button_pressed() -> void:
	$Camera2D/CanvasLayer/AnimationPlayer.play("Fade Out")
	await $Camera2D/CanvasLayer/AnimationPlayer.animation_finished
	var tree := get_tree()
	if tree == null:
		return
	tree.reload_current_scene()

func _on_menu_button_pressed() -> void:
	$Camera2D/CanvasLayer/AnimationPlayer.play("Fade Out")
	await $Camera2D/CanvasLayer/AnimationPlayer.animation_finished
	var tree := get_tree()
	if tree == null:
		return
	tree.change_scene_to_file("res://scenes/menu.tscn")
