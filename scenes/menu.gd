extends Node2D

func _ready() -> void:
	find_child("MenuMusic").play()
	if Global.bestWave > 1:
		$CanvasLayer/PB.text = "PB: Wave " + str(Global.bestWave)
	else:
		$CanvasLayer/PB.hide()
	if OS.get_name() == "Web":
		$CanvasLayer/HBoxContainer/QuitButton.hide()
		_align_pb_to_play_button.call_deferred()
	$CanvasLayer/BlackScreen.show()
	$CanvasLayer/AnimationPlayer.play("Fade In")

func _align_pb_to_play_button() -> void:
	var pb: Label = $CanvasLayer/PB
	var play_button: Button = $CanvasLayer/HBoxContainer/PlayButton
	var button_center_y: float = play_button.global_position.y + play_button.size.y * 0.5
	pb.global_position.y = button_center_y - pb.size.y * 0.5

func _on_quit_button_pressed() -> void:
	get_tree().quit()

func _on_play_button_pressed() -> void:
	$CanvasLayer/AnimationPlayer.play("Fade Out")
	await $CanvasLayer/AnimationPlayer.animation_finished
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_settings_button_pressed() -> void:
	$CanvasLayer/SettingsMenu.show()
