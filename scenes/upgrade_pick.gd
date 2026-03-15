extends Control

const UPGRADE_POOL := [
    {"name": "+2 Seconds", "rarity_weight": 15.0, "is_beneficial": true, "is_stackable": true, "description": "Permanently adds 2 seconds to the round timer."},
    {"name": "+5 Seconds", "rarity_weight": 5.0, "is_beneficial": true, "is_stackable": true, "description": "Permanently adds 5 seconds to the round timer."},
    {"name": "+1 Max Pickup", "rarity_weight": 12.0, "is_beneficial": true, "is_stackable": true, "description": "Allows you to drag one additional shape at a time. All shapes must match."},
    {"name": "+1 Pickup Range", "rarity_weight": 12.0, "is_beneficial": true, "is_stackable": true, "description": "Permanently increases the radius at which you can pick up shapes by 1 unit."},
    {"name": "Skip Wave", "rarity_weight": 4.0, "is_beneficial": true, "is_stackable": true, "description": "Skip the current wave. Does not grant the next wave's upgrade."},
    {"name": "-0.1 Friction", "rarity_weight": 10.0, "is_beneficial": true, "is_stackable": true, "description": "Shapes slide more, making them easier to reposition quickly."},
    {"name": "Ghost Shapes", "rarity_weight": 0.6, "is_beneficial": true, "is_stackable": false, "description": "Shapes no longer collide with each other."},
    {"name": "Shape Infection", "rarity_weight": 1.5, "is_beneficial": false, "is_stackable": false, "description": "Shapes transform into the shape type they collide with."},
    {"name": "Shape Clumping", "rarity_weight": 1.0, "is_beneficial": true, "is_stackable": false, "description": "Shapes of the same type pull toward each other."},
    {"name": "Sticky Depots", "rarity_weight": 1.0, "is_beneficial": true, "is_stackable": false, "description": "Shapes gain massive friction while over their matching depot."},
    {"name": "Magnet Depots", "rarity_weight": 1.0, "is_beneficial": true, "is_stackable": false, "description": "Depots pull in nearby matching shapes."},
    {"name": "Cleaner Bot", "rarity_weight": 0.8, "is_beneficial": true, "is_stackable": false, "description": "Spawns a tiny helper bot that grabs shapes and tosses them near matching depots."},
    {"name": "Double Cleaner Bot", "rarity_weight": 0.7, "is_beneficial": true, "is_stackable": false, "description": "Spawns a second cleaner bot."},
    {"name": "Faster Cleaner Bot", "rarity_weight": 8.0, "is_beneficial": true, "is_stackable": true, "description": "Increases cleaner bot movement speed."},
    {"name": "Slower Cleaner Bot", "rarity_weight": 8.0, "is_beneficial": false, "is_stackable": true, "description": "Decreases cleaner bot movement speed."},
    {"name": "Bullet Time", "rarity_weight": 0.7, "is_beneficial": true, "is_stackable": false, "description": "Slows down time while the round timer is at 10 seconds or less."},
    {"name": "Faster Shape Spawn", "rarity_weight": 8.0, "is_beneficial": true, "is_stackable": true, "description": "Speeds up the S.P.A.M."},
    {"name": "Increased Pentagon Chance", "rarity_weight": 5.5, "is_beneficial": false, "is_stackable": true, "description": "Increases the chance that each spawned shape is a pentagon."},
    {"name": "Depot Shuffle", "rarity_weight": 13.0, "is_beneficial": false, "is_stackable": true, "description": "Shuffles depot shape assignments and locks that layout until you pick this again."},
    {"name": "Shrinking Depots", "rarity_weight": 1.0, "is_beneficial": true, "is_stackable": false, "description": "Matching shapes shrink while touching their correct depot."},
    {"name": "-2 Seconds", "rarity_weight": 14.0, "is_beneficial": false, "is_stackable": true, "description": "Permanently removes 2 seconds from the round timer."},
    {"name": "+0.1 Friction", "rarity_weight": 10.0, "is_beneficial": false, "is_stackable": true, "description": "Shapes lose momentum faster and feel stickier."},
    {"name": "-2 Waves", "rarity_weight": 2.5, "is_beneficial": true, "is_stackable": true, "description": "Go back 2 waves, essentially allowing you to gain an extra upgrade."},
    {"name": "Slower Shape Spawn", "rarity_weight": 15.0, "is_beneficial": false, "is_stackable": true, "description": "Slows down the S.P.A.M."},
    {"name": "Decreased Pentagon Chance", "rarity_weight": 10.0, "is_beneficial": true, "is_stackable": true, "description": "Reduces the chance that each spawned shape is a pentagon."},
    {"name": "PTO", "rarity_weight": 0.5, "is_beneficial": true, "is_stackable": false, "description": "Protects you from being fired once. Is consumed upon use."},
]

