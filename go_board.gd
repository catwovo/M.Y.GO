extends Node2D
@onready var status_label = $CanvasLayer/StatusLabel
@onready var hand_ui = $CanvasLayer/HandUI
@onready var explanation_box = $CanvasLayer/ExplanationBox

@onready var info_label = $CanvasLayer/InfoLabel
# ===== 新增：执子颜色控制变量 =====
var player_color: int = 1       # 1 = 玩家执黑，2 = 玩家执白
var ai_color: int = 2           # AI 的颜色，恒为 3 - player_color
var color_select_idx: int = 0   # 默认 0 (执黑)
var board_select_idx_master: int = 2 # 默认 19路 (索引为 2)
const BOARD_CENTER_X_Y = 400.0
var has_sent_llm_this_turn: bool = false # 防抖锁：确保每一手牌有且仅能发起一次 LLM 请求
var board_size: int = 9         # 动态棋盘大小 (9 或 13)
var cell_size: float = 60.0     # 动态格子间距
var margin: float = 50.0        # 棋盘边缘留白
var stone_radius: float = 26.0  # 棋子动态半径
var is_ai_thinking: bool = false
var ai_difficulty: String = "medium" # 难度：easy, medium, hard
# ===== 新增：AI 棋风性格变量 =====
var ai_style: String = "balanced" # balanced(均衡), aggressive(力战), defensive(稳健), cosmic(宇宙)
var kata_service: KataService = null
# ===== 新增于 go_board.gd 变量区 =====
var is_manual_mode: bool = false # 开关控制：是否开启玩家自主下棋模式
# ===== 新增：棋子顺序控制与历史纪录 =====
var stone_number_mode: String = "last" # none(隐藏), last(只显最后一手), all(全部显示)
var move_history: Array[Vector2i] = []  # 记录整盘棋的落子物理顺序
var board_state = []
var active_candidates: Array = []
var pending_candidates: Array = []
var star_points: Array[Vector2i] = [] # 星位坐标列表
var current_turn = 1 # 1 = 玩家(黑棋), 2 = AI(白棋)
var enable_llm_card: bool = true   # 按钮控制：是否开启卡牌 AI 点评（关闭则不发送数据给 DeepSeek）

