extends Node
var locale_code: String = "zh" # 语言代码，默认 "zh"（中文），"en"（英文）
const SAVE_PATH = "user://game_save.cfg"
# ===== 新增于 ConfigManager.gd 变量区 =====
var tournament_board_size: int = 19     # 锦标赛玩家选择的棋盘大小
var tournament_komi: float = 7.5       # 锦标赛对应的贴目值
# 玩家存档数据
const ENCRYPTION_KEY = "Go_Grandmaster_Secure_Key_2026_AES" # 物理加密口令
var unlocked_cards: Array = ["战鹰"] # 初始只解锁战鹰
var current_deck: Array = ["战鹰"]
var saved_match_mode: String = "quick"  # 标记：存档是 "quick" 还是 "tournament"
# ===== 新增于 ConfigManager.gd 变量区 =====
var tournament_active: bool = false     # 锦标赛是否激活
var tournament_round: int = 0           # 当前轮次 (1=16强/首轮，2=8强，3=半决赛，4=决赛)
var tournament_size: int = 16            # 参赛总人数 (16, 32, 64)
var tournament_opponent: String = ""     # 当前轮次对手的名字
var tournament_character: String = ""    # 玩家在锦标赛中选用的出战棋手
# 设置数据
var sound_volume: float = 1.0
var music_volume: float = 1.0
var ai_api_key: String = ""
var ai_api_url: String = "https://api.deepseek.com/v1/chat/completions"
var ai_model: String = "deepseek-chat"
# ===== 新增于 ConfigManager.gd 变量区 =====
var active_match_exists: bool = false   # 是否存在未完结的对局存档
var is_resuming_match: bool = false     # 运行时标记：本次进入游戏是否是为了恢复存档
var window_mode_idx: int = 0            # 屏幕模式：0=窗口，1=无边框，2=全屏
# 以下为具体的对局快照数据
var saved_board_size: int = 9
var saved_board_state: Array = []
var saved_move_history: Array = []
var saved_komi: float = 7.5
var saved_black_captured: int = 0
var saved_white_captured: int = 0
var saved_game_time_elapsed: float = 0.0
var saved_current_turn: int = 1
var saved_difficulty: String = "5k"
var saved_style: String = "balanced"
var saved_hand_cards: Array = []     

var tournament_tree: Array = []
func _ready():
	load_game()

func save_game():
	var config = ConfigFile.new()
	# 玩家基本数据
	config.set_value("settings", "window_mode", window_mode_idx)
	config.set_value("player", "unlocked_cards", unlocked_cards)
	config.set_value("player", "current_deck", current_deck)
	config.set_value("settings", "locale", locale_code)
	# 锦标赛数据
	config.set_value("tournament", "active", tournament_active)
	config.set_value("tournament", "round", tournament_round)
	config.set_value("tournament", "size", tournament_size)
	config.set_value("tournament", "opponent", tournament_opponent)
	config.set_value("tournament", "character", tournament_character)
	config.set_value("tournament", "tree", tournament_tree)
	config.set_value("tournament", "board_size", tournament_board_size)
	config.set_value("tournament", "komi", tournament_komi)
	
	# 【核心安全写入】：局中快照
	config.set_value("match", "exists", active_match_exists)
	config.set_value("match", "board_size", saved_board_size)
	config.set_value("match", "board_state", saved_board_state)
	config.set_value("match", "move_history", saved_move_history)
	config.set_value("match", "komi", saved_komi)
	config.set_value("match", "black_captured", saved_black_captured)
	config.set_value("match", "white_captured", saved_white_captured)
	config.set_value("match", "time_elapsed", saved_game_time_elapsed)
	config.set_value("match", "current_turn", saved_current_turn)
	config.set_value("match", "difficulty", saved_difficulty)
	config.set_value("match", "style", saved_style)
	config.set_value("match", "hand_cards", saved_hand_cards)
	
	# 系统设置
	config.set_value("settings", "sound", sound_volume)
	config.set_value("settings", "music", music_volume)
	config.set_value("settings", "api_key", ai_api_key)
	config.set_value("settings", "api_url", ai_api_url)
	config.set_value("settings", "model", ai_model)
	
	config.save_encrypted_pass(SAVE_PATH, ENCRYPTION_KEY)
	print("[存档系统] 物理存档加密写入成功。")
