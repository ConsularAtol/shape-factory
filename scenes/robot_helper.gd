extends RigidBody2D

@export var moveSpeed := 120.0
@export var maxSpeed := 140.0
@export var steeringForce := 24.0
@export var arriveDistance := 14.0
@export var pickupDistance := 18.0
@export var grabAssistDistance := 34.0
@export var grabAssistPullSpeed := 180.0
@export var maxPursuitSeconds := 3.0
@export var stuckCheckInterval := 0.35
@export var minProgressDistance := 5.0
@export var carryOffset := 20.0
@export var depotApproachDistance := 120.0
@export var minDepotClearance := 96.0
@export var tossDistanceThreshold := 22.0
@export var tossSpeed := 520.0
@export var taskCooldownSeconds := 0.6

enum RobotState { IDLE, MOVING_TO_SHAPE, CARRYING_TO_DEPOT, COOLDOWN }

const SHAPE_COLOR_SQUARE := Color(0.2, 0.45, 1.0, 1.0)
const SHAPE_COLOR_CIRCLE := Color(1.0, 0.25, 0.25, 1.0)
const SHAPE_COLOR_TRIANGLE := Color(0.2, 1.0, 0.35, 1.0)
const SHAPE_COLOR_IDLE := Color(1.0, 1.0, 1.0, 0.35)

var _state: RobotState = RobotState.IDLE
var _targetShape: RigidBody2D = null
var _targetDepot: Node2D = null
var _carriedShape: RigidBody2D = null
var _cooldownRemaining := 0.0
var _pursuitTime := 0.0
var _stuckCheckTime := 0.0
var _lastDistanceToTarget := INF
@onready var _shapeIndicator: Sprite2D = $ShapeIndicator

func _ready() -> void:
	add_to_group("helper_robots")
	gravity_scale = 0.0
	linear_damp = 5.5
	angular_damp = 8.0
	_updateShapeIndicatorColor()

func _physics_process(delta: float) -> void:
	if !Global.inGame:
		_resetTaskState()
		return

	match _state:
		RobotState.IDLE:
			_tryAcquireTask()
		RobotState.MOVING_TO_SHAPE:
			_updateMoveToShape(delta)
		RobotState.CARRYING_TO_DEPOT:
			_updateCarryToDepot()
		RobotState.COOLDOWN:
			_cooldownRemaining = max(_cooldownRemaining - delta, 0.0)
			if _cooldownRemaining <= 0.0:
				_state = RobotState.IDLE

	_clampSpeed()
	_updateShapeIndicatorColor()

func _updateShapeIndicatorColor() -> void:
	if _shapeIndicator == null:
		return

	var shapeType := -1
	if _carriedShape != null && is_instance_valid(_carriedShape) && "shape" in _carriedShape:
		shapeType = int(_carriedShape.shape)
	elif _targetShape != null && is_instance_valid(_targetShape) && "shape" in _targetShape:
		shapeType = int(_targetShape.shape)

	match shapeType:
		0:
			_shapeIndicator.modulate = SHAPE_COLOR_SQUARE
		1:
			_shapeIndicator.modulate = SHAPE_COLOR_CIRCLE
		2:
			_shapeIndicator.modulate = SHAPE_COLOR_TRIANGLE
		_:
			_shapeIndicator.modulate = SHAPE_COLOR_IDLE

func _tryAcquireTask() -> void:
	_targetShape = _pickBestShapeCandidate()
	if _targetShape == null:
		return

	_targetDepot = _pickDepotForShape(int(_targetShape.shape))
	if _targetDepot == null:
		_targetShape = null
		return

	_pursuitTime = 0.0
	_stuckCheckTime = 0.0
	_lastDistanceToTarget = global_position.distance_to(_targetShape.global_position)
	_state = RobotState.MOVING_TO_SHAPE

func _pickBestShapeCandidate() -> RigidBody2D:
	var bestShape: RigidBody2D = null
	var bestDistance := INF
	for candidate in get_tree().get_nodes_in_group("shapes"):
		if !_isValidShapeCandidate(candidate):
			continue

		var candidateBody := candidate as RigidBody2D
		var distanceToCandidate := global_position.distance_squared_to(candidateBody.global_position)
		if distanceToCandidate < bestDistance:
			bestDistance = distanceToCandidate
			bestShape = candidateBody

	return bestShape

func _pickDepotForShape(shapeType: int) -> Node2D:
	var bestDepot: Node2D = null
	var bestDistance := INF
	for depot in get_tree().get_nodes_in_group("depots"):
		if depot == null || !is_instance_valid(depot):
			continue
		if !("shape" in depot):
			continue
		if "isTitleScreenDepot" in depot && depot.isTitleScreenDepot:
			continue
		if int(depot.shape) != shapeType:
			continue
		if !(depot is Node2D):
			continue

		var depotNode := depot as Node2D
		var distanceToDepot := global_position.distance_squared_to(depotNode.global_position)
		if distanceToDepot < bestDistance:
			bestDistance = distanceToDepot
			bestDepot = depotNode

	return bestDepot

