extends Node2D

@export var shape_scene: PackedScene
var _active_shape: Node = null

func _ready() -> void:
    spawnShape()

func spawnShape() -> void:
    await get_tree().create_timer(1).timeout
    if shape_scene == null:
        return
    if _active_shape != null && is_instance_valid(_active_shape):
        return

    var shape_instance = shape_scene.instantiate()
    add_child(shape_instance)
    _active_shape = shape_instance
    shape_instance.tree_exited.connect(_onActiveShapeExited, CONNECT_ONE_SHOT)
    shape_instance.shape = randi() % 3
    shape_instance.isTitleScreenShape = true
    shape_instance.find_child("AnimationPlayer").play("TitleSpawn")
    if shape_instance is RigidBody2D:
        shape_instance.linear_velocity = Vector2(0, -1000)

func _onActiveShapeExited() -> void:
    _active_shape = null
    if !is_inside_tree():
        return
    await _waitForTitleDepotToClose()
    if !is_inside_tree():
        return
    spawnShape()

func _waitForTitleDepotToClose() -> void:
    var title_depot = _getTitleScreenDepot()
    if title_depot == null:
        return

    var animation_player = title_depot.get_node_or_null("AnimationPlayer")
    while is_inside_tree() && is_instance_valid(title_depot):
        var depot_is_animating: bool = "_is_animating" in title_depot && title_depot._is_animating
        var animation_is_playing: bool = animation_player is AnimationPlayer && animation_player.is_playing()

        if !depot_is_animating && !animation_is_playing:
            return

        if animation_player is AnimationPlayer && animation_player.is_playing():
            await animation_player.animation_finished
        else:
            await get_tree().process_frame

func _getTitleScreenDepot() -> Node:
    for depot in get_tree().get_nodes_in_group("depots"):
        if "isTitleScreenDepot" in depot && depot.isTitleScreenDepot:
            return depot
    return null