func load_game():
	var config = ConfigFile.new()
	if not FileAccess.file_exists(SAVE_PATH):
		unlocked_cards = ["战鹰"]
		current_deck = ["战鹰"]
		print("[存档系统] 未检测到本地文件，已自动初始化新玩家数据。")
		return
	var err = config.load_encrypted_pass(SAVE_PATH, ENCRYPTION_KEY)
	if err != OK:
		# 兼容：如果解密失败，尝试进行明文普通读取（兼容旧档）
		err = config.load(SAVE_PATH)
	if err == OK:
		locale_code = config.get_value("settings", "locale", "zh")
		TranslationServer.set_locale(locale_code) # 一开机，自动把全盘文本翻译为玩家上次设置的语言
		window_mode_idx = config.get_value("settings", "window_mode", 0)
		apply_window_mode(window_mode_idx) # 游戏启动时，自动渲染为上一次保存的屏幕比例
		unlocked_cards = config.get_value("player", "unlocked_cards", ["柯洁", "战鹰", "常昊"])
		current_deck = config.get_value("player", "current_deck", ["柯洁", "战鹰", "常昊"])
		
		tournament_active = config.get_value("tournament", "active", false)
		tournament_round = config.get_value("tournament", "round", 0)
		tournament_size = config.get_value("tournament", "size", 16)
		tournament_opponent = config.get_value("tournament", "opponent", "")
		tournament_character = config.get_value("tournament", "character", "")
		tournament_tree = config.get_value("tournament", "tree", [])
		tournament_board_size = config.get_value("tournament", "board_size", 19)
		tournament_komi = config.get_value("tournament", "komi", 7.5)
		
		# 【核心安全读取】：读取局中快照
		active_match_exists = config.get_value("match", "exists", false)
		saved_board_size = config.get_value("match", "board_size", 9)
		saved_board_state = config.get_value("match", "board_state", [])
		saved_move_history = config.get_value("match", "move_history", [])
		saved_komi = config.get_value("match", "komi", 7.5)
		saved_black_captured = config.get_value("match", "black_captured", 0)
		saved_white_captured = config.get_value("match", "white_captured", 0)
		saved_game_time_elapsed = config.get_value("match", "time_elapsed", 0.0)
		saved_current_turn = config.get_value("match", "current_turn", 1)
		saved_difficulty = config.get_value("match", "difficulty", "5k")
		saved_style = config.get_value("match", "style", "balanced")
		saved_hand_cards = config.get_value("match", "hand_cards", [])
		
		sound_volume = config.get_value("settings", "sound", 1.0)
		music_volume = config.get_value("settings", "music", 1.0)
		ai_api_key = config.get_value("settings", "api_key", "")
		ai_api_url = config.get_value("settings", "api_url", "https://api.deepseek.com/v1/chat/completions")
		ai_model = config.get_value("settings", "model", "deepseek-chat")
		print("[存档系统] 已从硬盘成功载入历史快照。")
	else:
		# 【重要防线】：如果没找到存档文件，必须强制赋予初始状态！
		unlocked_cards = ["战鹰"]
		current_deck = ["战鹰"]
func simulate_ai_matches():
	if tournament_tree.size() == 0: return
	
	var current_round_players = tournament_tree[tournament_round - 1] # 拿到当前轮次活着的选手
	var next_round_players = []
	
	# 两两对决
	for i in range(0, current_round_players.size(), 2):
		var p1 = current_round_players[i]
		var p2 = current_round_players[i+1]
		
		# 如果其中一方是玩家出战的角色，玩家是必胜的（因为玩家是手动下赢了才触发此函数）
		if p1 == tournament_character or p2 == tournament_character:
			next_round_players.append(tournament_character)
		else:
			# 否则，两只 AI 进行基于段位概率的真实碰撞模拟！
			var winner = simulate_single_match(p1, p2)
			next_round_players.append(winner)
			
	# 将诞生的下一轮胜者名单，追加进对阵树中
	tournament_tree.append(next_round_players)