const BENEFICIAL_COLOR := Color(0.2, 1.0, 0.2, 1.0)
const NEGATIVE_COLOR := Color(1.0, 0.25, 0.25, 1.0)
const RAINBOW_SPEED := 1.25
const BENEFICIAL_WEIGHT_DECAY_START_WAVE := 10
const BENEFICIAL_WEIGHT_DECAY_PER_WAVE := 0.97
const BENEFICIAL_WEIGHT_MIN_SCALE := 0.4

var _rainbow_buttons: Array = []
var _rainbow_time := 0.0
@onready var _description_panel: Control = find_child("Description", true, false) as Control
@onready var _description_label: Label = _description_panel.find_child("Label", true, false) as Label if _description_panel != null else null

func _ready() -> void:
    Global.upgrades.connect(promptUpgrade)
    var upgradeButtons = find_child("Upgrades").get_children()
    for button in upgradeButtons:
        if !(button is Button):
            continue
        var entered_callable := Callable(self, "_onUpgradeButtonMouseEntered").bind(button)
        var exited_callable := Callable(self, "_onUpgradeButtonMouseExited").bind(button)
        if !button.is_connected("mouse_entered", entered_callable):
            button.connect("mouse_entered", entered_callable)
        if !button.is_connected("mouse_exited", exited_callable):
            button.connect("mouse_exited", exited_callable)

    _hide_description()
    set_process(false)
    hide()

func _is_upgrade_available(upgrade_name: String) -> bool:
    if upgrade_name == "Double Cleaner Bot" && !Global.helperRobotUnlocked:
        return false
    if (upgrade_name == "Faster Cleaner Bot" || upgrade_name == "Slower Cleaner Bot") && !Global.helperRobotUnlocked:
        return false
    if upgrade_name == "Ghost Shapes" && Global.shapeInfectionUnlocked:
        return false
    if upgrade_name == "Shape Infection" && Global.noShapeCollisionsUnlocked:
        return false
    if !_is_upgrade_stackable(upgrade_name) && _is_non_stackable_already_unlocked(upgrade_name):
        return false
    return true

func _getUpgradeConfig(upgrade_name: String) -> Dictionary:
    for upgrade in UPGRADE_POOL:
        if str(upgrade.get("name", "")) == upgrade_name:
            return upgrade
    return {}

func _is_non_stackable_already_unlocked(upgrade_name: String) -> bool:
    if upgrade_name == "Shrinking Depots":
        return Global.shrinkingDepotsUnlocked
    if upgrade_name == "Ghost Shapes":
        return Global.noShapeCollisionsUnlocked
    if upgrade_name == "Shape Infection":
        return Global.shapeInfectionUnlocked
    if upgrade_name == "Shape Clumping":
        return Global.sameTypeAttractionUnlocked
    if upgrade_name == "Sticky Depots":
        return Global.stickyDepotsUnlocked
    if upgrade_name == "Magnet Depots":
        return Global.magnetDepotsUnlocked
    if upgrade_name == "Cleaner Bot":
        return Global.helperRobotUnlocked
    if upgrade_name == "Double Cleaner Bot":
        return Global.doubleCleanerBotUnlocked
    if upgrade_name == "Bullet Time":
        return Global.lowTimeSlowMoUnlocked
    if upgrade_name == "PTO":
        return Global.deathShieldActive
    return false

func _get_available_upgrade_pool() -> Array:
    var available_pool: Array = []
    for upgrade in UPGRADE_POOL:
        var upgrade_name := str(upgrade.get("name", ""))
        if _is_upgrade_available(upgrade_name):
            available_pool.append(upgrade)
    return available_pool

func _is_upgrade_beneficial(upgrade_name: String) -> bool:
    var upgradeConfig := _getUpgradeConfig(upgrade_name)
    if !upgradeConfig.is_empty():
        return bool(upgradeConfig.get("is_beneficial", true))
    return true

