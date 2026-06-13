# 【TournamentSetup.gd 完整自适应对阵图代码】
extends Control

@onready var size_slider = $CenterContainer/VBoxContainer/HBoxContainer/LeftColumn/SizeSlider
@onready var size_label = $CenterContainer/VBoxContainer/HBoxContainer/LeftColumn/SizeLabel
@onready var leader_grid = $CenterContainer/VBoxContainer/HBoxContainer/LeftColumn/ScrollContainer/LeaderGrid

@onready var board_slider_node = $CenterContainer/VBoxContainer/HBoxContainer/LeftColumn/BoardSlider/Slider
@onready var board_label_node = $CenterContainer/VBoxContainer/HBoxContainer/LeftColumn/BoardSlider/Label

@onready var register_btn = $CenterContainer/VBoxContainer/RegisterBtn
@onready var back_btn = $BackButton

# 预载入卡牌
var card_scene = preload("res://Card.tscn")
var size_options = [16, 32, 64]
var size_select_idx: int = 0
var selected_leader_name: String = ""
var board_options = [
	{"text": "BOARD_9X9", "val": 9},
	{"text": "BOARD_13X13", "val": 13},
	{"text": "BOARD_19X19", "val": 19}
]
var board_select_idx: int = 2 # 默认 19路 (索引为 2)
func _ready():
	# 信号防重连保护
	if not back_btn.pressed.is_connected(_on_back_pressed):
		back_btn.pressed.connect(_on_back_pressed)
		
	if not register_btn.pressed.is_connected(_on_register_pressed):
		register_btn.pressed.connect(_on_register_pressed)
	
	# 初始化滑块
	board_slider_node.value = board_select_idx
	board_label_node.text = tr("BOARD_LBL") % tr(board_options[board_select_idx]["text"])
	if not board_slider_node.value_changed.is_connected(_on_board_slider_changed):
		board_slider_node.value_changed.connect(_on_board_slider_changed)
		
	# 此时进入该场景必定是未报名状态，所以强制按钮置灰，并渲染领袖网格
	register_btn.disabled = true
	populate_leader_grid()
func _on_back_pressed():
	get_tree().change_scene_to_file("res://ModeSelection.tscn")
func _on_size_slider_changed(val: float):
	size_select_idx = int(val)
	_update_size_label()



func _update_size_label():
	var t_size = size_options[size_select_idx]
	size_label.text = tr("TOURNAMENT_SIZE_LBL") % [t_size, 4 if t_size == 16 else (5 if t_size == 32 else 6)]
func _on_board_slider_changed(val: float):
	board_select_idx = int(val)
	board_label_node.text = tr("BOARD_LBL") % tr(board_options[board_select_idx]["text"])


func populate_leader_grid():
	for child in leader_grid.get_children():
		child.queue_free()
	var all_cards = ConfigManager.get_all_card_resources()
	for data in all_cards:
		if data.card_name in ConfigManager.unlocked_cards:
			var card_inst = card_scene.instantiate()
			leader_grid.add_child(card_inst)
			card_inst.setup_card(data)
			if data.card_name == selected_leader_name:
				card_inst.modulate = Color(0.502, 1.0, 0.502, 0.169)
			card_inst.pressed.connect(_on_leader_selected.bind(data, card_inst))

func _on_leader_selected(data: CardData, card_inst: TextureButton):
	selected_leader_name = data.card_name
	
	# 刷新网格状态高亮
	for child in leader_grid.get_children():
		child.modulate = Color.WHITE
	card_inst.modulate = Color(1.0, 1.0, 1.0, 0.325)
	
	# 激活报名参赛按钮
	register_btn.disabled = false
# 点击报名或进入下一轮
func _on_register_pressed():
	if ConfigManager.tournament_active:
		# 情况 A：如果锦标赛已经激活（对阵图已画好），点击直接进入战斗场景开始对局！
		get_tree().change_scene_to_file("res://go_board.tscn")
		return
		
	# 情况 B：如果是一届全新的比赛，运行以下名单生成逻辑：
	ConfigManager.tournament_active = true
	ConfigManager.tournament_size = size_options[size_select_idx]
	ConfigManager.tournament_character = selected_leader_name
	ConfigManager.tournament_round = 1
	ConfigManager.current_deck = [selected_leader_name]
	
	# ===== 全自动生成本届锦标赛 16/32/64 人对阵大名单 =====
	var roster = [selected_leader_name] # 玩家加入
	var all_cards = ConfigManager.get_all_card_resources()
	var available_enemies = []
	for card in all_cards:
		if card.card_name != selected_leader_name:
			available_enemies.append(card.card_name)
			
	# 如果你的自定义卡牌不够数，系统会自动用通用的虚拟棋手补齐，防止报错
	while available_enemies.size() < ConfigManager.tournament_size - 1:
		available_enemies.append(tr("VIRTUAL_PLAYER") % (available_enemies.size() + 1))
		
	available_enemies.shuffle()
	# 抓取对应数量的对手加入名单
	for i in range(ConfigManager.tournament_size - 1):
		roster.append(available_enemies[i])
		
	# 再次彻底洗牌，打乱玩家和所有 AI 在首轮中的对阵位置
	roster.shuffle()
	
	# 初始化对阵树的第一轮名单
	ConfigManager.tournament_tree = [roster]
	
	# 确定第一轮里，谁抽签抽到了玩家作为对手
	var my_idx = roster.find(selected_leader_name)
	# 围棋两两对决，如果是奇数索引，对手是左边；如果是偶数索引，对手是右边
	var opp_idx = my_idx - 1 if my_idx % 2 == 1 else my_idx + 1
	ConfigManager.tournament_opponent = roster[opp_idx]
	
	# ==================== 【核心修复】 ====================
	# 100% 场景化读值：直接从你在编辑器里建好的 opt_board 下拉框中读取 ID (9, 13 或 19)
	var b_size = board_options[board_select_idx]["val"]
	ConfigManager.tournament_board_size = b_size
	ConfigManager.tournament_komi = 3.5 if b_size == 9 else (5.5 if b_size == 13 else 7.5)
	# =====================================================
	
	ConfigManager.save_game()
	
	# 安全重载场景，彻底解决信号冲突
	get_tree().change_scene_to_file("res://BracketView.tscn")
