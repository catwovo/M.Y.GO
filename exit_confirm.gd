# 【exit_confirm.gd 完整代码】
extends Control

@onready var save_exit_btn = $PanelContainer/VBoxContainer/ButtonHBox/SaveExitBtn
@onready var surrender_btn = $PanelContainer/VBoxContainer/ButtonHBox/SurrenderBtn
@onready var cancel_btn = $PanelContainer/VBoxContainer/ButtonHBox/CancelBtn

func _ready():
	save_exit_btn.pressed.connect(_on_save_exit_pressed)
	surrender_btn.pressed.connect(_on_surrender_pressed)
	cancel_btn.pressed.connect(_on_cancel_pressed)

# A. 选项 1：保存快照并秒退大厅
func _on_save_exit_pressed():
	# 逆向调用父节点（GoBoard）写好的物理存盘函数
	if get_parent() and get_parent().has_method("save_active_match"):
		get_parent().save_active_match()
	queue_free()
	get_tree().change_scene_to_file("res://ModeSelection.tscn")

# B. 选项 2：放弃对局直接认输
func _on_surrender_pressed():
	ConfigManager.active_match_exists = false
	ConfigManager.is_resuming_match = false
	ConfigManager.save_game()
	queue_free()
	
	if ConfigManager.tournament_active:
		ConfigManager.tournament_active = false
		ConfigManager.save_game()
		get_tree().change_scene_to_file("res://main_menu.tscn")
	else:
		get_tree().change_scene_to_file("res://ModeSelection.tscn")

# C. 选项 3：取消弹窗，返回棋局
func _on_cancel_pressed():
	# 销毁弹窗，重回战场
	queue_free()
