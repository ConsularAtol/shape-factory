@tool
extends RigidBody2D

enum Shape { SQUARE, CIRCLE, TRIANGLE, PENTAGON }
var isDragging := false
var dragOffset := Vector2.ZERO
var dragTargetPosition := Vector2.ZERO

var drag_follow_strength := 30.0
var drag_max_speed := 1800.0
var release_max_speed := 1600.0
var pickup_padding := 6.0

var _correctDepotTouchCount := 0
var _titleStopFrames := 0
var _titleStopHandled := false
var _infectionCooldownRemaining := 0.0
var _isFadingAway := false

const TITLE_STOP_SPEED_THRESHOLD := 8.0
const TITLE_STOP_REQUIRED_FRAMES := 5
const INFECTION_COOLDOWN_SECONDS := 0.08
const SAME_TYPE_ATTRACTION_RADIUS := 150.0
const SAME_TYPE_ATTRACTION_FORCE := 420.0
const STICKY_DEPOT_LINEAR_DAMP := 22.0
const STICKY_DEPOT_ANGULAR_DAMP := 17.0
const STICKY_DEPOT_BRAKE_FORCE := 1300.0
const STICKY_DEPOT_STOP_SPEED := 6.0
const STICKY_DEPOT_STOP_ANGULAR_SPEED := 1.0

@export var isTitleScreenShape := false

@export var shape: Shape = Shape.SQUARE:
    set(value):
        if shape == value:
            return
        shape = value
        updateShape()
        Global.markShapeSpatialCacheDirty()
    get:
        return shape

func _ready() -> void:
    add_to_group("shapes")
    $AnimationPlayer.play("Spawn")
    continuous_cd = CCD_MODE_CAST_SHAPE
    contact_monitor = true
    max_contacts_reported = 8
    if !is_connected("body_entered", Callable(self, "_on_body_entered")):
        body_entered.connect(_on_body_entered)
    applyGlobalModifiers()
    if Global.noShapeCollisionsUnlocked:
        Global.applyNoShapeCollisionsFor(self)
    Global.markShapeSpatialCacheDirty()

func _on_body_entered(body: Node) -> void:
    if !Global.shapeInfectionUnlocked:
        return
    if _infectionCooldownRemaining > 0.0:
        return
    if body == null || !is_instance_valid(body):
        return
    if !(body is RigidBody2D):
        return
    if !("shape" in body):
        return

    var incomingShape := int(body.shape)
    if incomingShape == int(shape):
        return

    shape = incomingShape as Shape
    _infectionCooldownRemaining = INFECTION_COOLDOWN_SECONDS

func applyGlobalModifiers() -> void:
    if physics_material_override == null:
        physics_material_override = PhysicsMaterial.new()
    var friction_value := clampf(Global.shapeFriction, 0.0, 1.0)
    var stickyDepotActive := Global.stickyDepotsUnlocked && _correctDepotTouchCount > 0
    if stickyDepotActive:
        friction_value = 1.0
    physics_material_override.friction = friction_value
    if stickyDepotActive:
        linear_damp = STICKY_DEPOT_LINEAR_DAMP
        angular_damp = STICKY_DEPOT_ANGULAR_DAMP
    else:
        linear_damp = lerpf(1.5, 12.0, friction_value)
        angular_damp = lerpf(1.5, 10.0, friction_value)

func _updateShrinkState() -> void:
    var shrink_multiplier := 1.0
    if Global.shrinkingDepotsUnlocked && _correctDepotTouchCount > 0:
        shrink_multiplier = max(Global.shrinkingDepotScale, 0.1)

    $Sprite2D.scale = Vector2.ONE * shrink_multiplier
    $CollisionShape2D.scale = Vector2.ONE * shrink_multiplier

func beginCorrectDepotTouch() -> void:
    _correctDepotTouchCount += 1
    _updateShrinkState()
    applyGlobalModifiers()

func endCorrectDepotTouch() -> void:
    _correctDepotTouchCount = max(_correctDepotTouchCount - 1, 0)
    _updateShrinkState()
    applyGlobalModifiers()

