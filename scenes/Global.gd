extends Node

const SAVE_PATH := "user://save.save"
const SHAPE_SPATIAL_CELL_SIZE := 150.0

var wave: int = 1
var bestWave: int = 1
var seenTutorial: bool = false
var inGame: bool = false
var _depotAnimationLocks := 0
var _activeDragShapeIds := {}
var _activeDragShapeType := -1
var _flickeringShapeIds := {}
var _shapeSpatialBuckets := {}
var _shapeSpatialFrame := -1
var _shapeSpatialDirty := true
var timeBonus: int = 0
var maxPickupCount := 1
var pickupRangeBonus := 0.0
var shapeFriction := 0.45
var shapeSpawnIntervalMultiplier := 1.0
var pentagonSpawnChanceMultiplier := 1.0
var shrinkingDepotsUnlocked := false
var shrinkingDepotScale := 0.65
var noShapeCollisionsUnlocked := false
var shapeInfectionUnlocked := false
var sameTypeAttractionUnlocked := false
var stickyDepotsUnlocked := false
var magnetDepotsUnlocked := false
var lowTimeSlowMoUnlocked := false
var helperRobotUnlocked := false
var doubleCleanerBotUnlocked := false
var cleanerBotSpeedMultiplier := 1.0
var depotShuffleUnlocked := false
var randomizeDepotsRoundsRemaining := 0
var deathShieldActive: bool = false
var _depotBaseShapes := {}
var _depotShuffledShapes := {}
var inTutorial := false
var canOpenDepotsEarly := true
var _tutorial2Started := false

signal nextWave
signal upgrades
signal stopTimerEarly
signal loss
signal ptoConsumed

const LOSS_FLICKER_COUNT := 8
const LOSS_FLICKER_INTERVAL_SECONDS := 0.08

func _currentSettings() -> Dictionary:
	return {
		"music_volume": AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")),
		"sfx_volume": AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")),
		"fullscreen": DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN,
		"vsync": DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED,
		"max_fps": Engine.max_fps
	}

func _applySettings(settings: Dictionary) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), float(settings.get("music_volume", 0.0)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), float(settings.get("sfx_volume", 0.0)))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if bool(settings.get("fullscreen", false)) else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(settings.get("vsync", true)) else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = settings.get("max_fps")

func endTutorialDialogue() -> void:
	Dialogic.start("dialogic/end_tutorial")

func startTutorial() -> void:
	var current_scene := get_tree().current_scene
	var tutorial_music = current_scene.get_node_or_null("TutorialMusic")
	tutorial_music.play()
	inTutorial = true
	canOpenDepotsEarly = false
	_tutorial2Started = false

func allowEarlyDepotOpening() -> void:
	canOpenDepotsEarly = true

func disallowEarlyDepotOpening() -> void:
	canOpenDepotsEarly = false

func _process(_delta: float) -> void:
	if inTutorial && !_tutorial2Started && !isShapeDragActive() && _allDepotsHaveTheirShapes():
		_tutorial2Started = true
		Dialogic.start("dialogic/tutorial2")

func _allDepotsHaveTheirShapes() -> bool:
	if !inTutorial:
		return false

	var depots = get_tree().get_nodes_in_group("depots")
	if depots.is_empty():
		return false

	for depot in depots:
		if !depot.has_method("_getShapeBodiesInZone"):
			return false
		if !("shape" in depot):
			return false

		var shapes_in_zone = depot._getShapeBodiesInZone()
		if shapes_in_zone.is_empty():
			return false

		for shape_body in shapes_in_zone:
			if shape_body == null || !is_instance_valid(shape_body) || shape_body.is_queued_for_deletion():
				return false
			if !("shape" in shape_body):
				return false
			if int(shape_body.shape) != int(depot.shape):
				return false

	return true

func _defaultSaveData() -> Dictionary:
	return {
		"best_wave": 1,
		"seen_tutorial": false,
		"settings": _currentSettings()
	}

func _applySaveData(data: Dictionary) -> void:
	bestWave = max(int(data.get("best_wave", 1)), 1)
	seenTutorial = bool(data.get("seen_tutorial", false))
	_applySettings(data.get("settings", _currentSettings()))

func _buildSaveData() -> Dictionary:
	return {
		"best_wave": max(bestWave, 1),
		"seen_tutorial": seenTutorial,
		"settings": _currentSettings()
	}

func getSettings() -> Dictionary:
	return _buildSaveData().get("settings", {})

