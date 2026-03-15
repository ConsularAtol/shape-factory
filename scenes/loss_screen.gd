extends Control

const RAINBOW_SPEED := 1.4
const FADE_IN_DURATION := 1
const PB_FADE_DELAY := 1.0
const PB_FADE_DURATION := 0.2

var _rainbow_active := false
var _rainbow_time := 0.0
var _fade_tween: Tween
var _pb_fade_tween: Tween

@onready var _pb_label: Label = $VBoxContainer/PB

func _ready() -> void:
    hide()
    set_process(false)
    Global.loss.connect(_on_loss)

func randomizeLossQuip() -> void:
    var quips := [
        "Damn. Yeah that's where I'm using my one swear.",
        "Yeah... you're fired.",
        "It goes in the square hole!",
        "The shareholders aren't gonna like this one.",
        "Erm, what the flip?",
        "Shapes and colors man.",
        "You can play with your eyes open, it's okay.",
        "So... about that raise?",
        "Did your mouse disconnect?",
        "I thought we had something special.",
        "I personally would blame that on the upgrade rng.",
        "You signed an NDA, right?",
        "I've never seen that one.",
        "I don't even know what to say about that.",
        "Don't put your fingers in the machinery.",
        "Where did we find this guy?",
        "I could do better. But I won't.",
        "I hope you learned something from this.",
        "Yeah that square was a little too blue it's ok.",
        "Well, at least you tried.",
        "You're not getting paid",
        "How's the children gonna learn their shapes now?",
        "Hope you didn't delete the Indeed app.",
        "We're killing you now.",
        "I guess you just don't like fun.",
        "Witty comment.",
        "...",
        "I'm raising your rent too. And your taxes.",
        "Hope you enjoy the walk of shame to your second job.",
        "Oh wait, we DO sell pentagons? Oh well.",
        "I was waiting for an excuse to fire you.",
        "Thank you for the opportunity of knowing you.",
        "I have to update the company newsletter with this news now.",
        "My PB is higher than yours btw. Or at least it would be if I did your job.",
        "I'm putting YOU down the depot now.",
        "Huh? Oh, you lost again? Cool...",
        "Go home. Alt+F4. Get out.",
        "You get NOTHING! You LOSE! GOOD DAY, SIR!"
    ]
    Dialogic.VAR.set("lossQuip", quips[randi() % quips.size()])

func _on_loss() -> void:
    await get_tree().create_timer(2).timeout
    var isNewPb: bool = Global.wave > Global.bestWave

    if _fade_tween != null && _fade_tween.is_running():
        _fade_tween.kill()

    modulate.a = 0.0
    show()
    _fade_tween = create_tween()
    _fade_tween.tween_property(self, "modulate:a", 1.0, FADE_IN_DURATION)

    if _pb_fade_tween != null && _pb_fade_tween.is_running():
        _pb_fade_tween.kill()
    _pb_label.modulate.a = 0.0
    $VBoxContainer/WaveCount.text = "Failed on Wave " + str(Global.wave)

    if isNewPb:
        _pb_label.text = "New Best!"
        _rainbow_active = true
        _rainbow_time = 0.0
        set_process(true)
        $PBSound.play()
    else:
        _rainbow_active = false
        set_process(false)
        _pb_label.text = "Personal Best: Wave " + str(Global.bestWave)
        _pb_label.add_theme_color_override("font_color", Color(1.0, 0.0, 1.0, 1.0))

    Global.updateBestWave(Global.wave)

    await get_tree().create_timer(PB_FADE_DELAY).timeout
    _pb_fade_tween = create_tween()
    _pb_fade_tween.tween_property(_pb_label, "modulate:a", 1.0, PB_FADE_DURATION)
    randomizeLossQuip()
    Dialogic.start("lossquip")

func _process(delta: float) -> void:
    if !_rainbow_active:
        return

    _rainbow_time += delta * RAINBOW_SPEED
    var rainbow_color := Color.from_hsv(fmod(_rainbow_time, 1.0), 0.9, 1.0)
    _pb_label.add_theme_color_override("font_color", rainbow_color)