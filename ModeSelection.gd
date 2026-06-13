# 【ModeSelection.gd 完整代码】
extends Control

@onready var quick_play_btn = $CenterContainer/VBoxContainer/ModeCards/QuickPlayBtn
@onready var tournament_btn = $CenterContainer/VBoxContainer/ModeCards/TournamentBtn
@onready var deck_builder_btn = $DeckBuilderBtn
@onready var back_btn = $BackButton
@onready var settings_btn = $SettingsButton # 【核心新增】
func _ready():
	# 信号安全连接
	if not quick_play_btn.pressed.is_connected(_on_quick_play_pressed):
		quick_play_btn.pressed.connect(_on_quick_play_pressed)
		
	if not tournament_btn.pressed.is_connected(_on_tournament_pressed):
		tournament_btn.pressed.connect(_on_tournament_pressed)
		
	if not deck_builder_btn.pressed.is_connected(_on_deck_builder_pressed):
		deck_builder_btn.pressed.connect(_on_deck_builder_pressed)
		
	if not back_btn.pressed.is_connected(_on_back_pressed):
		back_btn.pressed.connect(_on_back_pressed)
	if not settings_btn.pressed.is_connected(_on_settings_pressed):
		settings_btn.pressed.connect(_on_settings_pressed)
# 点击：快速游戏
func _on_quick_play_pressed():
	ConfigManager.tournament_active = false
	ConfigManager.save_game()
	_check_and_start_match("res://go_board.tscn", "quick")
func _on_settings_pressed():
	var settings_scene = load("res://Settings.tscn")
	var settings_inst = settings_scene.instantiate()
	add_child(settings_inst) # 挂载为自己的子节点，直接显示为上层浮窗
# 点击：锦标赛
func _on_tournament_pressed():
	# 【核心修复】：锦标赛也必须通过安全检测！防止有未完结存档时被直接绕过
	if ConfigManager.tournament_active:
		# 锦标赛正在打：通过安全检测去对阵图
		_check_and_start_match("res://BracketView.tscn", "tournament")
	else:
		_check_and_start_match("res://TournamentSetup.tscn", "tournament")
# 点击：管理卡组
func _on_deck_builder_pressed():
	# 跳转到我们即将建立的专属“卡包仓库与编组场景”
	get_tree().change_scene_to_file("res://DeckBuilder.tscn")

# 点击：返回
func _on_back_pressed():
	# 返回到解谜主界面
	get_tree().change_scene_to_file("res://main_menu.tscn")
# 【替换 ModeSelection.gd 中的该函数：实现智能双存档槽隔离】
func _check_and_start_match(target_scene: String, mode: String):

	# 【核心修复】：只有当存档存在，且存档里的对局模式（quick/tournament）与当前玩家点击的完全一致时，才弹窗！
	if ConfigManager.active_match_exists and ConfigManager.saved_match_mode == mode:
		var mask = ColorRect.new()
		mask.color = Color(0.1, 0.1, 0.1, 0.8)
		mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(mask)
		
		var panel = PanelContainer.new()
		panel.custom_minimum_size = Vector2(350, 180)
		panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		mask.add_child(panel)
		
		var vbox = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 15)
		panel.add_child(vbox)
		
		var title = Label.new()
		title.text = tr("POPUP_RESUME_TITLE")
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(title)
		
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 20)
		vbox.add_child(hbox)
		
		var btn_continue = Button.new()
		btn_continue.text = tr("POPUP_RESUME_BTN")
		btn_continue.custom_minimum_size = Vector2(130, 40)
		btn_continue.pressed.connect(func():
			ConfigManager.is_resuming_match = true
			mask.queue_free()
			get_tree().change_scene_to_file("res://go_board.tscn")
		)
		hbox.add_child(btn_continue)
		
		var btn_new = Button.new()
		btn_new.text = tr("POPUP_NEW_BTN")
		btn_new.custom_minimum_size = Vector2(130, 40)
		btn_new.pressed.connect(func():
			ConfigManager.active_match_exists = false
			ConfigManager.is_resuming_match = false
			ConfigManager.save_game()
			mask.queue_free()
			get_tree().change_scene_to_file(target_scene)
		)
		hbox.add_child(btn_new)
	else:
		# 如果不一致（比如有锦标赛存档，但玩家点击的是快速游戏），不打扰玩家，直接进入配置新游戏，且绝不删除/污染原本的另一个存档！
		ConfigManager.is_resuming_match = false
		get_tree().change_scene_to_file(target_scene)