func _ready() -> void:
	loadSaveData()
	nextWave.connect(_onNextWaveApplyRoundModifiers)

func _onNextWaveApplyRoundModifiers() -> void:
	_applyDepotShapesForRound()

func _applyDepotShapesForRound() -> void:
	var depots = get_tree().get_nodes_in_group("depots")
	if depots.is_empty():
		return

	for depot in depots:
		if !("shape" in depot):
			continue
		var depot_id: int = depot.get_instance_id()
		if !_depotBaseShapes.has(depot_id):
			_depotBaseShapes[depot_id] = int(depot.shape)

	if depotShuffleUnlocked:
		_ensureDepotShuffleLayout(depots)
		for depot in depots:
			if !("shape" in depot):
				continue
			var depot_id: int = depot.get_instance_id()
			if _depotShuffledShapes.has(depot_id):
				depot.shape = int(_depotShuffledShapes[depot_id])
			elif _depotBaseShapes.has(depot_id):
				depot.shape = int(_depotBaseShapes[depot_id])
		return

	if randomizeDepotsRoundsRemaining > 0:
		var shuffled_shapes: Array = []
		for depot in depots:
			if !("shape" in depot):
				continue
			var depot_id: int = depot.get_instance_id()
			shuffled_shapes.append(int(_depotBaseShapes.get(depot_id, int(depot.shape))))
		shuffled_shapes.shuffle()

		var shape_index := 0
		for depot in depots:
			if !("shape" in depot):
				continue
			if shape_index >= shuffled_shapes.size():
				break
			depot.shape = shuffled_shapes[shape_index]
			shape_index += 1

		randomizeDepotsRoundsRemaining = max(randomizeDepotsRoundsRemaining - 1, 0)
		return

	for depot in depots:
		if !("shape" in depot):
			continue
		var depot_id: int = depot.get_instance_id()
		if _depotBaseShapes.has(depot_id):
			depot.shape = int(_depotBaseShapes[depot_id])

func _ensureDepotShuffleLayout(depots: Array) -> void:
	if _hasValidDepotShuffleLayout(depots):
		return

	var shuffled_shapes: Array = []
	for depot in depots:
		if !("shape" in depot):
			continue
		var depot_id: int = depot.get_instance_id()
		shuffled_shapes.append(int(_depotBaseShapes.get(depot_id, int(depot.shape))))
	shuffled_shapes.shuffle()

	_depotShuffledShapes.clear()
	var shape_index := 0
	for depot in depots:
		if !("shape" in depot):
			continue
		if shape_index >= shuffled_shapes.size():
			break
		var depot_id: int = depot.get_instance_id()
		_depotShuffledShapes[depot_id] = shuffled_shapes[shape_index]
		shape_index += 1

func _hasValidDepotShuffleLayout(depots: Array) -> bool:
	if _depotShuffledShapes.is_empty():
		return false

	for depot in depots:
		if !("shape" in depot):
			continue
		if !_depotShuffledShapes.has(depot.get_instance_id()):
			return false

	return true

func rerollDepotShuffle() -> void:
	depotShuffleUnlocked = true
	_depotShuffledShapes.clear()

func loadSaveData() -> void:
	if !FileAccess.file_exists(SAVE_PATH):
		_applySaveData(_defaultSaveData())
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		_applySaveData(_defaultSaveData())
		return

	var saved_text := file.get_as_text().strip_edges()
	if saved_text == "":
		_applySaveData(_defaultSaveData())
		return

	var parsed_json = JSON.parse_string(saved_text)
	if typeof(parsed_json) == TYPE_DICTIONARY:
		var parsed_save_data: Dictionary = _defaultSaveData()
		parsed_save_data.merge(parsed_json, true)
		_applySaveData(parsed_save_data)
		return

	if saved_text.is_valid_int():
		_applySaveData({
			"best_wave": max(saved_text.to_int(), 1),
			"seen_tutorial": false
		})
		save_data()
	else:
		_applySaveData(_defaultSaveData())

func save_data() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_buildSaveData()))

func setSeenTutorial(value: bool = true) -> void:
	if seenTutorial == value:
		return
	seenTutorial = value
	if !_tutorial2Started:
		nextWave.emit()
		wave = 1
	inTutorial = false
	var current_scene := get_tree().current_scene
	var tutorial_music = current_scene.get_node_or_null("TutorialMusic")
	tutorial_music.stop()
	save_data()

func updateBestWave(candidate_wave: int) -> void:
	if candidate_wave <= bestWave:
		return
	bestWave = candidate_wave
	save_data()

