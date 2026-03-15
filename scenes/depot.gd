@tool
extends Node2D

enum Shape { SQUARE, CIRCLE, TRIANGLE }
const SHAPE_SCRIPT := preload("res://scenes/shape.gd")
const DEPOT_CLICK_HALF_EXTENTS := Vector2(56, 56)
var collectAnimationDuration := 0.8
var magnetRadius := 120.0
var magnetForce := 900.0
var _is_animating := false
var _matchingShapesInZone := {}

@export var isTitleScreenDepot := false

@export var shape: Shape = Shape.SQUARE:
    set(value):
        shape = value
        updateShape()
    get:
        return shape

func _shapeName(shape_value: int) -> String:
    match shape_value:
        Shape.SQUARE:
            return "SQUARE"
        Shape.CIRCLE:
            return "CIRCLE"
        Shape.TRIANGLE:
            return "TRIANGLE"
        _:
            return "UNKNOWN"

func _isShapeBody(body: Node) -> bool:
    return body != null && body.get_script() == SHAPE_SCRIPT

func _isMatchingShape(body: Node) -> bool:
    return _isShapeBody(body) && int(body.shape) == int(shape)

func _ready() -> void:
    if isTitleScreenDepot:
        shape = randi_range(0, 2) as Shape
    add_to_group("depots")
    updateShape()

func _input(event: InputEvent) -> void:
    if Engine.is_editor_hint() || !isTitleScreenDepot || _is_animating:
        return
    if !(event is InputEventMouseButton):
        return

    var mouse_event := event as InputEventMouseButton
    if mouse_event.button_index != MOUSE_BUTTON_LEFT || !mouse_event.pressed:
        return

    var local_mouse_position := to_local(get_global_mouse_position())
    var click_rect := Rect2(-DEPOT_CLICK_HALF_EXTENTS, DEPOT_CLICK_HALF_EXTENTS * 2.0)
    if !click_rect.has_point(local_mouse_position):
        return

    shape = ((int(shape) + 1) % Shape.size()) as Shape

func _physics_process(_delta: float) -> void:
    if Engine.is_editor_hint():
        return

    if Global.magnetDepotsUnlocked:
        _applyMagnetPull()

    var shouldTrackMatchingTouches := Global.shrinkingDepotsUnlocked || Global.stickyDepotsUnlocked
    if !shouldTrackMatchingTouches:
        _releaseAllMatchingTouches()
        return

    var current_matching_shapes := {}
    for shape_body in _getShapeBodiesInZone():
        if shape_body == null || !is_instance_valid(shape_body):
            continue
        if !_isMatchingShape(shape_body):
            continue
        current_matching_shapes[shape_body.get_instance_id()] = shape_body

    for shape_id in current_matching_shapes.keys():
        if _matchingShapesInZone.has(shape_id):
            continue
        var entered_shape = current_matching_shapes[shape_id]
        if entered_shape.has_method("beginCorrectDepotTouch"):
            entered_shape.beginCorrectDepotTouch()

    for shape_id in _matchingShapesInZone.keys():
        if current_matching_shapes.has(shape_id):
            continue
        var exited_shape = _matchingShapesInZone[shape_id]
        if is_instance_valid(exited_shape) && exited_shape.has_method("endCorrectDepotTouch"):
            exited_shape.endCorrectDepotTouch()

    _matchingShapesInZone = current_matching_shapes

func _applyMagnetPull() -> void:
    var radius_sq := magnetRadius * magnetRadius
    for candidate in get_tree().get_nodes_in_group("shapes"):
        if candidate == null || !is_instance_valid(candidate):
            continue
        if !_isMatchingShape(candidate):
            continue
        if !(candidate is RigidBody2D):
            continue

        var to_depot: Vector2 = global_position - candidate.global_position
        var dist_sq := to_depot.length_squared()
        if dist_sq <= 0.0001 || dist_sq > radius_sq:
            continue

        var distance := sqrt(dist_sq)
        var pull_ratio := 1.0 - (distance / magnetRadius)
        var force := to_depot.normalized() * (magnetForce * pull_ratio)
        candidate.apply_central_force(force)