const COLUMNS_X = ["A", "B", "C", "D", "E", "F", "G", "H", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T"]
# ===== 新增：形势、胜率开关、大局观控制变量 =====
var show_winrate: bool = false         # 是否显示推荐胜率（由按钮控制）
var show_territory_map: bool = false   # 是否显示实时形势阴影
var board_ownership: Array = []       # 缓存 KataGo 计算出的 2D 势力热图
var last_llm_comments: Dictionary = {} # 缓存大模型评语，用于无需 Token 的秒切开关

var black_captured: int = 0       # 白棋（AI）提掉黑子的数量 (白棋得分)
var white_captured: int = 0       # 黑棋（玩家）提掉白子的数量 (黑棋得分)
var game_time_elapsed: float = 0.0 # 游戏对局已用时间 (秒)

var waiting_for_ai_analysis: bool = false # 标记：当前 KataGo 返回的推荐点是否用于 AI 自身做决策
var http_request: HTTPRequest = null # 用于网络请求的节点
var current_candidates_data = [] # 缓存当前推荐数据，用于备用
# 卡牌数据
var last_card_select_time: int = 0
var active_card_index = -1 
var quick_opponent_list: Array = [] # 存储所有的 .tres 棋手资源
var quick_opponent_idx: int = 0    # 玩家选中的对手索引
var consecutive_passes = 0  # 连续停一手计数。若达到 2，则游戏结束
var is_game_over = false    # 游戏是否结束
var komi: float = 7.5 # 动态贴目变量 (9路为 3.5，13路为 5.5)
var board_options = [
	{"text": "BOARD_9X9", "val": 9},
	{"text": "BOARD_13X13", "val": 13},
	{"text": "BOARD_19X19", "val": 19}
]
var board_select_idx: int = 0 # 默认选中 9路

var diff_options = [
	{"text": "20k", "val": "20k"},
	{"text": "15k", "val": "15k"},
	{"text": "10k", "val": "5k"},
	{"text": "1k", "val": "1k"},
	{"text": "1d", "val": "1d"},
	{"text": "3d", "val": "3d"},
	{"text": "5d", "val": "5d"},
	{"text": "9d", "val": "9d"}
]
var diff_select_idx: int = 3 # 默认选中第 4 项：5k 中级战术

var style_options = [
	{"text": "STYLE_BALANCED", "val": "balanced"},
	{"text": "STYLE_AGGRESSIVE", "val": "aggressive"},
	{"text": "STYLE_DEFENSIVE", "val": "defensive"},
	{"text": "STYLE_COSMIC", "val": "cosmic"}
]
var style_select_idx: int = 0 # 默认选中大局均衡
func _ready():
	# 1. 实例化并连接 KataGo 服务
	kata_service = KataService.new()
	add_child(kata_service)
	kata_service.candidates_ready.connect(_on_kata_candidates_ready)
	kata_service.score_ready.connect(_on_kata_score_ready)

	# 2. 【核心修复】：重新补全大语言模型请求节点的初始化和连接
	http_request = HTTPRequest.new()
	http_request.timeout = 5.0 
	add_child(http_request)
	http_request.request_completed.connect(_on_llm_request_completed)
	setup_game_parameters(board_options[board_select_idx]["val"])
	# 3. 默认隐藏手牌，等待配置面板完成
	connect_scene_ui_signals()
	
	# ==================== 【核心三向开局自适应检测】 ====================
	if ConfigManager.active_match_exists and ConfigManager.is_resuming_match:
		# 情况 A：玩家在主大厅选择了“继续上局”，一键复原并重塑历史战场！
		load_active_match()
	elif ConfigManager.tournament_active:
		# 情况 B：锦标赛进行中，跳过配置面板，直通锦标赛棋盘对局！
		start_tournament_game_direct()
	else:
		# 情况 C：普通快速游戏，默认隐藏手牌和控制栏，等待玩家调节滑块并开始
		hand_ui.visible = false
		if $CanvasLayer.has_node("UtilityBar"):
			$CanvasLayer/UtilityBar.visible = false
func start_tournament_game_direct():
	if $CanvasLayer.has_node("SetupMenuMask"):
		$CanvasLayer/SetupMenuMask.queue_free()
	board_size = ConfigManager.tournament_board_size
	komi = ConfigManager.tournament_komi
	setup_game_parameters(board_size)
	
	# 2. 【核心动态难度】：自动读取对手的 .tres 文件，锁定该 Boss 棋手的真实段位与风格！
	var enemy_res = load("res://cards/" + ConfigManager.tournament_opponent + ".tres")
	if enemy_res is CardData:
		# 除去 preaz_ 前缀，转换为我们代码识别的段位格式（如 15k, 9d 等）
		ai_difficulty = enemy_res.ai_rank.replace("preaz_", "")
		ai_style = enemy_res.ai_style
	else:
		ai_difficulty = "5k" # 备用安全值
		ai_style = "balanced"
	
	# 3. 初始化棋盘
	move_history.clear()
	black_captured = 0
	white_captured = 0
	game_time_elapsed = 0.0
	board_state.clear()
	for i in range(board_size):
		var row = []
		for j in range(board_size): row.append(0)
		board_state.append(row)
		
	# 4. 唤醒 KataGo
	update_status_label(tr("STATUS_MATCHING") % ConfigManager.tournament_opponent)
	var success = kata_service.start_katago_dynamic(board_size, komi)
	if success:
		update_status_label(tr("STATUS_TOURNAMENT") % [ConfigManager.tournament_round, ConfigManager.tournament_opponent, tr(ai_difficulty), tr(ai_style)])
		hand_ui.visible = true
		refill_hand()
		$CanvasLayer/UtilityBar.visible = true
	else:
		update_status_label(tr("STATUS_BRAIN_FAIL"))
	queue_redraw()
func connect_scene_ui_signals():
	var bar = $CanvasLayer/UtilityBar
	
	# ==================== 【核心安全同步】 ====================
	# 强制将场景中所有编辑器按钮的初始视觉状态，同步为与代码中的变量完全一致！
	bar.get_node("ManualBtn").button_pressed = is_manual_mode
	bar.get_node("WinrateBtn").button_pressed = show_winrate
	bar.get_node("TerritoryBtn").button_pressed = show_territory_map
	bar.get_node("CardAIBtn").button_pressed = enable_llm_card

	# =========================================================
	
	# 1. 连接你在场景里建好的“自主下棋 (ManualBtn)”开关
	if not bar.get_node("ManualBtn").toggled.is_connected(_on_manual_toggled):
		bar.get_node("ManualBtn").toggled.connect(func(pressed: bool):
			_on_manual_toggled(pressed)
		)
		
	if not bar.get_node("WinrateBtn").toggled.is_connected(_on_winrate_toggled):
		bar.get_node("WinrateBtn").toggled.connect(func(pressed):
			show_winrate = pressed
			if last_llm_comments.size() > 0:
				render_llm_commentary(last_llm_comments)
		)
		
	if not bar.get_node("TerritoryBtn").toggled.is_connected(_on_territory_toggled):
		bar.get_node("TerritoryBtn").toggled.connect(func(pressed):
			show_territory_map = pressed
			if not show_territory_map:
				board_ownership.clear()
			queue_redraw()
		)
	
	# 4. 自动初始化并连接场景中的“落子手顺 (NumOpt)”下拉框
	var num_opt = bar.get_node("NumOpt")
	num_opt.clear()
	num_opt.add_item(tr("NUM_OPT_NONE"), 0)
	num_opt.add_item(tr("NUM_OPT_LAST"), 1)
	num_opt.add_item(tr("NUM_OPT_ALL"), 2)
	
	if stone_number_mode == "none": num_opt.select(0)
	elif stone_number_mode == "last": num_opt.select(1)
	else: num_opt.select(2)
	
	num_opt.item_selected.connect(func(id):
		if id == 0: stone_number_mode = "none"
		elif id == 1: stone_number_mode = "last"
		else: stone_number_mode = "all"
		queue_redraw()
	)
	if not num_opt.item_selected.is_connected(_on_num_opt_selected):
		num_opt.item_selected.connect(_on_num_opt_selected)
	# 5. 连接卡牌 AI 点评开关
	if not bar.get_node("CardAIBtn").toggled.is_connected(_on_card_ai_toggled):
		bar.get_node("CardAIBtn").toggled.connect(_on_card_ai_toggled)
		

	if $CanvasLayer.has_node("PassBtn"):
		var pass_btn = $CanvasLayer/PassBtn
		if not pass_btn.pressed.is_connected(_on_pass_pressed):
			pass_btn.pressed.connect(_on_pass_pressed)
	if $CanvasLayer.has_node("ExitBtn"):
		var exit_btn = $CanvasLayer/ExitBtn
		if not exit_btn.pressed.is_connected(_on_exit_pressed):
			exit_btn.pressed.connect(_on_exit_pressed)
	var vbox = $CanvasLayer/SetupMenuMask/SetupPanel/VBoxContainer
	var tc = vbox.get_node("SetupTabContainer")
	
	var board_sld = tc.get_node("AIBattle/BoardSlider/Slider")
	var board_lbl = tc.get_node("AIBattle/BoardSlider/Label")
	if board_sld:
		board_sld.value = board_select_idx
		board_lbl.text = tr("BOARD_LBL") % tr(board_options[board_select_idx]["text"])
		if not board_sld.value_changed.is_connected(_on_board_slider_changed):
			board_sld.value_changed.connect(_on_board_slider_changed)
		
	var diff_sld = tc.get_node("AIBattle/DiffSlider/Slider")
	var diff_lbl = tc.get_node("AIBattle/DiffSlider/Label")
	if diff_sld:
		diff_sld.value = diff_select_idx
		diff_lbl.text = tr("DIFF_LBL") % tr(diff_options[diff_select_idx]["text"])
		if not diff_sld.value_changed.is_connected(_on_diff_slider_changed):
			diff_sld.value_changed.connect(_on_diff_slider_changed)
		
	var style_sld = tc.get_node("AIBattle/StyleSlider/Slider")
	var style_lbl = tc.get_node("AIBattle/StyleSlider/Label")
	if style_sld:
		style_sld.value = style_select_idx
		style_lbl.text = tr("STYLE_LBL") % tr(style_options[style_select_idx]["text"])
		if not style_sld.value_changed.is_connected(_on_style_slider_changed):
			style_sld.value_changed.connect(_on_style_slider_changed)

	# ---- TAB 2: 棋手挑战赛滑块连接 ----
	var master_board_sel = tc.get_node("MasterBattle/BoardSliderMaster")
	if master_board_sel:
		var sld = master_board_sel.get_node_or_null("Slider")
		var lbl = master_board_sel.get_node_or_null("Label")
		if sld == null:
			for child in master_board_sel.get_children():
				if child is HSlider: sld = child; break
		if lbl == null:
			for child in master_board_sel.get_children():
				if child is Label: lbl = child; break
		if sld and lbl:
			sld.value = board_select_idx_master
			lbl.text = tr("BOARD_LBL") % tr(board_options[board_select_idx_master]["text"])
			if not sld.value_changed.is_connected(_on_master_board_changed):
				sld.value_changed.connect(_on_master_board_changed.bind(lbl))

	# 对手滚动列表选择器 (Tab 2 - 棋手挑战)
	var opp_sel = tc.get_node("MasterBattle/OpponentSelector")
	if opp_sel:
		var list_lbl = opp_sel.get_node("Label")
		var list_container = opp_sel.get_node("Scroll/OpponentList")
		for child in list_container.get_children():
			child.queue_free()
		quick_opponent_list = ConfigManager.get_all_card_resources()
		
		for i in range(quick_opponent_list.size()):
			var opp = quick_opponent_list[i]
			var btn = Button.new()
			btn.text = opp.card_name
			btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
			btn.custom_minimum_size = Vector2(80, 35)
			
			if i == quick_opponent_idx:
				btn.modulate = Color(0.5, 1.0, 0.5)
				
				list_lbl.text = tr("OPPONENT_LBL") % opp.card_name
				
			btn.pressed.connect(func():
				for child in list_container.get_children():
					child.modulate = Color.WHITE
				btn.modulate = Color(0.5, 1.0, 0.5)
				quick_opponent_idx = i
				
				list_lbl.text = tr("OPPONENT_LBL") % opp.card_name
				
			)
			list_container.add_child(btn)

	# 执子选择滑块 (位于 VBoxContainer，不在 Tab 内部)
	var color_sel = vbox.get_node("ColorSlider")
	if color_sel:
		var color_sld = color_sel.get_node("Slider")
		var color_lbl = color_sel.get_node("Label")
		color_sld.value = color_select_idx
		var color_str = tr("COLOR_BLACK") if player_color == 1 else tr("COLOR_WHITE")
		color_lbl.text = tr("COLOR_LBL") % color_str
		if not color_sld.value_changed.is_connected(_on_color_slider_changed.bind(color_lbl)):
			color_sld.value_changed.connect(_on_color_slider_changed.bind(color_lbl))

	# 开始游戏按钮
	var start_btn = vbox.get_node("StartGameBtn")
	if start_btn:
		if not start_btn.pressed.is_connected(_on_start_game_pressed):
			start_btn.pressed.connect(_on_start_game_pressed)
	var setup_back_btn = vbox.get_node("SetupBackBtn")
	if setup_back_btn:
		if not setup_back_btn.pressed.is_connected(_on_setup_back_pressed):
			setup_back_btn.pressed.connect(_on_setup_back_pressed)
func _on_setup_back_pressed():
	# 命令 KataGo 安全关闭
	kata_service.stop_service()
	# 秒退回模式大厅场景
	get_tree().change_scene_to_file("res://ModeSelection.tscn")
func _on_num_opt_selected(id: int):
	if id == 0: stone_number_mode = "none"
	elif id == 1: stone_number_mode = "last"
	else: stone_number_mode = "all"
	queue_redraw()

func _on_card_ai_toggled(pressed: bool):
	enable_llm_card = pressed
	update_status_label("已%s卡牌 AI 点评" % ["开启" if pressed else "关闭"])

func _on_board_slider_changed(val: float):
	board_select_idx = int(val)
	var board_lbl = $CanvasLayer/SetupMenuMask/SetupPanel/VBoxContainer/SetupTabContainer/AIBattle/BoardSlider/Label
	board_lbl.text = tr("BOARD_LBL") % tr(board_options[board_select_idx]["text"])
	setup_game_parameters(board_options[board_select_idx]["val"])
	queue_redraw()

func _on_diff_slider_changed(val: float):
	diff_select_idx = int(val)
	var diff_lbl = $CanvasLayer/SetupMenuMask/SetupPanel/VBoxContainer/SetupTabContainer/AIBattle/DiffSlider/Label
	diff_lbl.text = tr("DIFF_LBL") % tr(diff_options[diff_select_idx]["text"])

func _on_style_slider_changed(val: float):
	style_select_idx = int(val)
	var style_lbl = $CanvasLayer/SetupMenuMask/SetupPanel/VBoxContainer/SetupTabContainer/AIBattle/StyleSlider/Label
	style_lbl.text = tr("STYLE_LBL") % tr(style_options[style_select_idx]["text"])

func _on_color_slider_changed(val: float, color_lbl: Label):
	color_select_idx = int(val)
	player_color = 1 if color_select_idx == 0 else 2
	ai_color = 2 if player_color == 1 else 1
	var color_str = tr("COLOR_BLACK") if player_color == 1 else tr("COLOR_WHITE")
	color_lbl.text = tr("COLOR_LBL") % color_str
func _on_master_board_changed(val: float, lbl_node: Label):
	board_select_idx_master = int(val)
	lbl_node.text = "棋盘大小: " + board_options[board_select_idx_master]["text"]
	setup_game_parameters(board_options[board_select_idx_master]["val"])
	queue_redraw()

func create_start_menu():
	var canvas = $CanvasLayer
	var mask = ColorRect.new()
	mask.name = "StartMenuMask"
	mask.color = Color(0.1, 0.1, 0.1, 0.8)
	mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(mask)
	
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(450, 220)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	mask.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)
	
	var title = Label.new()
	title.text = "—— 围棋大局观对决 ——"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	var board_hbox = HBoxContainer.new()
	var lbl_board = Label.new()
	lbl_board.text = "棋盘大小: "
	var opt_board = OptionButton.new()
	opt_board.name = "OptBoard"
	opt_board.add_item("9 路棋盘", 9)
	opt_board.add_item("13 路棋盘", 13)
	opt_board.add_item("19 路棋盘", 19)
	board_hbox.add_child(lbl_board)
	board_hbox.add_child(opt_board)
	vbox.add_child(board_hbox)
	
	# 【细分】：9 个专业围棋级别
	var diff_hbox = HBoxContainer.new()
	var lbl_diff = Label.new()
	lbl_diff.text = "AI 棋力级别: "
	var opt_diff = OptionButton.new()
	opt_diff.name = "OptDiff"
	opt_diff.add_item("20k", 0)
	opt_diff.add_item("15k", 1)
	opt_diff.add_item("10k", 2)
	opt_diff.add_item("5k", 3)
	opt_diff.add_item("1k", 4)
	opt_diff.add_item("1d", 5)
	opt_diff.add_item("3d", 6)
	opt_diff.add_item("5d", 7)
	opt_diff.add_item("9d", 8)
	opt_diff.select(3) # 默认选中 5k
	diff_hbox.add_child(lbl_diff)
	diff_hbox.add_child(opt_diff)
	vbox.add_child(diff_hbox)
	
	var style_hbox = HBoxContainer.new()
	var lbl_style = Label.new()
	lbl_style.text = "AI 棋风偏好: "
	var opt_style = OptionButton.new()
	opt_style.name = "OptStyle"
	opt_style.add_item("大局均衡", 0)
	opt_style.add_item("力战混战", 1)
	opt_style.add_item("坚实稳健", 2)
	opt_style.add_item("宇宙中腹", 3)
	opt_style.select(0)
	style_hbox.add_child(lbl_style)
	style_hbox.add_child(opt_style)
	vbox.add_child(style_hbox)
	
	var start_btn = Button.new()
	start_btn.text = "MENU_START_GAME"
	start_btn.custom_minimum_size = Vector2(0, 50)
	start_btn.pressed.connect(_on_start_game_pressed.bind(mask, opt_board, opt_diff, opt_style))
	vbox.add_child(start_btn)