func startGame() -> void:
	wave = 1
	inGame = true
	_tutorial2Started = false
	timeBonus = 0
	maxPickupCount = 1
	pickupRangeBonus = 0.0
	shapeFriction = 0.45
	shapeSpawnIntervalMultiplier = 1.0
	pentagonSpawnChanceMultiplier = 1.0
	shrinkingDepotsUnlocked = false
	noShapeCollisionsUnlocked = false
	shapeInfectionUnlocked = false
	sameTypeAttractionUnlocked = false
	stickyDepotsUnlocked = false
	magnetDepotsUnlocked = false
	lowTimeSlowMoUnlocked = false
	helperRobotUnlocked = false
	doubleCleanerBotUnlocked = false
	cleanerBotSpeedMultiplier = 1.0
	depotShuffleUnlocked = false
	randomizeDepotsRoundsRemaining = 0
	deathShieldActive = false
	_depotBaseShapes.clear()
	_depotShuffledShapes.clear()
	_activeDragShapeIds.clear()
	_activeDragShapeType = -1
	if !seenTutorial:
		Dialogic.start("dialogic/tutorial")
	else:
		nextWave.emit()

func beginDepotAnimation() -> void:
	_depotAnimationLocks += 1

func endDepotAnimation() -> void:
	var previous_locks := _depotAnimationLocks
	_depotAnimationLocks = max(_depotAnimationLocks - 1, 0)
	if previous_locks > 0 && _depotAnimationLocks == 0:
		if inTutorial:
			Dialogic.start("dialogic/tutorial3")
		inGame = true
		wave += 1
		upgrades.emit()

func isDragLocked() -> bool:
	return _depotAnimationLocks > 0 || !inGame

func tryBeginShapeDrag(shape: Node) -> bool:
	if shape == null:
		return false
	if isDragLocked():
		return false
	if !("shape" in shape):
		return false

	var shape_id := shape.get_instance_id()
	if _activeDragShapeIds.has(shape_id):
		return true

	var candidate_shape_type := int(shape.shape)
	if !_activeDragShapeIds.is_empty() && _activeDragShapeType != candidate_shape_type:
		return false

	if _activeDragShapeIds.size() >= maxPickupCount:
		return false

	if _activeDragShapeIds.is_empty():
		_activeDragShapeType = candidate_shape_type
	_activeDragShapeIds[shape_id] = true
	return true

func endShapeDrag(shape: Node) -> void:
	if shape == null:
		return
	_activeDragShapeIds.erase(shape.get_instance_id())
	if _activeDragShapeIds.is_empty():
		_activeDragShapeType = -1

func isShapeDragActive() -> bool:
	return !_activeDragShapeIds.is_empty()

func shouldShapeClaimClick(shape: Node, world_position: Vector2, pickup_padding_value: float) -> bool:
	if shape == null || !is_instance_valid(shape) || shape.is_queued_for_deletion():
		return false

	var best_shape: Node = null
	var best_distance_sq := INF
	var best_z_index := -INF
	var best_tree_index := -INF

	for candidate in _getActiveShapes():
		if candidate == null || !is_instance_valid(candidate) || candidate.is_queued_for_deletion():
			continue
		if !(candidate is Node2D):
			continue
		if !candidate.has_method("canPickAtWorldPosition"):
			continue
		if !candidate.canPickAtWorldPosition(world_position, pickup_padding_value):
			continue

		var candidate_node := candidate as Node2D
		var distance_sq := candidate_node.global_position.distance_squared_to(world_position)
		var candidate_z_index := candidate_node.z_index
		var candidate_tree_index := candidate_node.get_index()

		if best_shape == null:
			best_shape = candidate
			best_distance_sq = distance_sq
			best_z_index = candidate_z_index
			best_tree_index = candidate_tree_index
			continue

		var is_better := false
		if distance_sq < best_distance_sq - 0.0001:
			is_better = true
		elif absf(distance_sq - best_distance_sq) <= 0.0001:
			if candidate_z_index > best_z_index:
				is_better = true
			elif candidate_z_index == best_z_index && candidate_tree_index > best_tree_index:
				is_better = true

		if is_better:
			best_shape = candidate
			best_distance_sq = distance_sq
			best_z_index = candidate_z_index
			best_tree_index = candidate_tree_index

	return best_shape == shape

func refreshShapeModifiers() -> void:
	for shape_body in _getActiveShapes():
		if shape_body.has_method("applyGlobalModifiers"):
			shape_body.applyGlobalModifiers()

