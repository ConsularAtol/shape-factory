extends Node2D

@export var shape_scene: PackedScene
var shapesPerSpawn := 3
@export var launch_cone_degrees := 80.0
@export var launch_speed_min := 260.0
@export var launch_speed_max := 460.0
@export var muzzle_offset := 16.0
@export var muzzle_spread := 10.0
@export var burst_spread_per_shape := 2.0
@export var burst_lane_jitter := 0.35
@export var rapid_spawn_interval := 0.02
@export var max_burst_spread := 22.0
@export var regular_shape_weight := 1.0
@export var pentagon_spawn_weight := 0.35
const PENTAGON_UNLOCK_WAVE := 5

var _isSpawning := false
var _tutorialSpawnPending := false
var _spawnCanceled := false

func _ready() -> void:
	add_to_group("shape_generators")
	Global.nextWave.connect(prepareNextWave)

func prepareNextWave():
	$SpawnCount.text = "0"
	_spawnCanceled = false
	var wave_index := int(max(Global.wave - 1, 0))
	shapesPerSpawn = 3 + int(round(pow(float(wave_index), 1.6)))
	$AnimationPlayer.play("Open")

func stopSpawning() -> void:
	_spawnCanceled = true
	_tutorialSpawnPending = false

func spawnShapes(count: int = -1) -> void:
	if shape_scene == null:
		return
	if _spawnCanceled:
		return

	_isSpawning = true
	var spawn_count = shapesPerSpawn if count < 0 else count
	for i in range(spawn_count):
		if _spawnCanceled:
			break
		_spawnShapeWithType(_pickRandomShapeType(), i, spawn_count)
		$SpawnCount.text = str(int($SpawnCount.text) + 1)

		if i < spawn_count - 1:
			var scaled_interval := float(max(rapid_spawn_interval * Global.shapeSpawnIntervalMultiplier, 0.005))
			await get_tree().create_timer(scaled_interval).timeout
			if _spawnCanceled:
				break

	_isSpawning = false

func _pickRandomShapeType() -> int:
	if Global.wave < PENTAGON_UNLOCK_WAVE:
		return randi() % 3

	var regular_weight_total: float = max(regular_shape_weight, 0.0) * 3.0
	var base_pentagon_weight: float = max(pentagon_spawn_weight, 0.0)
	var total_weight := regular_weight_total + base_pentagon_weight

	if total_weight <= 0.0:
		return randi() % 3

	if regular_weight_total <= 0.0:
		return 3

	var base_pentagon_chance := base_pentagon_weight / total_weight
	var adjusted_pentagon_chance := clampf(base_pentagon_chance * max(Global.pentagonSpawnChanceMultiplier, 0.0), 0.0, 0.95)
	if randf() < adjusted_pentagon_chance:
		return 3

	return randi() % 3

func spawnOneOfEachType() -> void:
	if shape_scene == null || _isSpawning:
		return
	if _spawnCanceled:
		return

	_isSpawning = true
	var tutorial_types := [0, 1, 2, 3]
	for i in range(tutorial_types.size()):
		if _spawnCanceled:
			break
		_spawnShapeWithType(tutorial_types[i], i, tutorial_types.size())
		if i < tutorial_types.size() - 1:
			var scaled_interval := float(max(rapid_spawn_interval * Global.shapeSpawnIntervalMultiplier, 0.005))
			await get_tree().create_timer(scaled_interval).timeout
			if _spawnCanceled:
				break
	_isSpawning = false

func startTutorialSpawnCycle() -> void:
	if shape_scene == null:
		return
	if _isSpawning:
		return
	if $AnimationPlayer.is_playing():
		return

	_tutorialSpawnPending = true
	$AnimationPlayer.play("Open")

func _spawnShapeWithType(shape_type: int, spawn_index: int = 0, spawn_total: int = 1) -> void:
	if shape_scene == null:
		return

	var shape_instance = shape_scene.instantiate()
	shape_instance.shape = shape_type
	add_child(shape_instance)

	var lane_position := 0.5
	if spawn_total > 1:
		lane_position = float(spawn_index) / float(spawn_total - 1)

	var lane_jitter := 0.0
	if spawn_total > 1:
		lane_jitter = randf_range(-0.5, 0.5) * (burst_lane_jitter / float(spawn_total - 1))

	var lane_with_jitter := clampf(lane_position + lane_jitter, 0.0, 1.0)
	var launch_angle = lerpf(-launch_cone_degrees * 0.5, launch_cone_degrees * 0.5, lane_with_jitter)
	var launch_direction = Vector2.UP.rotated(deg_to_rad(launch_angle))
	var perpendicular = Vector2(-launch_direction.y, launch_direction.x)
	var spread_growth = max(spawn_total - 1, 0) * burst_spread_per_shape
	var burst_spread = min(muzzle_spread + spread_growth, max_burst_spread)
	var side_offset = perpendicular * randf_range(-burst_spread, burst_spread)
	shape_instance.global_position = global_position + launch_direction * muzzle_offset + side_offset

	if shape_instance is RigidBody2D:
		shape_instance.gravity_scale = 0.0
		shape_instance.sleeping = false
		shape_instance.angular_velocity = 0.0
		var launch_speed = randf_range(launch_speed_min, launch_speed_max)
		shape_instance.linear_velocity = launch_direction * launch_speed

func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "Open":
		if _spawnCanceled:
			_tutorialSpawnPending = false
			$AnimationPlayer.play("Close")
			return
		if _tutorialSpawnPending:
			_tutorialSpawnPending = false
			await spawnOneOfEachType()
		else:
			await spawnShapes()
		$AnimationPlayer.play("Close")