func _is_upgrade_stackable(upgrade_name: String) -> bool:
    var upgradeConfig := _getUpgradeConfig(upgrade_name)
    if !upgradeConfig.is_empty():
        return bool(upgradeConfig.get("is_stackable", true))
    return true

func _get_weighted_upgrade_value(upgrade: Dictionary) -> float:
    var baseWeight: float = max(float(upgrade.get("rarity_weight", 0.0)), 0.0)
    if baseWeight <= 0.0:
        return 0.0

    if !bool(upgrade.get("is_beneficial", true)):
        return baseWeight

    var decayWaveIndex := int(max(Global.wave - BENEFICIAL_WEIGHT_DECAY_START_WAVE, 0))
    var beneficialScale: float = max(pow(BENEFICIAL_WEIGHT_DECAY_PER_WAVE, decayWaveIndex), BENEFICIAL_WEIGHT_MIN_SCALE)
    return baseWeight * beneficialScale

func _apply_upgrade_button_color(button: Button, is_beneficial: bool) -> void:
    var text_color := BENEFICIAL_COLOR if is_beneficial else NEGATIVE_COLOR
    _set_button_text_color(button, text_color)

func _set_button_text_color(button: Button, text_color: Color) -> void:
    button.add_theme_color_override("font_color", text_color)
    button.add_theme_color_override("font_hover_color", text_color)
    button.add_theme_color_override("font_hover_pressed_color", text_color)
    button.add_theme_color_override("font_pressed_color", text_color)
    button.add_theme_color_override("font_focus_color", text_color)

func _get_upgrade_description(upgrade_name: String) -> String:
    var upgradeConfig := _getUpgradeConfig(upgrade_name)
    return str(upgradeConfig.get("description", ""))

func _show_description_for_upgrade(upgrade_name: String) -> void:
    if _description_panel == null || _description_label == null:
        return
    _description_label.text = _get_upgrade_description(upgrade_name)
    _description_panel.show()

func _hide_description() -> void:
    if _description_panel == null:
        return
    _description_panel.hide()

func _onUpgradeButtonMouseEntered(button: Button) -> void:
    if button == null:
        return
    var upgrade_name := str(button.get_meta("upgrade_name", ""))
    if upgrade_name == "":
        _hide_description()
        return
    _show_description_for_upgrade(upgrade_name)

func _onUpgradeButtonMouseExited(_button: Button) -> void:
    _hide_description()

func _process(delta: float) -> void:
    if _rainbow_buttons.is_empty():
        return

    _rainbow_time += delta * RAINBOW_SPEED
    for i in range(_rainbow_buttons.size()):
        var button: Button = _rainbow_buttons[i]
        if button == null || !is_instance_valid(button):
            continue
        var hue := fmod(_rainbow_time + float(i) * 0.17, 1.0)
        var rainbow_color := Color.from_hsv(hue, 0.9, 1.0)
        _set_button_text_color(button, rainbow_color)

func pickRandomUpgrade() -> String:
    var available_pool := _get_available_upgrade_pool()
    if available_pool.is_empty():
        return ""

    var total_weight := 0.0
    for upgrade in available_pool:
        total_weight += _get_weighted_upgrade_value(upgrade)

    if total_weight <= 0.0:
        return str(available_pool[randi() % available_pool.size()].get("name", ""))

    var roll := randf() * total_weight
    var cumulative := 0.0
    for upgrade in available_pool:
        cumulative += _get_weighted_upgrade_value(upgrade)
        if roll <= cumulative:
            return str(upgrade.get("name", ""))

    return str(available_pool.back().get("name", ""))

func _pick_unique_upgrades(count: int) -> Array:
    var chosen_names: Array = []
    var pool := _get_available_upgrade_pool()
    var target_count: int = min(count, pool.size())

    while chosen_names.size() < target_count && !pool.is_empty():
        var total_weight := 0.0
        for upgrade in pool:
            total_weight += _get_weighted_upgrade_value(upgrade)

        var picked_index := 0
        if total_weight > 0.0:
            var roll := randf() * total_weight
            var cumulative := 0.0
            for i in range(pool.size()):
                cumulative += _get_weighted_upgrade_value(pool[i])
                if roll <= cumulative:
                    picked_index = i
                    break
        else:
            picked_index = randi() % pool.size()

        chosen_names.append(str(pool[picked_index].get("name", "")))
        pool.remove_at(picked_index)

    return chosen_names