# 拟真对决算法：计算两张卡牌的段位分，算概率碰撞，支持爆冷！
func simulate_single_match(p1_name: String, p2_name: String) -> String:
	var p1_res = load("res://cards/" + p1_name + ".tres")
	var p2_res = load("res://cards/" + p2_name + ".tres")
	
	var p1_power = get_rank_power(p1_res.ai_rank)
	var p2_power = get_rank_power(p2_res.ai_rank)
	
	# 概率公式：胜率 = 己方权重 / (己方权重 + 对方权重)
	var p1_win_chance = float(p1_power) / float(p1_power + p2_power)
	
	if randf() < p1_win_chance:
		return p1_name
	return p2_name

# 将段位文本转化为战斗权重分
func get_rank_power(rank: String) -> int:
	if "9d" in rank: return 120 # 棋圣
	elif "5d" in rank: return 85
	elif "1d" in rank: return 55
	elif "1k" in rank: return 40
	elif "5k" in rank: return 20
	return 10 # 15k
# 【新增于 ConfigManager.gd 脚本最末尾：大厂级自适应 JSON 备份扫盘算法】
func get_all_card_resources() -> Array:
	var list = []
	var cards_list_path = "res://cards_list.json"
	
	# 1. 策略 A：如果在 Godot 编辑器中开发运行，自动扫盘，并实时备份名单到 JSON 中
	if OS.has_feature("editor"):
		var dir = DirAccess.open("res://cards/")
		if dir:
			var file_names = []
			dir.list_dir_begin()
			var file_name = dir.get_next()
			while file_name != "":
				if not dir.current_is_dir():
					if file_name.ends_with(".tres") or file_name.ends_with(".remap"):
						var clean_name = file_name.replace(".remap", "")
						file_names.append(clean_name)
				file_name = dir.get_next()
			
			# 自动将扫描到的 70+ 棋手名单持久化写入 JSON 文件中！
			var file = FileAccess.open(cards_list_path, FileAccess.WRITE)
			if file:
				file.store_string(JSON.stringify(file_names))
				file.close()
				print("[存档自检] 已自动在本地备份 70+ 棋手名单到 JSON。")
				
			# 载入资源
			for f_name in file_names:
				var res = load("res://cards/" + f_name)
				if res is CardData:
					list.append(res)
		return list
		
	# 2. 策略 B：如果在导出的正式包里运行，直接读取备份好的 JSON 清单，100% 绕过扫盘限制，安全载入！
	else:
		print("================== [导出包环境自检开始] ==================")
		# 探雷 1：查看 JSON 文件到底在不在包里？
		var json_exists = FileAccess.file_exists(cards_list_path)
		print("探雷 1: res://cards_list.json 存在吗？ -> ", json_exists)
		
		if json_exists:
			var file = FileAccess.open(cards_list_path, FileAccess.READ)
			if file:
				var content = file.get_as_text()
				file.close()
				print("探雷 2: JSON 文件读取内容成功。内容: ", content)
				
				var file_names = JSON.parse_string(content)
				if file_names is Array:
					print("探雷 3: 准备加载数组中的卡牌...")
					for f_name in file_names:
						# 探雷 4：分别打印每一张卡的加载结果
						print("  -> 正在尝试 load('res://cards/", f_name, "')")
						var res = load("res://cards/" + f_name)
						if res == null:
							print("     [失败] load() 返回了 null。说明文件没打包进来！")
						else:
							print("     [成功] load() 返回了资源。资源类型是否匹配 CardData？ -> ", res is CardData)
							if res is CardData:
								list.append(res)
		
		print("================== [导出包环境自检结束] 成功载入 ", list.size(), " 张卡牌 ==================")
		return list
func apply_window_mode(idx: int):
	window_mode_idx = idx
	if idx == 0:
		# 1. 标准窗口模式 (有边框)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	elif idx == 1:
		# 2. 无边框窗口模式
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	else:
		# 3. 物理全屏模式
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