# 【替换你原本的对局启动函数：适配 HSlider 零参数信号与自动配置】
# 【替换你原本的对局启动函数：加入 Tab 选项卡分支判定】
func _on_start_game_pressed():
	# 获取当前处于哪一个 Tab 选项卡 (0 = AI自由对战, 1 = 棋手挑战赛)
	var tab_container = $CanvasLayer/SetupMenuMask/SetupPanel/VBoxContainer/SetupTabContainer
	var active_tab_index = tab_container.current_tab
	
	# 定义临时棋盘大小
	var selected_size = 9
	
	if active_tab_index == 0:
		# 情况 A：玩家选择【AI自由对战】 (手动拉三个滑块配置)
		selected_size = board_options[board_select_idx]["val"]
		ai_difficulty = diff_options[diff_select_idx]["val"]
		ai_style = style_options[style_select_idx]["val"]
		ConfigManager.tournament_opponent = "AI"
	else:
		# 情况 B：玩家选择【棋手挑战赛】 (读取所选棋手卡牌属性，完全锁定难度和棋风)
		selected_size = board_options[board_select_idx_master]["val"]
		var chosen_opp = quick_opponent_list[quick_opponent_idx]
		ConfigManager.tournament_opponent = chosen_opp.card_name
		ai_difficulty = chosen_opp.ai_rank.replace("preaz_", "")
		ai_style = chosen_opp.ai_style

	# 写入全局对局大小设定与自适应参数/贴目计算
	board_size = selected_size
	setup_game_parameters(selected_size)
	
	# 直接销毁高斯模糊遮罩（SetupMenuMask 自身），战场变清晰
	if $CanvasLayer.has_node("SetupMenuMask"):
		$CanvasLayer/SetupMenuMask.queue_free()
		
	# 重置对局历史、提子数、秒表已用时间
	move_history.clear()
	black_captured = 0
	white_captured = 0
	game_time_elapsed = 0.0
	
	# 初始化棋盘二维数组
	board_state.clear()
	for i in range(board_size):
		var row = []
		for j in range(board_size):
			row.append(0)
		board_state.append(row)
		
	# 启动并配置 KataGo
	update_status_label("正在为您唤醒 AI 引擎...")
	var success = kata_service.start_katago_dynamic(board_size, komi)
	if success:
		if active_tab_index == 0:
			update_status_label("🏆 快速游戏对局 | 对手: %s (级别: %s | 风格: %s)" % [ConfigManager.tournament_opponent, ai_difficulty, ai_style])
		else:
			update_status_label("🏆 棋手挑战赛 | 对手: %s (级别: %s | 风格: %s)" % [ConfigManager.tournament_opponent, ai_difficulty, ai_style])
		hand_ui.visible = true
		refill_hand()
	else:
		update_status_label("致命错误：无法连接 KataGo 围棋大脑！")
	
	queue_redraw()
	
	# 展现你在场景编辑器中摆好的工具栏
	$CanvasLayer/UtilityBar.visible = true
func _on_manual_toggled(button_pressed: bool):
	is_manual_mode = button_pressed
	if is_manual_mode:
		# 开启自主模式：清除任何卡牌激活状态和圆圈
		active_card_index = -1
		active_candidates.clear()
		pending_candidates.clear()
		queue_redraw()
		for child in hand_ui.get_children():
			child.modulate = Color(0.55, 0.55, 0.55)
		update_status_label("【自主下棋】模式已开启。你可以直接在棋盘任意空位落子！")
		
		if explanation_box:
			explanation_box.text = "[font_size=18][b]💡 自主下棋模式：[/b][/font_size]\n\n[color=gray]当前你已接管控制权。可以直接点击棋盘上任意空白处落子（黑棋）。落子后，AI 对手将自动根据你选择的段位和棋风进行应对。可以随时关闭此按钮重新回到卡牌托管。[/color]"
	else:
		update_status_label("卡牌托管中，请选择手牌落子")

		if explanation_box:
			explanation_box.text = "[font_size=18][b]💡 卡牌托管模式：[/b][/font_size]\n\n[color=gray]请点击下方的一张棋手卡牌，听听他们为你规划的神之一手战术！[/color]"
func _on_winrate_toggled(button_pressed: bool):
	show_winrate = button_pressed
	if current_candidates_data.size() > 0:
		# 如果开启了卡牌点评且有大模型缓存，用大模型渲染
		if enable_llm_card and last_llm_comments.size() > 0:
			render_llm_commentary(last_llm_comments)
		else:
			# 否则（离线状态下），直接重绘本地离线版
			_fallback_offline_explanation()
func _on_territory_toggled(button_pressed: bool):
	show_territory_map = button_pressed
	if not show_territory_map:
		board_ownership.clear()
		queue_redraw()
	else:
		update_status_label("形势实时判断已开启。落子后，阴影区将标记双方的绝对势力。")
func setup_game_parameters(size: int):
	board_size = size
	if board_size == 9:
		cell_size = 86.5
		stone_radius = 42.0
		margin = 50.0
		star_points = [Vector2i(4, 4)]
		komi = 3.5
	elif board_size == 13:
		cell_size = 60.0
		stone_radius = 28.0
		margin = 50.0
		star_points = [
			Vector2i(3, 3), Vector2i(3, 9),
			Vector2i(9, 3), Vector2i(9, 9),
			Vector2i(6, 6)
		]
		komi = 5.5
	elif board_size == 19:
		cell_size = 41.0
		stone_radius = 19.5
		margin = 50.0
		komi = 7.5 # 19路标准贴 7.5 目
		# 19路标准九个星位（四角、四边、天元）
		star_points = [
			Vector2i(3, 3), Vector2i(3, 9), Vector2i(3, 15),
			Vector2i(9, 3), Vector2i(9, 9), Vector2i(9, 15),
			Vector2i(15, 3), Vector2i(15, 9), Vector2i(15, 15)
		]
	var board_width = (board_size - 1) * cell_size
	margin = BOARD_CENTER_X_Y - (board_width / 2.0)
	board_ownership.clear()

# 当玩家点击 Pass 按钮时
func _on_pass_pressed():
	if is_ai_thinking or current_turn == 2 or is_game_over:
		return
	
	print("玩家选择 Pass（停一手）")
	consecutive_passes += 1
	
	if consecutive_passes >= 2:
		trigger_game_over()
	else:
		# 轮到 AI，AI 决定是否也 Pass
		switch_to_ai_turn()