func updateShape() -> void:
    match shape:
        Shape.SQUARE:
            $Sprite2D.texture = load("res://assets/sprite/shapes/square.png")
        Shape.CIRCLE:
            $Sprite2D.texture = load("res://assets/sprite/shapes/circle.png")
        Shape.TRIANGLE:
            $Sprite2D.texture = load("res://assets/sprite/shapes/triangle.png")
        Shape.PENTAGON:
            $Sprite2D.texture = load("res://assets/sprite/shapes/pentagon.png")

func canPickAtWorldPosition(world_position: Vector2, pickup_padding_value: float = -1.0) -> bool:
    var effective_padding: float = pickup_padding + Global.pickupRangeBonus
    if pickup_padding_value >= 0.0:
        effective_padding = pickup_padding_value

    var local_mouse_position = to_local(world_position)
    var pickup_rect = $Sprite2D.get_rect().grow(effective_padding)
    return pickup_rect.has_point(local_mouse_position)

func _getDragSpeedScale() -> float:
    return clampf(Engine.time_scale, 0.1, 1.0)

func _applySameTypeAttraction() -> void:
    if !Global.sameTypeAttractionUnlocked:
        return

    var attractionRadiusSq := SAME_TYPE_ATTRACTION_RADIUS * SAME_TYPE_ATTRACTION_RADIUS
    for candidate in Global.getNearbyShapesOfType(int(shape), global_position, SAME_TYPE_ATTRACTION_RADIUS):
        if candidate == self || candidate == null || !is_instance_valid(candidate):
            continue
        if candidate.is_queued_for_deletion():
            continue
        if !(candidate is RigidBody2D):
            continue
        if !("shape" in candidate):
            continue
        if int(candidate.shape) != int(shape):
            continue

        var toCandidate: Vector2 = candidate.global_position - global_position
        var distanceSq := toCandidate.length_squared()
        if distanceSq <= 0.0001 || distanceSq > attractionRadiusSq:
            continue

        var distance := sqrt(distanceSq)
        var pullRatio := 1.0 - (distance / SAME_TYPE_ATTRACTION_RADIUS)
        var attractionForce := (toCandidate / distance) * (SAME_TYPE_ATTRACTION_FORCE * pullRatio)
        apply_central_force(attractionForce)

func beginDragFromScoop(mouse_world_position: Vector2) -> void:
    if isDragging:
        return
    isDragging = true
    sleeping = false
    linear_velocity = Vector2.ZERO
    angular_velocity = 0.0
    dragOffset = global_position - mouse_world_position
    dragTargetPosition = mouse_world_position + dragOffset

func _tryScoopNearbyShapes(mouse_world_position: Vector2) -> void:
    if Global.maxPickupCount <= 1:
        return

    var effective_padding: float = pickup_padding + Global.pickupRangeBonus
    for candidate in get_tree().get_nodes_in_group("shapes"):
        if candidate == self || candidate == null || !is_instance_valid(candidate) || candidate.is_queued_for_deletion():
            continue
        if !("shape" in candidate):
            continue
        if int(candidate.shape) != int(shape):
            continue
        if "isDragging" in candidate && candidate.isDragging:
            continue
        if !candidate.has_method("canPickAtWorldPosition"):
            continue
        if !candidate.canPickAtWorldPosition(mouse_world_position, effective_padding):
            continue
        if !Global.tryBeginShapeDrag(candidate):
            continue
        if candidate.has_method("beginDragFromScoop"):
            candidate.beginDragFromScoop(mouse_world_position)

func _input(event: InputEvent) -> void:
    if event is InputEventMouseButton && event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed:
            if Global.isDragLocked():
                isDragging = false
                return
            var mouse_world_position = get_global_mouse_position()
            var effective_padding: float = pickup_padding + Global.pickupRangeBonus
            if !canPickAtWorldPosition(mouse_world_position, effective_padding):
                return
            if Global.maxPickupCount <= 1 && !Global.shouldShapeClaimClick(self, mouse_world_position, effective_padding):
                return
            if !Global.tryBeginShapeDrag(self):
                isDragging = false
                return
            isDragging = true
            sleeping = false
            linear_velocity = Vector2.ZERO
            angular_velocity = 0.0
            dragOffset = global_position - mouse_world_position
            dragTargetPosition = mouse_world_position + dragOffset
        else:
            if isDragging:
                var scaled_release_max_speed: float = release_max_speed * _getDragSpeedScale()
                if linear_velocity.length() > scaled_release_max_speed:
                    linear_velocity = linear_velocity.normalized() * scaled_release_max_speed
                angular_velocity = 0.0
            isDragging = false
            Global.endShapeDrag(self)