func upgradePicked(upgrade_name: String) -> void:
    if Global.inTutorial:
        return
    match upgrade_name:
        "+2 Seconds":
            Global.timeBonus += 2
        "+5 Seconds":
            Global.timeBonus += 5
        "-2 Seconds":
            Global.timeBonus -= 2
        "+1 Max Pickup":
            Global.maxPickupCount += 1
        "+1 Pickup Range":
            Global.pickupRangeBonus += 1.0
        "Skip Wave":
            Global.wave += 1
        "-2 Waves":
            Global.wave -= 2
        "-0.1 Friction":
            Global.shapeFriction = clampf(Global.shapeFriction - 0.1, 0.0, 1.0)
            Global.refreshShapeModifiers()
        "Ghost Shapes":
            Global.noShapeCollisionsUnlocked = true
            Global.applyNoShapeCollisions()
        "Shape Infection":
            Global.shapeInfectionUnlocked = true
        "Shape Clumping":
            Global.sameTypeAttractionUnlocked = true
        "Sticky Depots":
            Global.stickyDepotsUnlocked = true
            Global.refreshShapeModifiers()
        "Magnet Depots":
            Global.magnetDepotsUnlocked = true
        "Cleaner Bot":
            Global.helperRobotUnlocked = true
        "Double Cleaner Bot":
            Global.doubleCleanerBotUnlocked = true
        "Faster Cleaner Bot":
            Global.cleanerBotSpeedMultiplier = clampf(Global.cleanerBotSpeedMultiplier * 1.12, 0.55, 2.0)
        "Slower Cleaner Bot":
            Global.cleanerBotSpeedMultiplier = clampf(Global.cleanerBotSpeedMultiplier * 0.9, 0.55, 2.0)
        "Bullet Time":
            Global.lowTimeSlowMoUnlocked = true
        "+0.1 Friction":
            Global.shapeFriction = clampf(Global.shapeFriction + 0.1, 0.0, 1.0)
            Global.refreshShapeModifiers()
        "Faster Shape Spawn":
            Global.shapeSpawnIntervalMultiplier = clampf(Global.shapeSpawnIntervalMultiplier * 0.85, 0.35, 3.0)
        "Increased Pentagon Chance":
            Global.pentagonSpawnChanceMultiplier = clampf(Global.pentagonSpawnChanceMultiplier * 1.1, 0.1, 3.0)
        "Depot Shuffle":
            Global.rerollDepotShuffle()
        "Slower Shape Spawn":
            Global.shapeSpawnIntervalMultiplier = clampf(Global.shapeSpawnIntervalMultiplier * 1.15, 0.35, 3.0)
        "Decreased Pentagon Chance":
            Global.pentagonSpawnChanceMultiplier = clampf(Global.pentagonSpawnChanceMultiplier * 0.9, 0.1, 3.0)
        "Shrinking Depots":
            Global.shrinkingDepotsUnlocked = true
        "PTO":
            Global.deathShieldActive = true
    $UpgradeSound.play()

    _rainbow_buttons.clear()
    _hide_description()
    set_process(false)
    hide()
    Global.nextWave.emit()

func promptUpgrade() -> void:
    var upgradeButtons := find_child("Upgrades").get_children()
    var unique_choices := _pick_unique_upgrades(upgradeButtons.size())
    _rainbow_buttons.clear()
    _rainbow_time = 0.0

    for i in range(upgradeButtons.size()):
        var button = upgradeButtons[i]
        var upgrade_name: String = unique_choices[i] if i < unique_choices.size() else ""
        button.text = upgrade_name
        button.set_meta("upgrade_name", upgrade_name)
        if !_is_upgrade_stackable(upgrade_name):
            _rainbow_buttons.append(button)
            _set_button_text_color(button, Color.from_hsv(float(i) * 0.17, 0.9, 1.0))
        else:
            var is_beneficial := _is_upgrade_beneficial(upgrade_name)
            _apply_upgrade_button_color(button, is_beneficial)
        if button.is_connected("pressed", Callable(self, "upgradePicked")):
            button.disconnect("pressed", Callable(self, "upgradePicked"))
        if upgrade_name != "":
            button.connect("pressed", Callable(self, "upgradePicked").bind(upgrade_name))
    _hide_description()
    set_process(!_rainbow_buttons.is_empty())
    show()