func _draw():
	# 1. 绘制棋盘背景（浅黄色木质感色调）
	var board_rect = Rect2(margin - cell_size/2, margin - cell_size/2, cell_size * board_size, cell_size * board_size)
	draw_rect(board_rect, Color(0.347, 0.672, 0.631, 1.0), true)
	draw_rect(board_rect, Color(0.2, 0.1, 0.0), false, 2.0)

	# 2. 绘制经纬网格线 (根据 board_size 动态绘制)
	for i in range(board_size):
		var start = margin + i * cell_size
		draw_line(Vector2(margin, start), Vector2(margin + (board_size - 1) * cell_size, start), Color.BLACK, 1.5)
		draw_line(Vector2(start, margin), Vector2(start, margin + (board_size - 1) * cell_size), Color.BLACK, 1.5)

	# 3. 绘制动态星位 (9路画 1个，13路画 5个)
	var star_radius_size = 5.0 if board_size == 9 else 4.0
	for star in star_points:
		draw_circle(get_pixel_position(star.x, star.y), star_radius_size, Color.BLACK)

	# ===== 绘制本地形势阴影 (Influence Map) =====
	if show_territory_map:
		calculate_offline_influence()
		for x in range(board_size):
			for y in range(board_size):
				var val = board_ownership[y * board_size + x]
				var pos = get_pixel_position(x, y)
				if val > 0.15:
					# 我方势力 -> 渲染半透明蓝色柔光方块
					draw_rect(Rect2(pos - Vector2(cell_size/2, cell_size/2), Vector2(cell_size, cell_size)), Color(0.0, 0.4, 0.8, 0.3), true)
				elif val < -0.15:
					# 敌方势力 -> 渲染半透明红色柔光方块
					draw_rect(Rect2(pos - Vector2(cell_size/2, cell_size/2), Vector2(cell_size, cell_size)), Color(0.8, 0.1, 0.1, 0.3), true)

	# 4. 绘制自适应坐标 (横向 A-N，纵向 9-1 / 13-1)
	var coord_font = ThemeDB.get_fallback_font()
	var coord_font_size = 18 if board_size == 9 else 14 
	var coord_color = Color(1.0, 1.0, 1.0, 1.0)
	var offset_dist = 20.0 if board_size == 9 else 22.0

	for i in range(board_size):
		# A. 底部横向字母坐标
		var letter = COLUMNS_X[i]
		var grid_x = margin + i * cell_size
		var text_pos_bottom = Vector2(grid_x, margin + (board_size - 1) * cell_size + offset_dist)
		
		var letter_size = coord_font.get_string_size(letter, HORIZONTAL_ALIGNMENT_CENTER, -1, coord_font_size)
		text_pos_bottom.x -= letter_size.x / 2.0
		text_pos_bottom.y += letter_size.y / 3.0
		draw_string(coord_font, text_pos_bottom, letter, HORIZONTAL_ALIGNMENT_CENTER, -1, coord_font_size, coord_color)

		# B. 左侧纵向数字坐标
		var number = str(board_size - i)
		var grid_y = margin + i * cell_size
		var text_pos_left = Vector2(margin - offset_dist, grid_y)
		
		var number_size = coord_font.get_string_size(number, HORIZONTAL_ALIGNMENT_CENTER, -1, coord_font_size)
		text_pos_left.x -= number_size.x / 2.0
		text_pos_left.y += number_size.y / 3.0
		draw_string(coord_font, text_pos_left, number, HORIZONTAL_ALIGNMENT_CENTER, -1, coord_font_size, coord_color)

	# ==================== 【安全卫士】 ====================
	# 如果玩家还没点击“开始对局”，直接退回，不绘制后续棋子和候选点
	if board_state.size() < board_size:
		return

	# 5. 绘制所有已落下的棋子
	for x in range(board_size):
		for y in range(board_state[x].size()):
			var state = board_state[x][y]
			if state != 0:
				var pos = get_pixel_position(x, y)
				if state == 1:
					draw_circle(pos, stone_radius, Color.BLACK)
					draw_circle(pos, stone_radius, Color(0.2, 0.2, 0.2), false, 1.5)
				elif state == 2:
					draw_circle(pos, stone_radius, Color.WHITE)
					draw_circle(pos, stone_radius, Color.BLACK, false, 1.5)
	if stone_number_mode != "none" and move_history.size() > 0:
		var num_font = ThemeDB.get_fallback_font()
		var num_font_size = clamp(stone_radius * 1.0, 10, 20) # 字体大小随棋子大小自适应
		
		if stone_number_mode == "all":
			# 模式 1：全部显示
			for i in range(move_history.size()):
				var pos = move_history[i]
				var state = board_state[pos.x][pos.y]
				# 只有当这颗棋子还存活在棋盘上（没被提子）时，才绘制它的数字
				if state != 0:
					var pixel_pos = get_pixel_position(pos.x, pos.y)
					var text = str(i + 1)
					var text_color = Color.WHITE if state == 1 else Color.BLACK # 黑子用白字，白子用黑字
					
					var size = num_font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, num_font_size)
					var text_pos = pixel_pos + Vector2(-size.x / 2.0, size.y / 3.0)
					draw_string(num_font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, num_font_size, text_color)
					
		elif stone_number_mode == "last":
			# 模式 2：只显最后一手。在最后一颗存活的落子上画一个鲜红色的指示圆点
			var last_alive_idx = -1
			for i in range(move_history.size() - 1, -1, -1):
				var pos = move_history[i]
				if board_state[pos.x][pos.y] != 0:
					last_alive_idx = i
					break
			if last_alive_idx != -1:
				var pos = move_history[last_alive_idx]
				var pixel_pos = get_pixel_position(pos.x, pos.y)
				# 绘制专业的红点指示器
				draw_circle(pixel_pos, stone_radius * 0.35, Color(0.9, 0.1, 0.1))
	# 6. 绘制带序号的彩色推荐圈 (①, ②, ③)
	var font = ThemeDB.get_fallback_font()
	var font_size = 22 if board_size == 9 else 16
	for i in range(active_candidates.size()):
		var cand_data = active_candidates[i]
		var pos = get_pixel_position(cand_data["pos"].x, cand_data["pos"].y)
		var color = cand_data["color"] # 拿到古铜暗金色
		
		# 绘制带白边的彩色判定圆圈
		draw_circle(pos, stone_radius * 0.8, color)
		draw_circle(pos, stone_radius * 0.8, Color.WHITE, false, 1.5)
		
		# 【核心修复】：直接绘制我们存入缓存的字母标记 A, B, C！
		var text = cand_data["num_str"]
		var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var text_pos = pos + Vector2(-text_size.x / 2.0, text_size.y / 3.0) 
		
		draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.WHITE)
func get_pixel_position(grid_x: int, grid_y: int) -> Vector2:
	return Vector2(margin + grid_x * cell_size, margin + grid_y * cell_size)

func get_grid_position(pixel_pos: Vector2) -> Vector2i:
	var grid_x = round((pixel_pos.x - margin) / cell_size)
	var grid_y = round((pixel_pos.y - margin) / cell_size)
	return Vector2i(grid_x, grid_y)

# ==================== 回合状态控制 ====================

func update_status_label(text: String):
	if status_label:
		status_label.text = text

func switch_to_ai_turn():
	current_turn = 2
	is_ai_thinking = true
	var opponent_name = "AI"
	if ConfigManager.tournament_active:
		opponent_name = ConfigManager.tournament_opponent
		
	update_status_label("%s 正在长考中 (当前级别: %s)..." % [opponent_name, ai_difficulty])
	
	# 【核心安全重置】：在这里将右侧对话框切换为对手长考，使用 opponent_name
	if explanation_box:
		explanation_box.text = "[font_size=18][b]💡 %s 正在长考中...[/b][/font_size]" % opponent_name
	
	for btn in hand_ui.get_children():
		if btn is Button:
			btn.disabled = true
			
	if $CanvasLayer.has_node("PassBtn"):
		$CanvasLayer/PassBtn.disabled = true
			
	active_candidates.clear()
	pending_candidates.clear()
	queue_redraw()
	# 终局判定
	var empty_spaces = get_empty_spaces_count()
	var pass_threshold = 20 if board_size == 9 else 45
	if consecutive_passes == 1 and empty_spaces < pass_threshold:
		print("[终局判定] 玩家已 Pass 且已进入官子阶段，AI 跟着 Pass。")
		ai_pass()
		return
			
	await get_tree().create_timer(0.2).timeout
	
	waiting_for_ai_analysis = true
	
	# 【细分 9 级思考深度】：
	var visits = 20
	var temp = 0.1
	if ai_difficulty == "20k": visits = 2; temp = 4.0
	elif ai_difficulty == "15k": visits = 4; temp = 3.0
	elif ai_difficulty == "10k": visits = 6; temp = 2.0
	elif ai_difficulty == "5k": visits = 10; temp = 1.5
	elif ai_difficulty == "1k": visits = 15; temp = 1.0
	elif ai_difficulty == "1d": visits = 20; temp = 0.5
	elif ai_difficulty == "3d": visits = 25; temp = 0.2
	else: visits = 30; temp = 0.0 # 5d 和 9d 大师限制在 30 深度，秒回且绝对强力！
	
	if consecutive_passes == 1:
		visits = 30
	kata_service.min_required_visits = max(1, visits - 2)
	kata_service.send_command("kata-set-param maxPlayouts " + str(visits))
	kata_service.send_command("kata-set-param maxVisits " + str(visits))
	kata_service.send_command("kata-set-param chosenMoveTemperature " + str(temp))
	
	# 原生段位配置转换
	var target_rank = "preaz_5k"
	if ai_difficulty == "20k": target_rank = "preaz_20k" # 20k 降级匹配
	elif ai_difficulty == "15k": target_rank = "preaz_15k"
	elif ai_difficulty == "10k": target_rank = "preaz_10k"
	elif ai_difficulty == "5k": target_rank = "preaz_5k"
	elif ai_difficulty == "1k": target_rank = "preaz_1k"
	elif ai_difficulty == "1d": target_rank = "preaz_1d"
	elif ai_difficulty == "3d": target_rank = "preaz_3d"
	elif ai_difficulty == "5d": target_rank = "preaz_5d"
	else: target_rank = "preaz_9d"
	kata_service.send_command("kata-set-param humanSLProfile " + target_rank)
	# 指令同步
	var pda_value = 0.0
	if ai_style == "aggressive": pda_value = -2.5
	elif ai_style == "defensive": pda_value = 2.5
	
	
	kata_service.send_command("kata-set-param playoutDoublingAdvantage " + str(pda_value))
	
	# 命令算棋落子
	var ai_color_str = "b" if ai_color == 1 else "w"
	kata_service.send_command("lz-analyze " + ai_color_str + " 10")