func _physics_process(delta: float) -> void:
    if _infectionCooldownRemaining > 0.0:
        _infectionCooldownRemaining = max(_infectionCooldownRemaining - delta, 0.0)

    _applySameTypeAttraction()

    if Global.isDragLocked() && isDragging:
        isDragging = false
        Global.endShapeDrag(self)

    if isDragging:
        var drag_speed_scale: float = _getDragSpeedScale()
        var scaled_drag_follow_strength: float = drag_follow_strength * drag_speed_scale
        var scaled_drag_max_speed: float = drag_max_speed * drag_speed_scale
        dragTargetPosition = get_global_mouse_position() + dragOffset
        _tryScoopNearbyShapes(dragTargetPosition - dragOffset)
        var to_target = dragTargetPosition - global_position
        if to_target.length() < 1.0:
            linear_velocity = Vector2.ZERO
        else:
            linear_velocity = to_target * scaled_drag_follow_strength
            if linear_velocity.length() > scaled_drag_max_speed:
                linear_velocity = linear_velocity.normalized() * scaled_drag_max_speed
        angular_velocity = 0.0

    var stickyDepotActive := Global.stickyDepotsUnlocked && _correctDepotTouchCount > 0
    if stickyDepotActive && !isDragging:
        linear_velocity = linear_velocity.move_toward(Vector2.ZERO, STICKY_DEPOT_BRAKE_FORCE * delta)
        angular_velocity = move_toward(angular_velocity, 0.0, STICKY_DEPOT_BRAKE_FORCE * 0.03 * delta)
        if linear_velocity.length() <= STICKY_DEPOT_STOP_SPEED:
            linear_velocity = Vector2.ZERO
        if absf(angular_velocity) <= STICKY_DEPOT_STOP_ANGULAR_SPEED:
            angular_velocity = 0.0

    if _correctDepotTouchCount > 0 && !Global.shrinkingDepotsUnlocked && !Global.stickyDepotsUnlocked:
        _correctDepotTouchCount = 0
        _updateShrinkState()

    _handleTitleScreenStopBehavior()

func _handleTitleScreenStopBehavior() -> void:
    if !isTitleScreenShape || _titleStopHandled:
        return
    if isDragging:
        _titleStopFrames = 0
        return

    if linear_velocity.length() <= TITLE_STOP_SPEED_THRESHOLD:
        _titleStopFrames += 1
    else:
        _titleStopFrames = 0

    if _titleStopFrames < TITLE_STOP_REQUIRED_FRAMES:
        return

    _titleStopHandled = true
    var title_depots = get_tree().get_nodes_in_group("depots").filter(func(depot): return "isTitleScreenDepot" in depot && depot.isTitleScreenDepot)
    if title_depots.is_empty():
        queue_free()
        return

    for depot in title_depots:
        if !("shape" in depot):
            continue
        if int(depot.shape) == int(shape):
            if depot.has_method("openDepot"):
                depot.openDepot()
            return

    _handleIncorrectTitleShape(title_depots)

func _handleIncorrectTitleShape(_title_depots: Array) -> void:
    var current_scene = get_tree().current_scene
    if current_scene != null:
        var incorrect_shape_player = current_scene.get_node_or_null("LoudBuzzerIdk")
        if incorrect_shape_player is AudioStreamPlayer2D:
            incorrect_shape_player.play()

    Global.loss.emit()
    if Global.has_method("_flickerShapeVisibility"):
        await Global._flickerShapeVisibility(self)

    if is_instance_valid(self) && !is_queued_for_deletion():
        queue_free()

func fadeAwayAndDespawn() -> void:
    if _isFadingAway || is_queued_for_deletion():
        return

    _isFadingAway = true
    freeze = true
    sleeping = true
    linear_velocity = Vector2.ZERO
    angular_velocity = 0.0
    $AnimationPlayer.play("Fade Away")

func _exit_tree() -> void:
    Global.endShapeDrag(self)
    Global.markShapeSpatialCacheDirty()

func _on_animation_player_animation_finished(anim_name: StringName) -> void:
    if anim_name == "Fade Away":
        queue_free()
