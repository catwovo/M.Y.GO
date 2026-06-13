class_name KataService
extends Node

# 定义信号：当解析出推荐候选点时，通知棋盘
# 传递参数格式：candidates = [{"move": "E5", "winrate": 0.52, "score": 0.5}]
signal candidates_ready(candidates: Array)
signal ai_move_ready(move: String)
var process_pid: int = -1
var stdio_pipe: FileAccess = null
var read_thread: Thread = null
var min_required_visits: int = 25 # 思考门槛：只有计算次数达到此值，才允许返回数据并 stop
var should_terminate: bool = false
signal score_ready(score_text: String) # 当 KataGo 精准数子完成时触发
signal ownership_ready(ownership: Array) # 当 KataGo 实时形势掌控数据算出时触发
# 启动 KataGo 子进程与读取线程
# 【替换 kata_service.gd 中的该函数：优先自动匹配人类模仿模型】
# 【替换 kata_service.gd 中的这两个函数：使用真实物理路径，彻底解决导出找不到 bin 报错】
func start_katago() -> bool:
	stop_service()
	print("\n========== [KataService 启动自检] ==========")
	
	# 【核心修复】：根据是在编辑器内还是导出后，智能获取外部真实物理目录
	var base_dir = ""
	if OS.has_feature("editor"):
		# 编辑器环境下，指向项目根目录下的 bin
		base_dir = ProjectSettings.globalize_path("res://bin/")
	else:
		# 导出包环境下，指向游戏 exe 所在真实物理目录下的 bin
		base_dir = OS.get_executable_path().get_base_dir().path_join("bin/")
		
	# 确保末尾有斜杠
	if not base_dir.ends_with("/") and not base_dir.ends_with("\\"):
		base_dir += "/"
		
	var dir = DirAccess.open(base_dir)
	if not dir:
		print("【致命错误】：找不到物理文件夹 '", base_dir, "'！")
		print(">> 请确保导出的 .exe 旁边有一个包含 katago 的 bin/ 文件夹！")
		return false
		
	print("正在扫描物理目录 '", base_dir, "' 下的文件...")
	dir.list_dir_begin()
	var file_name = dir.get_next()
	var found_model = ""
	
	while file_name != "":
		if not dir.current_is_dir():
			print(" -> 发现文件: ", file_name)
			var is_valid_model = file_name.ends_with(".gz") or file_name.ends_with(".bin") or file_name.ends_with(".onnx")
			
			if is_valid_model:
				if "human" in file_name.to_lower():
					found_model = file_name
					print("【自检提示】：发现人类模仿模型，优先加载！")
					break
				elif found_model == "":
					found_model = file_name
		file_name = dir.get_next()
	
	var exe_path = base_dir + "katago.exe"
	var config_path = base_dir + "katago.cfg"
	
	if not FileAccess.file_exists(exe_path):
		print("【致命错误】：找不到主程序 '", exe_path, "'！")
		return false
	if not FileAccess.file_exists(config_path):
		print("【致命错误】：找不到配置文件 '", config_path, "'！")
		return false
		
	if found_model == "":
		print("【致命错误】：在 bin 目录下没有找到任何权重文件 (.gz 或 .bin)。")
		return false
	
	var model_path = base_dir + found_model
	print("【自动匹配权重】：已选择权重文件 -> ", found_model)
	
	print("准备启动进程...")
	print(" 执行路径: ", exe_path)
	
	# 这里直接传入拼接好的绝对物理路径，不再需要 ProjectSettings.globalize_path 转换
	var args = ["gtp", "-config", config_path, "-model", model_path]
	var pipe_res = OS.execute_with_pipe(exe_path, args)
	
	if pipe_res.is_empty():
		print("【致命错误】：OS.execute_with_pipe 启动失败！")
		return false
		
	stdio_pipe = pipe_res["stdio"]
	process_pid = pipe_res["pid"]
	print("【成功】：KataGo 进程已建立！PID: ", process_pid)
	print("============================================\n")
	
	should_terminate = false
	read_thread = Thread.new()
	read_thread.start(_thread_read_loop)
	
	send_command("boardsize 9")
	send_command("komi 7.5")
	send_command("clear_board")
	return true
func bin_ui_check_path(path: String) -> String:
	if OS.has_feature("editor"):
		return path
	return OS.get_executable_path().get_base_dir().path_join("bin/")
func send_command(cmd: String):
	if stdio_pipe and stdio_pipe.is_open():
		stdio_pipe.store_line(cmd)
		stdio_pipe.flush()

func request_analysis_color(show_territory: bool = false, player_color_str: String = "b"):
	if show_territory:
		# 根据玩家是黑是白，动态请求分析
		send_command("kata-analyze " + player_color_str + " 10 ownership true")
	else:
		send_command("lz-analyze " + player_color_str + " 10")
func abs_path(relative_path: String) -> String:
	return ProjectSettings.globalize_path(relative_path)