# ==================== AI 智能决策逻辑 ====================

func ai_pass():
	print("AI 选择 Pass（停一手）")
	consecutive_passes += 1
	if consecutive_passes >= 2:
		# 触发终局（由于在 switch_to_ai_turn 的 await 中，我们在这里用 call_deferred 触发避免冲突）
		call_deferred("trigger_game_over")


func refill_hand():
	
	for child in hand_ui.get_children():
		child.queue_free()
	
	active_card_index = -1
	active_candidates.clear()
	
	var available_cards = []
	var all_cards = ConfigManager.get_all_card_resources()
	if ConfigManager.current_deck.size() > 0:
		for res in all_cards:
			if res.card_name in ConfigManager.current_deck:
				available_cards.append(res)
	
	if available_cards.size() == 0:
		print("[发牌保底] 玩家卡组为空或读取失败，启动应急兜底方案！强制发放卡牌。")
		# 强制把系统库里最多前 3 张卡借给玩家打！
		for i in range(min(3, all_cards.size())):
			available_cards.append(all_cards[i])
	if available_cards.size() == 0:
		print("【致命警告】：整个游戏内没有检测到任何棋手资源卡！")
		return
	# 随机分发 3 张手牌
	for i in range(min(3, available_cards.size())):
		var card_scene = load("res://Card.tscn")
		var card_instance = card_scene.instantiate()
		var random_data = available_cards[randi() % available_cards.size()]
		
		card_instance.card_data = random_data
		card_instance.pressed.connect(_on_card_selected.bind({}, i, card_instance))
		hand_ui.add_child(card_instance)

func _on_card_selected(_card_data: Dictionary, index: int, btn_node: TextureButton):

	if is_ai_thinking or current_turn == 2 or is_game_over:
		return
	kata_service.send_command("stop")
	active_card_index = index
	for child in hand_ui.get_children():
		child.modulate = Color.WHITE
	btn_node.modulate = Color(0.867, 1.0, 0.859, 0.027) # 点击高亮
	
	active_candidates.clear()
	update_status_label("KataGo 正在为您深度规划落子点...")
	has_sent_llm_this_turn = false
	last_card_select_time = Time.get_ticks_msec()
	var data = btn_node.card_data
	if explanation_box:
		explanation_box.text = "[font_size=18][b]💡 " + tr("DIALOG_THINKING_TITLE") + "[/b][/font_size]\n\n[color=gray]" + (tr("DIALOG_THINKING_DESC") % data.card_name) + "[/color]"
	var card_rank = data.ai_rank
	var card_style = data.ai_style
	var card_visits = 100
	
	# 自适应算力深度
	if "9d" in card_rank: card_visits = 100
	elif "5d" in card_rank: card_visits = 60
	elif "1d" in card_rank: card_visits = 40
	elif "1k" in card_rank: card_visits = 25
	elif "5k" in card_rank: card_visits = 15
	kata_service.min_required_visits = 25
	# 命令 KataGo 以该卡牌对应的段位和棋风进行运算
	kata_service.send_command("kata-set-param humanSLProfile " + card_rank)
	kata_service.send_command("kata-set-param playoutDoublingAdvantage " + str(-2.5 if card_style == "aggressive" else (2.5 if card_style == "defensive" else 0.0)))
	kata_service.send_command("kata-set-param maxPlayouts " + str(card_visits))
	kata_service.send_command("kata-set-param maxVisits " + str(card_visits))
	kata_service.send_command("kata-set-param chosenMoveTemperature 0.0")
	
	# 使用高稳定的 lz-analyze
	var p_color_str = "b" if player_color == 1 else "w"
	kata_service.request_analysis_color(show_territory_map, p_color_str)
func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_ai_thinking or current_turn == 2 or is_game_over:
			return
			
		var grid_pos = get_grid_position(get_local_mouse_position())
		if grid_pos.x >= 0 and grid_pos.x < board_size and grid_pos.y >= 0 and grid_pos.y < board_size:
			if is_manual_mode:
				if board_state[grid_pos.x][grid_pos.y] == 0:
					# 【核心修改】：使用玩家实际选择的执子颜色 player_color
					if try_place_stone(grid_pos.x, grid_pos.y, player_color): 
						move_history.append(grid_pos)
						kata_service.send_command("stop")
						active_candidates.clear()
						pending_candidates.clear()
						queue_redraw()
						
						# 同步落子给 KataGo（动态判断颜色字符串）
						var p_color_name = "black" if player_color == 1 else "white"
						var gtp_move = grid_to_gtp(grid_pos.x, grid_pos.y)
						kata_service.send_command("play " + p_color_name + " " + gtp_move)
						
						switch_to_ai_turn()
					else:
						print("非法落子：此处为禁着自杀点！")
				return
			
			if active_card_index == -1:
				print("请先从下方选择一张棋手卡牌！")
				return
				
			var clicked_candidate = null
			for cand in active_candidates:
				if cand["pos"] == grid_pos:
					clicked_candidate = cand
					break
					
			if clicked_candidate != null:
				# 【核心修改】：使用玩家实际选择的执子颜色 player_color
				if try_place_stone(grid_pos.x, grid_pos.y, player_color): 
					move_history.append(grid_pos)
					kata_service.send_command("stop")
					active_candidates.clear()
					pending_candidates.clear()
					queue_redraw()
					active_card_index = -1
					
					# 同步落子给 KataGo
					var p_color_name = "black" if player_color == 1 else "white"
					var gtp_move = grid_to_gtp(grid_pos.x, grid_pos.y)
					kata_service.send_command("play " + p_color_name + " " + gtp_move)
					
					switch_to_ai_turn()
				else:
					if grid_pos.x >= 0 and grid_pos.x < board_size and grid_pos.y >= 0 and grid_pos.y < board_size:
						
						print("无效点击：只能下在绿色推荐候选点上！")
func get_group_and_liberties(start_x: int, start_y: int) -> Dictionary:
	var target_color = board_state[start_x][start_y]
	if target_color == 0:
		return {"group": [], "liberties": []}
	var group = []
	var liberties = []
	var queue = [Vector2i(start_x, start_y)]
	var visited = {}
	while queue.size() > 0:
		var current = queue.pop_front()
		if visited.has(current):
			continue
		visited[current] = true
		group.append(current)
		var neighbors = [current + Vector2i.UP, current + Vector2i.DOWN, current + Vector2i.LEFT, current + Vector2i.RIGHT]
		for neighbor in neighbors:
			if neighbor.x >= 0 and neighbor.x < board_size and neighbor.y >= 0 and neighbor.y < board_size:
				var neighbor_color = board_state[neighbor.x][neighbor.y]
				if neighbor_color == target_color:
					if not visited.has(neighbor) and not neighbor in queue:
						queue.append(neighbor)
				elif neighbor_color == 0:
					if not neighbor in liberties:
						liberties.append(neighbor)
	return {"group": group, "liberties": liberties}

func try_place_stone(x: int, y: int, color: int) -> bool:
	board_state[x][y] = color
	var opponent_color = 2 if color == 1 else 1
	var captured_any = false
	var stones_to_remove = []
	var neighbors = [Vector2i(x, y) + Vector2i.UP, Vector2i(x, y) + Vector2i.DOWN, Vector2i(x, y) + Vector2i.LEFT, Vector2i(x, y) + Vector2i.RIGHT]
	for neighbor in neighbors:
		if neighbor.x >= 0 and neighbor.x < board_size and neighbor.y >= 0 and neighbor.y < board_size:
			if board_state[neighbor.x][neighbor.y] == opponent_color:
				var result = get_group_and_liberties(neighbor.x, neighbor.y)
				if result["liberties"].size() == 0:
					for stone in result["group"]:
						if not stone in stones_to_remove:
							stones_to_remove.append(stone)
					captured_any = true
	for stone in stones_to_remove:
		board_state[stone.x][stone.y] = 0
		if opponent_color == 1:
			black_captured += 1 # AI白棋提掉了玩家黑子
		else:
			white_captured += 1 # 玩家黑棋提掉了AI白子
	if not captured_any:
		var own_result = get_group_and_liberties(x, y)
		if own_result["liberties"].size() == 0:
			board_state[x][y] = 0
			return false
	return true