func _isValidShapeCandidate(candidate: Node) -> bool:
	if candidate == null || !is_instance_valid(candidate) || candidate.is_queued_for_deletion():
		return false
	if !(candidate is RigidBody2D):
		return false
	if !("shape" in candidate):
		return false
	if !_hasDepotForShape(int(candidate.shape)):
		return false
	if "isDragging" in candidate && candidate.isDragging:
		return false
	if "isTitleScreenShape" in candidate && candidate.isTitleScreenShape:
		return false
	if _isShapeAlreadyCorrectlyInDepot(candidate):
		return false
	if _isShapeReservedByAnotherBot(candidate):
		return false
	return true

func _hasDepotForShape(shapeType: int) -> bool:
	for depot in get_tree().get_nodes_in_group("depots"):
		if depot == null || !is_instance_valid(depot):
			continue
		if !("shape" in depot):
			continue
		if "isTitleScreenDepot" in depot && depot.isTitleScreenDepot:
			continue
		if int(depot.shape) == shapeType:
			return true
	return false

func isReservingShape(shapeBody: Node) -> bool:
	if shapeBody == null || !is_instance_valid(shapeBody):
		return false
	return (_targetShape != null && _targetShape == shapeBody) || (_carriedShape != null && _carriedShape == shapeBody)

func _isShapeReservedByAnotherBot(shapeBody: Node) -> bool:
	for bot in get_tree().get_nodes_in_group("helper_robots"):
		if bot == null || !is_instance_valid(bot) || bot == self:
			continue
		if bot.has_method("isReservingShape") && bot.isReservingShape(shapeBody):
			return true
	return false

func _isShapeAlreadyCorrectlyInDepot(shapeBody: Node) -> bool:
	for depot in get_tree().get_nodes_in_group("depots"):
		if depot == null || !is_instance_valid(depot):
			continue
		if !("shape" in depot):
			continue
		if "isTitleScreenDepot" in depot && depot.isTitleScreenDepot:
			continue
		if !depot.has_method("_getShapeBodiesInZone"):
			continue

		var shapesInZone: Array = depot._getShapeBodiesInZone()
		if !shapesInZone.has(shapeBody):
			continue

		if int(shapeBody.shape) == int(depot.shape):
			return true

	return false

func _updateMoveToShape(delta: float) -> void:
	if !_isValidShapeCandidate(_targetShape):
		_resetTaskState()
		return
	if _targetDepot == null || !is_instance_valid(_targetDepot):
		_resetTaskState()
		return

	var distanceToTarget := global_position.distance_to(_targetShape.global_position)
	_steerToward(_targetShape.global_position)

	if distanceToTarget <= pickupDistance:
		_pickupTargetShape()
		return

	if distanceToTarget <= grabAssistDistance:
		_targetShape.linear_velocity = _targetShape.linear_velocity.move_toward(Vector2.ZERO, 220.0 * delta)
		_targetShape.angular_velocity = move_toward(_targetShape.angular_velocity, 0.0, 10.0 * delta)
		_targetShape.global_position = _targetShape.global_position.move_toward(global_position, grabAssistPullSpeed * delta)
		distanceToTarget = global_position.distance_to(_targetShape.global_position)
		if distanceToTarget <= pickupDistance * 1.4:
			_pickupTargetShape()
			return

	_pursuitTime += delta
	_stuckCheckTime += delta
	if _stuckCheckTime >= stuckCheckInterval:
		var progressDistance := _lastDistanceToTarget - distanceToTarget
		if progressDistance < minProgressDistance:
			if distanceToTarget <= grabAssistDistance * 1.6:
				_pickupTargetShape()
				return
			_state = RobotState.IDLE
			_targetShape = null
			_targetDepot = null
			return
		_stuckCheckTime = 0.0
		_lastDistanceToTarget = distanceToTarget

	if _pursuitTime >= maxPursuitSeconds:
		if distanceToTarget <= grabAssistDistance * 1.8:
			_pickupTargetShape()
			return
		_state = RobotState.IDLE
		_targetShape = null
		_targetDepot = null

func _pickupTargetShape() -> void:
	if !_isValidShapeCandidate(_targetShape):
		_resetTaskState()
		return

	_carriedShape = _targetShape
	_targetShape = null
	_carriedShape.freeze = true
	_carriedShape.sleeping = true
	_carriedShape.linear_velocity = Vector2.ZERO
	_carriedShape.angular_velocity = 0.0
	_carriedShape.rotation = 0.0
	_setCarryCollisionException(true)
	if _shouldDoImmediateCloseRangeToss():
		var toDepotNow := _targetDepot.global_position - global_position
		var tossDirectionNow := toDepotNow.normalized() if toDepotNow.length_squared() > 0.0001 else Vector2.UP
		_tossCarriedShape(tossDirectionNow)
		return
	_state = RobotState.CARRYING_TO_DEPOT