func markShapeSpatialCacheDirty() -> void:
	_shapeSpatialDirty = true

func getNearbyShapesOfType(shape_type: int, world_position: Vector2, radius: float) -> Array:
	_refreshShapeSpatialCache()

	var nearby_shapes: Array = []
	var bucket_map: Dictionary = _shapeSpatialBuckets.get(shape_type, {})
	if bucket_map.is_empty():
		return nearby_shapes

	var min_cell := _getShapeSpatialCell(world_position - Vector2.ONE * radius)
	var max_cell := _getShapeSpatialCell(world_position + Vector2.ONE * radius)
	for cell_x in range(min_cell.x, max_cell.x + 1):
		for cell_y in range(min_cell.y, max_cell.y + 1):
			var cell_shapes: Array = bucket_map.get(Vector2i(cell_x, cell_y), [])
			nearby_shapes.append_array(cell_shapes)

	return nearby_shapes

func spawnTutorialShapes() -> bool:
	var generator: Node = null
	var current_scene := get_tree().current_scene
	if current_scene != null:
		generator = current_scene.get_node_or_null("ShapeGenerator")

	if generator == null:
		var generators = get_tree().get_nodes_in_group("shape_generators")
		if !generators.is_empty():
			generator = generators[0]

	if generator == null:
		return false
	if !generator.has_method("startTutorialSpawnCycle"):
		return false

	generator.startTutorialSpawnCycle()
	return true

func _stopAllShapeGenerators() -> void:
	for generator in get_tree().get_nodes_in_group("shape_generators"):
		if generator == null || !is_instance_valid(generator):
			continue
		if generator.has_method("stopSpawning"):
			generator.stopSpawning()

func applyNoShapeCollisions() -> void:
	var shapes := _getActiveShapes()
	for i in range(shapes.size()):
		var shape_a = shapes[i]
		if !(shape_a is PhysicsBody2D):
			continue
		for j in range(i + 1, shapes.size()):
			var shape_b = shapes[j]
			if !(shape_b is PhysicsBody2D):
				continue
			shape_a.add_collision_exception_with(shape_b)
			shape_b.add_collision_exception_with(shape_a)

func applyNoShapeCollisionsFor(shape: PhysicsBody2D) -> void:
	if shape == null:
		return
	for other_shape in _getActiveShapes():
		if other_shape == shape:
			continue
		if !(other_shape is PhysicsBody2D):
			continue
		shape.add_collision_exception_with(other_shape)
		other_shape.add_collision_exception_with(shape)

func _shapeName(shape_value: int) -> String:
	match shape_value:
		0:
			return "SQUARE"
		1:
			return "CIRCLE"
		2:
			return "TRIANGLE"
		3:
			return "PENTAGON"
		_:
			return "UNKNOWN"

func _getActiveShapes() -> Array:
	var all_shapes = get_tree().get_nodes_in_group("shapes")
	return all_shapes.filter(func(shape): return shape != null && !shape.is_queued_for_deletion())

func _refreshShapeSpatialCache() -> void:
	var current_physics_frame := Engine.get_physics_frames()
	if !_shapeSpatialDirty && _shapeSpatialFrame == current_physics_frame:
		return

	_shapeSpatialBuckets.clear()
	for shape_body in _getActiveShapes():
		if !(shape_body is Node2D):
			continue
		if !("shape" in shape_body):
			continue

		var shape_type := int(shape_body.shape)
		if !_shapeSpatialBuckets.has(shape_type):
			_shapeSpatialBuckets[shape_type] = {}

		var bucket_map: Dictionary = _shapeSpatialBuckets[shape_type]
		var spatial_cell := _getShapeSpatialCell((shape_body as Node2D).global_position)
		if !bucket_map.has(spatial_cell):
			bucket_map[spatial_cell] = []
		bucket_map[spatial_cell].append(shape_body)

	_shapeSpatialFrame = current_physics_frame
	_shapeSpatialDirty = false

func _getShapeSpatialCell(world_position: Vector2) -> Vector2i:
	return Vector2i(floori(world_position.x / SHAPE_SPATIAL_CELL_SIZE), floori(world_position.y / SHAPE_SPATIAL_CELL_SIZE))

func _isPentagonShape(shape_body: Node) -> bool:
	if shape_body == null || !is_instance_valid(shape_body):
		return false
	if !("shape" in shape_body):
		return false
	return int(shape_body.shape) == 3