# 1. 终局处理函数
func trigger_game_over():
	is_game_over = true
	is_ai_thinking = true
	
	for btn in hand_ui.get_children():
		if btn is Button:
			btn.disabled = true
	if $CanvasLayer.has_node("PassBtn"):
		$CanvasLayer/PassBtn.disabled = true
	update_status_label("对局双 Pass 结束，KataGo 正在精准数子判定中...")
	
	# 【核心改动】：让 KataGo 裁判进行数子，结果会触发 _on_kata_score_ready 信号
	kata_service.send_command("final_score")

# 2. 核心数子算法 (中国规则简化版)
func calculate_final_score() -> Dictionary:
	var black_stones = 0
	var white_stones = 0
	var black_territory = 0
	var white_territory = 0
	
	# 先数棋盘上的活子
	for x in range(board_size):
		for y in range(board_size):
			if board_state[x][y] == 1:
				black_stones += 1
			elif board_state[x][y] == 2:
				white_stones += 1
				
	# 通过染色算法（Flood Fill）计算空白区域归属
	var visited = {}
	for x in range(board_size):
		for y in range(board_size):
			if board_state[x][y] == 0 and not visited.has(Vector2i(x, y)):
				var region = flood_fill_territory(x, y, visited)
				
				# 检查这片空白区域边界上的棋子颜色
				var has_black_border = region["borders"].has(1)
				var has_white_border = region["borders"].has(2)
				
				# 如果只挨着黑子，判定为黑棋地盘
				if has_black_border and not has_white_border:
					black_territory += region["size"]
				# 如果只挨着白子，判定为白棋地盘
				elif has_white_border and not has_black_border:
					white_territory += region["size"]
				# 如果都挨着（公气），不给分

	var total_black = float(black_stones + black_territory)
	var total_white = float(white_stones + white_territory) + komi
	
	var winner = 1 if total_black > total_white else 2
	
	return {
		"black_stones": black_stones,
		"black_territory": black_territory,
		"total_black": total_black,
		"white_stones": white_stones,
		"white_territory": white_territory,
		"total_white": total_white,
		"winner": winner
	}

# 3. 染色辅助函数：收集相连的空地并记录它的边界棋子颜色
func flood_fill_territory(start_x: int, start_y: int, visited: Dictionary) -> Dictionary:
	var queue = [Vector2i(start_x, start_y)]
	var region_size = 0
	var borders = {} # 用字典的键来当做 Set 避免重复记录边界颜色

	while queue.size() > 0:
		var current = queue.pop_front()
		if visited.has(current):
			continue
		visited[current] = true
		region_size += 1

		var neighbors = [
			current + Vector2i.UP,
			current + Vector2i.DOWN,
			current + Vector2i.LEFT,
			current + Vector2i.RIGHT
		]

		for neighbor in neighbors:
			if neighbor.x >= 0 and neighbor.x < board_size and neighbor.y >= 0 and neighbor.y < board_size:
				var color = board_state[neighbor.x][neighbor.y]
				if color == 0:
					if not visited.has(neighbor) and not neighbor in queue:
						queue.append(neighbor)
				else:
					borders[color] = true # 记录边界上遇到的棋子颜色

	return {
		"size": region_size,
		"borders": borders.keys()
	}
func _on_kata_candidates_ready(candidates: Array):
	
	var msec_since_click = Time.get_ticks_msec() - last_card_select_time
	# 只要少于 150ms，且不是 AI 回合，绝对是上一回合还没排空的残留垃圾，直接强行丢弃！
	if msec_since_click < 150 and not waiting_for_ai_analysis:
		return
	if (current_turn == 2 and not waiting_for_ai_analysis) or (current_turn == 1 and active_card_index == -1):
		return

	if waiting_for_ai_analysis:
		waiting_for_ai_analysis = false
		kata_service.send_command("stop")
		var ai_move = select_katrain_ai_move(candidates)
		_execute_ai_move(ai_move)
		return
	if has_sent_llm_this_turn:
		return
	pending_candidates.clear()
	var shuffled = candidates.duplicate()
	shuffled.shuffle()
	current_candidates_data = shuffled
	
	var card_name = "神秘棋手"
	if active_card_index != -1:
		var card_node = hand_ui.get_child(active_card_index)
		if card_node and card_node.card_data:
			card_name = card_node.card_data.card_name
				
	var option_labels = ["A", "B", "C"]
	var candidate_list_text = ""
	for i in range(shuffled.size()):
		var cand = shuffled[i]
		var grid_pos = gtp_to_grid(cand["move"])
		if grid_pos.x >= 0 and board_state[grid_pos.x][grid_pos.y] == 0:
			var label = option_labels[i]
			pending_candidates.append({
				"pos": grid_pos,
				"color": Color(0.85, 0.65, 0.15), # 统一古铜金
				"num_str": label,
				"winrate": cand["winrate"],
				"move": cand["move"],
				"pv": cand["pv"]
			})
			var tactical_info = get_grid_tactical_info(grid_pos)
			candidate_list_text += "选项 %s: 坐标 %s (%s) (预估胜率: %.1f%%, 后续变化: %s)\n" % [
				label, cand["move"], tactical_info, cand["winrate"] * 100.0, ", ".join(cand["pv"].slice(0, 4))
			]
			
	if not enable_llm_card:
		_fallback_offline_explanation()
		return
			
	has_sent_llm_this_turn = true
	if explanation_box:
		explanation_box.text = "[font_size=18][b]💡 " + tr("DIALOG_GENERATING_TITLE") + "[/b][/font_size]\n\n[color=gray]" + (tr("DIALOG_GENERATING_DESC") % card_name) + "[/color]"
	
	# 【核心修复】：修正了 JSON 结构体中 B 和 C 字母的拼写错误
	var current_lang_name = "中文 (Chinese)" if ConfigManager.locale_code == "zh" else "英文 (English)"
	var system_prompt = "你是一位擅长围棋入门教育的专业成人围棋教师。请根据玩家提供和描述的当前盘面布局，对推荐的 A、B、C 三个落子点进行精准、客观的战术剖析。必须严格以给出的物理和战术事实为准，使用正规的围棋术语。绝对不要提到任何‘胜率’或百分比数值，纯粹从棋理、攻防和棋形角度进行剖析。必须严格以 JSON 格式输出，结构为: {\"A\": \"点评A\", \"B\": \"点评B\", \"C\": \"点评C\"}。每条点评字数必须严格控制在 100 字以内，使用大白话、用初学者可以理解的语言。最重要的是：【必须且只能使用 %s 语言撰写所有的 JSON 解析文本内容】！" % [current_lang_name]
	
	var board_grid = get_board_text_grid()
	var black_label = "我方黑棋" if player_color == 1 else "敌方黑棋"
	var white_label = "敌方白棋" if player_color == 1 else "我方白棋"
	var my_color_name = "黑棋" if player_color == 1 else "白棋"
	

	var user_prompt = "【当前全盘棋子物理分布图】(字符 X 代表 %s，字符 O 代表 %s，字符 . 代表空格交叉点):\n" % [black_label, white_label]
	user_prompt += board_grid + "\n"
	user_prompt += "当前轮到我执 %s 落子，请评估以下三个选项并给出你的专业棋理解释：\n" % my_color_name
	user_prompt += candidate_list_text
	
	send_llm_request(system_prompt, user_prompt, true)
func gtp_to_grid(gtp_move: String) -> Vector2i:
	var col_str = gtp_move.substr(0, 1).to_upper()
	var row_str = gtp_move.substr(1)
	
	var x = COLUMNS_X.find(col_str)
	# 围棋坐标 y 从下往上数（1在最下面），而我们的像素网格 y 从上往下数（0在最上面）
	var y = board_size - int(row_str) 
	
	return Vector2i(x, y)
func grid_to_gtp(x: int, y: int) -> String:
	var col = COLUMNS_X[x]
	var row = str(board_size - y)
	return col + row