func _shouldDoImmediateCloseRangeToss() -> bool:
	if _targetDepot == null || !is_instance_valid(_targetDepot):
		return false
	var depotDistance := global_position.distance_to(_targetDepot.global_position)
	return depotDistance <= minDepotClearance

func _updateCarryToDepot() -> void:
	if _carriedShape == null || !is_instance_valid(_carriedShape) || _carriedShape.is_queued_for_deletion():
		_resetTaskState()
		return
	if _isShapeBeingDragged(_carriedShape):
		_releaseCarriedShape()
		_targetDepot = null
		_state = RobotState.COOLDOWN
		_cooldownRemaining = taskCooldownSeconds
		return
	if _targetDepot == null || !is_instance_valid(_targetDepot):
		_releaseCarriedShape()
		_resetTaskState()
		return

	var toDepot := _targetDepot.global_position - global_position
	var distanceToDepot := toDepot.length()
	var toDepotDirection := toDepot.normalized() if toDepot.length_squared() > 0.0001 else Vector2.UP
	var approachTarget := _targetDepot.global_position - toDepotDirection * depotApproachDistance
	var carryDirection := toDepotDirection

	if distanceToDepot < minDepotClearance:
		var awayVector := global_position - _targetDepot.global_position
		var awayDirection := awayVector.normalized() if awayVector.length_squared() > 0.0001 else -toDepotDirection
		var safePosition := _targetDepot.global_position + awayDirection * minDepotClearance
		_steerToward(safePosition)
		carryDirection = awayDirection
	else:
		_steerToward(approachTarget)

	_carriedShape.global_position = global_position + carryDirection * carryOffset
	_carriedShape.rotation = 0.0

	var approachError := absf(distanceToDepot - depotApproachDistance)
	if distanceToDepot >= minDepotClearance && approachError <= tossDistanceThreshold:
		_tossCarriedShape(toDepotDirection)

func _tossCarriedShape(tossDirection: Vector2) -> void:
	if _carriedShape == null || !is_instance_valid(_carriedShape):
		_resetTaskState()
		return

	_setCarryCollisionException(false)
	_carriedShape.freeze = false
	_carriedShape.sleeping = false
	_carriedShape.linear_velocity = tossDirection * tossSpeed + linear_velocity * 0.2
	_carriedShape.angular_velocity = 0.0
	_carriedShape.rotation = 0.0
	_carriedShape = null
	_targetDepot = null
	_state = RobotState.COOLDOWN
	_cooldownRemaining = taskCooldownSeconds

func _releaseCarriedShape() -> void:
	if _carriedShape == null || !is_instance_valid(_carriedShape):
		return
	_setCarryCollisionException(false)
	_carriedShape.freeze = false
	_carriedShape.sleeping = false
	_carriedShape = null

func _setCarryCollisionException(enabled: bool) -> void:
	if _carriedShape == null || !is_instance_valid(_carriedShape):
		return
	if enabled:
		add_collision_exception_with(_carriedShape)
		_carriedShape.add_collision_exception_with(self)
	else:
		remove_collision_exception_with(_carriedShape)
		_carriedShape.remove_collision_exception_with(self)

func _isShapeBeingDragged(shapeBody: Node) -> bool:
	return shapeBody != null && is_instance_valid(shapeBody) && "isDragging" in shapeBody && shapeBody.isDragging

func _getSpeedScale() -> float:
	return clampf(Global.cleanerBotSpeedMultiplier, 0.55, 2.0)

func _steerToward(targetPosition: Vector2) -> void:
	var speedScale := _getSpeedScale()
	var toTarget := targetPosition - global_position
	if toTarget.length() <= arriveDistance:
		linear_velocity = linear_velocity.move_toward(Vector2.ZERO, steeringForce * speedScale)
		return

	var desiredVelocity := toTarget.normalized() * (moveSpeed * speedScale)
	var steering := (desiredVelocity - linear_velocity) * (steeringForce * speedScale)
	apply_central_force(steering)

func _clampSpeed() -> void:
	var effectiveMaxSpeed := maxSpeed * _getSpeedScale()
	if linear_velocity.length() > effectiveMaxSpeed:
		linear_velocity = linear_velocity.normalized() * effectiveMaxSpeed

func _resetTaskState() -> void:
	_releaseCarriedShape()
	_targetShape = null
	_targetDepot = null
	_state = RobotState.IDLE
	_cooldownRemaining = 0.0
	_pursuitTime = 0.0
	_stuckCheckTime = 0.0
	_lastDistanceToTarget = INF