# ==================== 后台多线程读取循环 ====================

func _thread_read_loop():
	while not should_terminate:
		if stdio_pipe and stdio_pipe.is_open():
			var line = stdio_pipe.get_line().strip_edges()
			
			#if not line.is_empty():
				#if line.length() > 200:
					# 超过 250 字符的分析行，只打印前 80 字符，不破坏游戏引擎性能
					#print("[KataGo 后台] (超长分析行已自动缩写) ", line.substr(0, 50), "...")
				#else:
					#print("[KataGo 后台] ", line)
			
			if line.begins_with("="):
				var parts = line.split(" ")
				if parts.size() > 1:
					var resp = parts[1].strip_edges()
					if "B+" in resp or "W+" in resp or resp == "0" or "draw" in resp.to_lower():
						call_deferred("emit_score", resp)
					else:
						call_deferred("emit_ai_move", resp)
			
			elif line.begins_with("info"):
				if "ownership" in line:
					var start_idx = line.find("ownership")
					var open_bracket = line.find("[", start_idx)
					var close_bracket = line.find("]", open_bracket)
					if open_bracket != -1 and close_bracket != -1:
						var ownership_str = line.substr(open_bracket + 1, close_bracket - open_bracket - 1).strip_edges()
						var ownership_parts = ownership_str.split(" ")
						var ownership_floats = []
						for p in ownership_parts:
							p = p.strip_edges()
							if p != "":
								ownership_floats.append(float(p))
						call_deferred("emit_ownership", ownership_floats)
				
				if " move " in line:
					# 【核心修复】：提取当前这一行计算的 Visits 深度
					var top_visits = 0
					var parts = line.split("info move ")
					if parts.size() > 1:
						var sub_parts = parts[1].split(" ", false)
						for i in range(sub_parts.size()):
							if sub_parts[i] == "visits" and i + 1 < sub_parts.size():
								top_visits = int(sub_parts[i+1])
								break
								
					# 【核心修复】：只有当 KataGo 真的动脑筋算够了次数（胜率已经产生分化），才允许拦截并 stop！
					if top_visits >= min_required_visits:
						min_required_visits = 9999
						var candidates = parse_combined_analysis_line(line)
						if candidates.size() > 0:
							call_deferred("emit_candidates", candidates)
							send_command("stop")
		else:
			OS.delay_msec(10)
func emit_ownership(ownership_floats: Array):
	ownership_ready.emit(ownership_floats)
# 新增辅助分发函数（放于脚本任意空白处）
func emit_score(score_text: String):
	score_ready.emit(score_text)
func emit_ai_move(move: String):
	ai_move_ready.emit(move)
func parse_combined_analysis_line(line: String) -> Array:
	var candidates = []
	var parts = line.split("info move ")
	
	for part in parts:
		part = part.strip_edges()
		if part.is_empty():
			continue
			
		var sub_parts = part.split(" ")
		if sub_parts.size() >= 4:
			var move_name = sub_parts[0]
			var winrate = 0.0
			
			# 提取胜率
			for i in range(sub_parts.size()):
				if sub_parts[i] == "winrate" and i + 1 < sub_parts.size():
					var raw_winrate = float(sub_parts[i+1])
					if raw_winrate > 1.0:
						winrate = raw_winrate / 10000.0
					else:
						winrate = raw_winrate
					break
			
			# 提取 PV 变化链
			var pv_list = []
			var pv_split = part.split("pv ")
			if pv_split.size() > 1:
				var pv_moves = pv_split[1].split(" ")
				for m in pv_moves:
					m = m.strip_edges()
					if m != "" and m.length() <= 3:
						pv_list.append(m)
			
			# 【核心修复】：移除了对 move_name == "pass" 的强行过滤，允许 pass 作为候选点进入决策
			if move_name != "":
				candidates.append({
					"move": move_name,
					"winrate": winrate,
					"pv": pv_list
				})
				
	return candidates
func emit_candidates(candidates: Array):
	# 过滤出胜率排名前 3 的推荐点发送给棋盘
	candidates.sort_custom(func(a, b): return a["winrate"] > b["winrate"])
	var top_candidates = candidates.slice(0, min(3, candidates.size()))
	candidates_ready.emit(top_candidates)

# ==================== 安全关闭服务 ====================

func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		stop_service()

func stop_service():
	should_terminate = true
	if process_pid != -1:
		OS.kill(process_pid)
		process_pid = -1
	if read_thread and read_thread.is_alive():
		read_thread.wait_to_finish()
	print("[KataService] 服务已安全关闭。")
func start_katago_dynamic(size: int, komi_val: float) -> bool:
	var success = start_katago()
	if success:
		# 初始化动态棋盘大小和贴目
		send_command("boardsize " + str(size))
		send_command("komi " + str(komi_val))
		send_command("clear_board")
	return success