func send_llm_request(system_content: String, user_content: String, require_json: bool = true):
	if http_request and http_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		http_request.cancel_request()

	# ==== 【核心改动】：动态、安全地从全局管理器中读取配置 ====
	var api_key = ConfigManager.ai_api_key
	var api_url = ConfigManager.ai_api_url
	var api_model = ConfigManager.ai_model

	# 只要未配置 Key，直接优雅降级为本地离线点评，绝不卡死
	if api_key == "":
		_fallback_offline_explanation()
		return

	var headers = [
		"Content-Type: application/json", 
		"Authorization: Bearer " + api_key
	]
	
	var payload = {
		"model": api_model,
		"messages": [
			{"role": "system", "content": system_content},
			{"role": "user", "content": user_content}
		],
		"temperature": 0.7,
		"max_tokens": 300 
	}
	if require_json:
		payload["response_format"] = {"type": "json_object"}
	
	var err = http_request.request(api_url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		_fallback_offline_explanation()
# 【替换 go_board.gd 中的该函数：加入绝对防崩防卡死安全验证】
func _on_llm_request_completed(_result, response_code, _headers, body):
	if response_code == 200:
		var response_text = body.get_string_from_utf8()
		var json = JSON.parse_string(response_text)
		
		if json and json.has("choices"):
			var raw_content = json["choices"][0]["message"]["content"]
			print("[LLM 原创评语] ", raw_content)
			
			var parsed_commentary = JSON.parse_string(raw_content)
			if parsed_commentary:
				render_llm_commentary(parsed_commentary)
				return
				
	print("LLM 请求失败，状态码: ", response_code)
	_fallback_offline_explanation()
func render_llm_commentary(comments: Dictionary):
	last_llm_comments = comments
	
	var dialog_text = "[font_size=18][b]" + tr("DIALOG_HEADER") + "[/b][/font_size]\n\n"
	var option_labels = ["A", "B", "C"]
	
	for i in range(current_candidates_data.size()):
		var cand = current_candidates_data[i]
		var label = option_labels[i]
		var comment = comments.get(label, tr("FALLBACK_COMMENT"))
		
		# 动态过滤：即使开启胜率，由于打乱了顺序，也极其有趣
		if show_winrate:
			dialog_text += tr("DIALOG_OPTION_WINRATE") % [
				label, cand["move"], cand["winrate"] * 100.0
			]
		else:
			dialog_text += tr("DIALOG_OPTION") % [label, cand["move"]]
			
		dialog_text += "[color=orange]%s[/color]\n\n" % comment
		
	active_candidates = pending_candidates.duplicate()
	queue_redraw()
	
	
	if explanation_box:
		explanation_box.text = dialog_text
func _fallback_offline_explanation():
	# 彻底去掉繁琐的离线大白话文字，只保留一个精简、不遮挡视线的提示
	if explanation_box:
		explanation_box.text = "[font_size=18][b]💡 卡牌推荐已亮起[/b][/font_size]\n\n[color=gray]已为你计算并推荐最强落子选项，请在棋盘上选择 A、B 或 C 字母进行落子对局。[/color]"
		
	# 依然在棋盘上亮起 A, B, C 判定圈
	active_candidates = pending_candidates.duplicate()
	queue_redraw()
func get_empty_spaces_count() -> int:
	var count = 0
	for x in range(board_size):
		for y in range(board_size):
			if board_state[x][y] == 0:
				count += 1
	return count
# 【新增于 go_board.gd 脚本最末尾：战术特征计算器】
func get_grid_tactical_info(pos: Vector2i) -> String:
	# 1. 【核心自愈修复】：用数学公式在本地算出绝对精确的物理象限，彻底纠正大模型 Y 轴颠倒的本能错误！
	# pos.y = 0 代表最上方 (13路)，pos.y = 12 代表最下方 (1路)
	var horiz = "左" if pos.x < float(board_size) / 2.0 else "右"
	var vert = "上" if pos.y < float(board_size) / 2.0 else "下"
	var quadrant = horiz + vert + "角区域"
	
	if pos.x == int(board_size / 2.0) and pos.y == int(board_size / 2.0):
		quadrant = "天元 (中心点)"

	# 2. 计算高低位属性
	var loc = ""
	if board_size == 9:
		if pos.x in [3, 4, 5] and pos.y in [3, 4, 5]: loc = "中腹天元要冲"
		elif pos.x in [0, 1, 7, 8] and pos.y in [0, 1, 7, 8]: loc = "角部要地"
		else: loc = "边线"
	elif board_size == 13:
		if pos.x in [4, 5, 6, 7, 8] and pos.y in [4, 5, 6, 7, 8]: loc = "中腹天元要冲"
		elif pos.x in [0, 1, 2, 10, 11, 12] and pos.y in [0, 1, 2, 10, 11, 12]: loc = "角部要地"
		else: loc = "边线"
	elif board_size == 19:
		# 19路棋盘标准大局观划分
		if pos.x in [7, 8, 9, 10, 11] and pos.y in [7, 8, 9, 10, 11]: loc = "中腹天元要冲"
		elif (pos.x <= 4 or pos.x >= 14) and (pos.y <= 4 or pos.y >= 14): loc = "角部要地"
		else: loc = "边线"
		
	var relation = "落子在空旷地带，意在抢占大场"
	
	# 局部检查上下左右邻居颜色
	var neighbors = [pos + Vector2i.UP, pos + Vector2i.DOWN, pos + Vector2i.LEFT, pos + Vector2i.RIGHT]
	var has_my_stone = false
	var has_opp_stone = false
	
	for n in neighbors:
		if n.x >= 0 and n.x < board_size and n.y >= 0 and n.y < board_size:
			var color = board_state[n.x][n.y]
			if color == 1: has_my_stone = true
			elif color == 2: has_opp_stone = true
			
	if has_opp_stone:
		relation = "直接贴着敌方棋子，属于贴身肉搏、分断、发起纠缠的走法"
	elif has_my_stone:
		relation = "紧贴着我方已有棋子，属于补强、防守、连接或安全长气的稳健走法"
		
	# 返回时把我们算好的【绝对物理方位】塞给它
	return "物理方位: %s (%s)，战术关系: %s" % [quadrant, loc, relation]
func select_katrain_ai_move(candidates: Array) -> String:
	if candidates.size() == 0:
		return "pass"
	if candidates[0]["winrate"] < 0.02:
		print("[KataGo Native] 投子认输：AI 胜率仅 %.2f%%，选择 Pass 终局。" % (candidates[0]["winrate"] * 100.0))
		return "pass"
	candidates.sort_custom(func(a, b): return a["winrate"] > b["winrate"])
	if candidates[0]["move"].to_lower() == "pass":
		print("[KataGo Native] 终局判定：第一候选点为 pass，AI 决定无条件同意终局。")
		return "pass"
	# 根据 9 级段位进行最自然的拟人选子
	var index = 0
	if ai_difficulty == "20k":
		index = min(4, candidates.size() - 1) # 20k 故意乱选极其偏后的缓着
	elif ai_difficulty == "15k":
		index = min(3, candidates.size() - 1)
	elif ai_difficulty == "10k":
		index = min(2, candidates.size() - 1)
	elif ai_difficulty == "5k":
		index = min(1, candidates.size() - 1)
	elif ai_difficulty == "1k":
		index = 0
		if candidates.size() > 1 and randf() < 0.6: index = 1 # 有 60% 概率走次选好棋
	elif ai_difficulty == "1d":
		index = 0
		if candidates.size() > 1 and randf() < 0.3: index = 1 # 有 30% 概率走次选
	else:
		index = 0 # 3d, 5d, 9d 顶级高手直接选取第一妙手
		
	var chosen = candidates[index]
	print("[KataGo Native] AI落子决策：当前段位 %s | 坐标 %s" % [ai_difficulty, chosen["move"]])
	return chosen["move"]
func _execute_ai_move(gtp_move: String):
	if gtp_move.to_lower() == "pass":
		print("AI 选择 Pass")
		consecutive_passes += 1
		if consecutive_passes >= 2:
			trigger_game_over()
			return
	else:
		var grid_pos = gtp_to_grid(gtp_move)
		if try_place_stone(grid_pos.x, grid_pos.y, ai_color): 
			consecutive_passes = 0
			# 同步落子给 KataGo
			var ai_color_name = "black" if ai_color == 1 else "white"
			kata_service.send_command("play " + ai_color_name + " " + gtp_move)
		else:
			print("错误：AI 走了一步非法棋！", gtp_move)
			
	# ==================== 【核心安全清理】 ====================
	# AI 落子完毕，清空任何残留的候选圈，保证回到玩家回合时，新一轮推荐未出来前棋盘绝对干净
	active_candidates.clear()
	pending_candidates.clear()
	# =========================================================
			
	# 归还回合给玩家
	current_turn = 1
	is_ai_thinking = false
	update_status_label("你的回合，请选择卡牌落子")
	if $CanvasLayer.has_node("PassBtn"):
		$CanvasLayer/PassBtn.disabled = false
	refill_hand()
	queue_redraw()
func _on_kata_score_ready(score_text: String):
	ConfigManager.active_match_exists = false
	ConfigManager.save_game()
	var winner_desc = ""
	var clean_score = score_text.replace("=", "").strip_edges() # 过滤干净
	
	if clean_score.begins_with("B+"):
		var pts = clean_score.replace("B+", "")
		winner_desc = "黑棋获胜！领先 %s 目/子" % pts
	elif clean_score.begins_with("W+"):
		var pts = clean_score.replace("W+", "")
		winner_desc = "白棋获胜！领先 %s 目/子" % pts
	else:
		winner_desc = "双方平局 (和棋)！"
		
	var summary = "【对局结束 - KataGo 精准数子完成】\n\n"
	summary += "最终判子结果：%s\n" % clean_score
	summary += "胜负结果：%s" % winner_desc
	
	update_status_label(summary)
	
	
	if explanation_box:
		explanation_box.text = summary
	check_tournament_victory(1 if (clean_score.begins_with("B+") and player_color == 1) or (clean_score.begins_with("W+") and player_color == 2) else 2)

func calculate_offline_influence():
	board_ownership.clear()
	# 1. 初始化势力矩阵为 0.0
	for i in range(board_size * board_size):
		board_ownership.append(0.0)
		
	# 2. 遍历棋盘上所有的棋子，向周围格辐射势力
	for x in range(board_size):
		for y in range(board_state[x].size() if board_state.size() > x else 0):
			var stone = board_state[x][y]
			if stone != 0:
				var is_black = (stone == 1)
				var strength = 1.0 if is_black else -1.0 # 黑棋 +1，白棋 -1
				
				# 将势力辐射到距离为 3 步以内的所有格子（曼哈顿距离）
				for tx in range(board_size):
					for ty in range(board_size):
						var dist = abs(tx - x) + abs(ty - y)
						if dist <= 3: # 辐射范围：3步
							var idx = ty * board_size + tx
							# 势力衰减公式：1 / (2^距离)
							var decay = 1.0 / pow(2.0, dist)
							board_ownership[idx] += strength * decay
							
	# 3. 将结果值锁死在 -1.0 到 1.0 之间
	for i in range(board_ownership.size()):
		board_ownership[i] = clamp(board_ownership[i], -1.0, 1.0)
func _process(delta: float):
	# 只有当棋盘初始化完毕，且游戏未结束时，才累计计时并更新常驻面板
	if not is_game_over and board_state.size() >= board_size:
		game_time_elapsed += delta
		update_info_panel()

# 【新增于 go_board.gd 最末尾：高精度格式化刷新 HUD 数据】
func update_info_panel():
	if info_label:
		# 格式化用时为 分:秒
		var minutes = int(game_time_elapsed) / 60.0
		var seconds = int(game_time_elapsed) % 60
		var time_str = "%02d:%02d" % [minutes, seconds]
		
		var bbcode = "" 
		bbcode += (tr("HUD_KOMI") % str(komi)) + "    "
		bbcode += (tr("HUD_BLACK_CAP") % white_captured) + "    "
		bbcode += (tr("HUD_WHITE_CAP") % black_captured) + "    "
		bbcode += (tr("HUD_TIME") % time_str)
		
		
		
		info_label.text = bbcode
# 【替换 go_board.gd 中的该对局结算检测函数：实现双模式赢棋夺卡】
func check_tournament_victory(winner_color: int):
	# 获取当前对战对手的名字
	var defeated_enemy = ConfigManager.tournament_opponent
	
	if winner_color == 1: # 玩家（黑棋）赢了！
		# 【核心新增】：无论是快速游戏还是锦标赛，只要赢了，无条件永久收服解锁卡牌！
		if not defeated_enemy in ConfigManager.unlocked_cards:
			ConfigManager.unlocked_cards.append(defeated_enemy)
			print("战胜对手，解锁卡牌: ", defeated_enemy)
			
		# 如果是锦标赛
		if ConfigManager.tournament_active:
			if ConfigManager.current_deck.size() < 20:
				ConfigManager.current_deck.append(defeated_enemy)
				
			var current_round_players = ConfigManager.tournament_tree[ConfigManager.tournament_round - 1]
			if current_round_players.size() == 2:
				ConfigManager.tournament_active = false
				ConfigManager.save_game()
				update_status_label("恭喜！！！你已斩获本届锦标赛【总冠军】！")
				explanation_box.text = "已获得冠军！3 秒后自动返回主大厅。"
				await get_tree().create_timer(3.0).timeout
				get_tree().change_scene_to_file("res://ModeSelection.tscn")
				return
				
			ConfigManager.simulate_ai_matches()
			ConfigManager.tournament_round += 1
			
			var next_round_roster = ConfigManager.tournament_tree[ConfigManager.tournament_round - 1]
			var my_idx = next_round_roster.find(ConfigManager.tournament_character)
			var opp_idx = my_idx - 1 if my_idx % 2 == 1 else my_idx + 1
			ConfigManager.tournament_opponent = next_round_roster[opp_idx]
			
			ConfigManager.save_game()
			update_status_label("胜利！获得卡牌 [%s]！3 秒后自动带你返回对阵图查看下一轮..." % defeated_enemy)
			await get_tree().create_timer(3.0).timeout
			get_tree().change_scene_to_file("res://TournamentSetup.tscn")
		else:
			# 如果是快速游戏赢了
			ConfigManager.save_game()
			update_status_label("对局大胜！获得卡牌：[%s]！3秒后自动退回大厅。" % defeated_enemy)
			await get_tree().create_timer(3.0).timeout
			get_tree().change_scene_to_file("res://ModeSelection.tscn")
		
	else: # 玩家输了！
		if ConfigManager.tournament_active:
			ConfigManager.tournament_active = false
			ConfigManager.save_game()
			update_status_label("遗憾战败！你的锦标赛宣告止步。3 秒后带你退回到主界面...")
			await get_tree().create_timer(3.0).timeout
			get_tree().change_scene_to_file("res://main_menu.tscn")
		else:
			# 快速游戏输了
			update_status_label("对局落败！3秒后退回大厅，请重整旗鼓再次挑战！")
			await get_tree().create_timer(3.0).timeout
			get_tree().change_scene_to_file("res://ModeSelection.tscn")
# 【新增于 go_board.gd 最末尾：点击退出时的弹窗询问逻辑】
func _on_exit_pressed():
	# 如果对局已经正常结束，直接带玩家秒回大厅，不需要弹窗
	if is_game_over:
		get_tree().change_scene_to_file("res://ModeSelection.tscn")
		return
		
	# 如果当前已有退出弹窗，防止重复生成
	if $CanvasLayer.has_node("ExitConfirm"):
		return
		
	# 【核心修复】：直接实例化你在编辑器里拉好的高颜值 ExitConfirm.tscn 场景并覆盖显示！
	var exit_scene = load("res://ExitConfirm.tscn")
	var exit_inst = exit_scene.instantiate()
	$CanvasLayer.add_child(exit_inst)
func save_active_match():
	ConfigManager.active_match_exists = true
	ConfigManager.saved_match_mode = "tournament" if ConfigManager.tournament_active else "quick"
	ConfigManager.saved_board_size = board_size
	ConfigManager.saved_board_state = board_state.duplicate(true) # 深度拷贝二维矩阵
	ConfigManager.saved_move_history = move_history.duplicate()
	ConfigManager.saved_komi = komi
	ConfigManager.saved_black_captured = black_captured
	ConfigManager.saved_white_captured = white_captured
	ConfigManager.saved_game_time_elapsed = game_time_elapsed
	ConfigManager.saved_current_turn = current_turn
	ConfigManager.saved_difficulty = ai_difficulty
	ConfigManager.saved_style = ai_style
	
	# 提取并保存当前手中 3 张手牌的绝对资源路径 (.tres)，以便完美复原
	var cards_paths = []
	for child in hand_ui.get_children():
		if child.get("card_data") and child.card_data:
			cards_paths.append(child.card_data.resource_path)
	ConfigManager.saved_hand_cards = cards_paths
	
	ConfigManager.save_game()
	
# 【新增于 go_board.gd 最末尾：核心对局数据快照重组复原算法】
func load_active_match():
	if $CanvasLayer.has_node("SetupMenuMask"):
		$CanvasLayer/SetupMenuMask.queue_free()
	ConfigManager.is_resuming_match = false # 消费掉标记
	
	# 1. 恢复所有局中数据
	board_size = ConfigManager.saved_board_size
	board_state = ConfigManager.saved_board_state.duplicate(true)
	move_history = ConfigManager.saved_move_history.duplicate()
	komi = ConfigManager.saved_komi
	black_captured = ConfigManager.saved_black_captured
	white_captured = ConfigManager.saved_white_captured
	game_time_elapsed = ConfigManager.saved_game_time_elapsed
	current_turn = ConfigManager.saved_current_turn
	ai_difficulty = ConfigManager.saved_difficulty
	ai_style = ConfigManager.saved_style
	
	# 自适应参数初始化
	setup_game_parameters(board_size)
	
	# 2. 完美重塑手牌区
	for child in hand_ui.get_children():
		child.queue_free()
		
	for i in range(ConfigManager.saved_hand_cards.size()):
		var path = ConfigManager.saved_hand_cards[i]
		if ResourceLoader.exists(path):
			var card_scene = load("res://Card.tscn")
			var card_instance = card_scene.instantiate()
			card_instance.card_data = load(path)
			card_instance.pressed.connect(_on_card_selected.bind({}, i, card_instance))
			hand_ui.add_child(card_instance)
			
	# 3. 唤醒 KataGo 并恢复局中状态
	update_status_label("正在为您复原 KataGo 战场逻辑...")
	var success = kata_service.start_katago_dynamic(board_size, komi)
	if success:
		# 强制把全盘所有历史子，按照顺序一步一步拍在 KataGo 的脑袋里，让它的后台棋盘彻底复原！
		for i in range(move_history.size()):
			var pos = move_history[i]
			# 依靠顺序判定是黑还是白拍给 AI
			var color_str = "black" if (i % 2 == 0) else "white"
			kata_service.send_command("play " + color_str + " " + grid_to_gtp(pos.x, pos.y))
			
		update_status_label("局势复原完成！当前级别: %s" % ai_difficulty)
		hand_ui.visible = true
		$CanvasLayer/UtilityBar.visible = true
		
		# 4. 回合衔接：如果是轮到 AI 走，唤醒 AI 的思考
		if current_turn == 2:
			switch_to_ai_turn()
	else:
		update_status_label("大脑复原失败")
	queue_redraw()
func get_board_text_grid() -> String:
	var grid_str = ""
	for y in range(board_size):
		var row_str = ""
		for x in range(board_size):
			var val = board_state[x][y]
			if val == 1: row_str += "X " # 黑子
			elif val == 2: row_str += "O " # 白子
			else: row_str += ". " # 空
		grid_str += row_str.strip_edges() + "\n"
	return grid_str
