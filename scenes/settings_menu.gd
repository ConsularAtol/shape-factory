extends Control

func _ready() -> void:
	hide()
	loadSettings()

func loadSettings() -> void:
	var settings = Global.getSettings()
	$ColorRect/VBoxContainer/MusicVolume/Slider.value = db_to_linear(settings["music_volume"]) * 100.0
	$ColorRect/VBoxContainer/SFXVolume/Slider.value = db_to_linear(settings["sfx_volume"]) * 100.0
	$ColorRect/VBoxContainer/FullScreen/CheckBox.button_pressed = settings["fullscreen"]
	$ColorRect/VBoxContainer/VSync/CheckBox.button_pressed = settings["vsync"]
	$ColorRect/VBoxContainer/MaxFPS/Slider.value = settings["max_fps"]

func _on_music_volume_value_changed(value: float) -> void:
	$ColorRect/VBoxContainer/MusicVolume/Value.text = str(int(round(value))) + "%"
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(value / 100.0))
	$AudioSliderNoise.bus = &"Music"
	$AudioSliderNoise.play()
	Global.save_data()

func _on_sfx_volume_value_changed(value: float) -> void:
	$ColorRect/VBoxContainer/SFXVolume/Value.text = str(int(round(value))) + "%"
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(value / 100.0))
	$AudioSliderNoise.bus = &"SFX"
	$AudioSliderNoise.play()
	Global.save_data()

func _on_maxfps_value_changed(value: float) -> void:
	$ColorRect/VBoxContainer/MaxFPS/Value.text = str(int(value))
	Engine.max_fps = int(value)
	Global.save_data()

func _on_fullscreen_box_toggled(toggled_on: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if toggled_on else DisplayServer.WINDOW_MODE_WINDOWED)
	Global.save_data()

func _on_vsync_box_toggled(toggled_on: bool) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if toggled_on else DisplayServer.VSYNC_DISABLED)
	Global.save_data()

func _on_close_button_pressed() -> void:
	Global.save_data()
	hide()