func _releaseAllMatchingTouches() -> void:
    for shape_id in _matchingShapesInZone.keys():
        var shape_body = _matchingShapesInZone[shape_id]
        if is_instance_valid(shape_body) && shape_body.has_method("endCorrectDepotTouch"):
            shape_body.endCorrectDepotTouch()
    _matchingShapesInZone.clear()

func _exit_tree() -> void:
    _releaseAllMatchingTouches()

func _getShapeBodiesInZone() -> Array:
    var collection_zone: Area2D = $ShapeCollectionZone
    var overlapping_bodies = collection_zone.get_overlapping_bodies()
    return overlapping_bodies.filter(func(body): return _isShapeBody(body))

func _hasRemainingShapeAvailable() -> bool:
    var all_shapes = get_tree().get_nodes_in_group("shapes")
    for candidate in all_shapes:
        if !_isShapeBody(candidate):
            continue
        if candidate.is_queued_for_deletion():
            continue
        if int(candidate.shape) == int(shape):
            return true
    return false

func isReadyToOpen() -> bool:
    var shapes_in_zone = _getShapeBodiesInZone()
    if shapes_in_zone.is_empty():
        return !_hasRemainingShapeAvailable()
    return shapes_in_zone.all(func(body): return _isMatchingShape(body))

func haltShapesInZone() -> void:
    var shapes_in_zone = _getShapeBodiesInZone()
    for shape_body in shapes_in_zone:
        if shape_body is RigidBody2D:
            shape_body.linear_velocity = Vector2.ZERO
            shape_body.angular_velocity = 0.0
            shape_body.sleeping = true

func openDepot() -> void:
    if _is_animating:
        return
    _is_animating = true
    if !isTitleScreenDepot:
        Global.beginDepotAnimation()
    $AnimationPlayer.play("Open")

func _collectShape(collected_shape: RigidBody2D) -> void:
    collected_shape.freeze = true
    collected_shape.sleeping = true
    collected_shape.linear_velocity = Vector2.ZERO
    collected_shape.angular_velocity = 0.0

    var tween = create_tween()
    tween.set_parallel(true)
    tween.tween_property(collected_shape, "scale", Vector2.ZERO, collectAnimationDuration).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
    tween.tween_property(collected_shape, "global_position", global_position, collectAnimationDuration).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
    tween.finished.connect(func():
        if is_instance_valid(collected_shape):
            collected_shape.queue_free()
    )

func updateShape() -> void:
    match shape:
        Shape.SQUARE:
            $Base.texture = load("res://assets/sprite/depots/square.png")
            $DoorLeft.texture = load("res://assets/sprite/depots/squaredoorleft.png")
            $DoorRight.texture = load("res://assets/sprite/depots/squaredoorright.png")
        Shape.CIRCLE:
            $Base.texture = load("res://assets/sprite/depots/circle.png")
            $DoorLeft.texture = load("res://assets/sprite/depots/circledoorleft.png")
            $DoorRight.texture = load("res://assets/sprite/depots/circledoorright.png")
        Shape.TRIANGLE:
            $Base.texture = load("res://assets/sprite/depots/triangle.png")
            $DoorLeft.texture = load("res://assets/sprite/depots/triangledoorleft.png")
            $DoorRight.texture = load("res://assets/sprite/depots/triangledoorright.png")

func _on_animation_player_animation_finished(anim_name: StringName) -> void:
    if anim_name == "Open":
        var shapes_in_zone = _getShapeBodiesInZone()
        for collected_shape in shapes_in_zone:
            if _isMatchingShape(collected_shape):
                _collectShape(collected_shape)
        await get_tree().create_timer(1).timeout
        $AnimationPlayer.play("Close")
    elif anim_name == "Close":
        if _is_animating:
            _is_animating = false
            if !isTitleScreenDepot:
                Global.endDepotAnimation()