func _getUnsortedShapes(depots: Array) -> Array:
	var shape_idsInDepots := {}
	for depot in depots:
		if !depot.has_method("_getShapeBodiesInZone"):
			continue
		for shape_body in depot._getShapeBodiesInZone():
			shape_idsInDepots[shape_body.get_instance_id()] = true

	var unsorted_shapes: Array = []
	for shape_body in _getActiveShapes():
		if _isPentagonShape(shape_body):
			continue
		if !shape_idsInDepots.has(shape_body.get_instance_id()):
			unsorted_shapes.append(shape_body)
	return unsorted_shapes

func _despawnUnsortedPentagons() -> void:
	for shape_body in _getActiveShapes():
		if _isPentagonShape(shape_body):
			shape_body.fadeAwayAndDespawn()

func _getIncorrectShapesInDepots(depots: Array) -> Array:
	var incorrect_shapes: Array = []
	for depot in depots:
		if !depot.has_method("_getShapeBodiesInZone"):
			continue
		if !("shape" in depot):
			continue
		for shape_body in depot._getShapeBodiesInZone():
			if !("shape" in shape_body):
				continue
			if int(shape_body.shape) != int(depot.shape):
				incorrect_shapes.append(shape_body)
	return incorrect_shapes

func _flickerShapeVisibility(shape_body: Node2D) -> void:
	if shape_body == null || !is_instance_valid(shape_body) || shape_body.is_queued_for_deletion():
		return

	var shape_id: int = shape_body.get_instance_id()
	if _flickeringShapeIds.has(shape_id):
		return

	_flickeringShapeIds[shape_id] = true
	for i in range(LOSS_FLICKER_COUNT):
		if !is_instance_valid(shape_body) || shape_body.is_queued_for_deletion():
			break
		shape_body.visible = !shape_body.visible
		await get_tree().create_timer(LOSS_FLICKER_INTERVAL_SECONDS).timeout

	if is_instance_valid(shape_body) && !shape_body.is_queued_for_deletion():
		shape_body.visible = true

	_flickeringShapeIds.erase(shape_id)

func _flickerLossShapes(shapes: Array) -> void:
	var unique_shape_ids := {}
	for shape_body in shapes:
		if shape_body == null || !is_instance_valid(shape_body) || shape_body.is_queued_for_deletion():
			continue
		var shape_id: int = shape_body.get_instance_id()
		if unique_shape_ids.has(shape_id):
			continue
		unique_shape_ids[shape_id] = true
		if shape_body is Node2D:
			_flickerShapeVisibility(shape_body)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("earlyOpen") && inGame && canOpenDepotsEarly:
		if isDragLocked():
			return
		if _tryOpenAllDepots():
			stopTimerEarly.emit()

func _tryOpenAllDepots() -> bool:
	var depots = get_tree().get_nodes_in_group("depots")
	if depots.is_empty():
		return false

	if _getActiveShapes().is_empty():
		return false

	var unsorted_shapes = _getUnsortedShapes(depots)
	var incorrect_shapes = _getIncorrectShapesInDepots(depots)
	if !unsorted_shapes.is_empty() || !incorrect_shapes.is_empty():
		lose(unsorted_shapes + incorrect_shapes)
		return true

	var all_ready := true
	for depot in depots:
		if depot.has_method("isReadyToOpen") && !depot.isReadyToOpen():
			all_ready = false
			break

	if all_ready:
		_stopAllShapeGenerators()
		_despawnUnsortedPentagons()
		for depot in depots:
			if depot.has_method("haltShapesInZone"):
				depot.haltShapesInZone()
		for depot in depots:
			if depot.has_method("openDepot"):
				depot.openDepot()
		return true

	lose(incorrect_shapes)
	return true

func lose(offending_shapes: Array = []) -> void:
	if deathShieldActive && !offending_shapes.is_empty():
		deathShieldActive = false
		ptoConsumed.emit()
		get_tree().current_scene.get_node_or_null("PTOSound").play()
		_stopAllShapeGenerators()
		for shape_body in offending_shapes:
			if shape_body != null && is_instance_valid(shape_body) && !shape_body.is_queued_for_deletion():
				if shape_body.has_method("fadeAwayAndDespawn"):
					shape_body.fadeAwayAndDespawn()
		var depots := get_tree().get_nodes_in_group("depots")
		for depot in depots:
			if depot.has_method("haltShapesInZone"):
				depot.haltShapesInZone()
		for depot in depots:
			if depot.has_method("openDepot"):
				depot.openDepot()
		return
	loss.emit()
	inGame = false
	_flickerLossShapes(offending_shapes)
