
extends Control

@onready var start_match_btn = $"../StartMatchBtn"
@onready var back_btn = $"../BackButton"


func _ready():
	if not back_btn.pressed.is_connected(_on_back_pressed):
		back_btn.pressed.connect(_on_back_pressed)
		
	if not start_match_btn.pressed.is_connected(_on_start_match_pressed):
		start_match_btn.pressed.connect(_on_start_match_pressed)
		
	queue_redraw()

func _on_back_pressed():
	get_tree().change_scene_to_file("res://TournamentSetup.tscn")

func _on_start_match_pressed():
	get_tree().change_scene_to_file("res://go_board.tscn")

func _draw():
	if not ConfigManager.tournament_active:
		return
		
	var font = ThemeDB.get_fallback_font()
	var font_size = 13 if ConfigManager.tournament_size == 64 else (16 if ConfigManager.tournament_size == 32 else 18)
	
	var start_x = 0.0
	var total_width = size.x
	var start_y = 0.0
	var total_height = size.y
	# ==========================================================
	var total_rounds = 4 if ConfigManager.tournament_size == 16 else (5 if ConfigManager.tournament_size == 32 else 6)
	var step_y = total_height / float(total_rounds)
	
	
	for r in range(total_rounds):
		# 这一轮在物理上应该有多少个名额
		var total_players_in_round = ConfigManager.tournament_size / pow(2.0, r)
		
		# 自适应等分间距
		var step_x = total_width / float(total_players_in_round)
		var start_x_offset = start_x + step_x / 2.0
		var y = start_y + r * step_y + (step_y / 2.0)
		
		for i in range(total_players_in_round):
			var x = start_x_offset + i * step_x
			var p_name = "待定" # 默认未来未打完的席位为灰色 "待定"
			var text_color = Color(0.259, 0.259, 0.259, 1.0) # 待定颜色
			var is_defeated = false
			
			if r < ConfigManager.tournament_tree.size():
				var round_list = ConfigManager.tournament_tree[r]
				if i < round_list.size():
					p_name = round_list[i]
					text_color = Color.WHITE
					
					# 判定是否战败
					if p_name == ConfigManager.tournament_character:
						text_color = Color(1.0, 0.8, 0.2) # 玩家风范金色
					else:
						# 检查下一轮是否还有他，没有则划掉
						if r + 1 < ConfigManager.tournament_tree.size():
							var next_players = ConfigManager.tournament_tree[r + 1]
							if not p_name in next_players:
								is_defeated = true
								text_color = Color(0.4, 0.4, 0.4)
								
			# 居中对齐绘制名字
			var name_size = font.get_string_size(p_name, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
			var draw_pos = Vector2(x - name_size.x / 2.0, y)
			draw_string(font, draw_pos, p_name, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, text_color)
			
			# 绘制淘汰删除线
			if is_defeated:
				draw_line(Vector2(draw_pos.x, y - name_size.y/3.0), Vector2(draw_pos.x + name_size.x, y - name_size.y/3.0), Color(0.5, 0.2, 0.2), 2.0)
				
			# ==================== 【核心修复】：将限制更改为总轮数 total_rounds，无条件画出全部连线 ====================
			if r + 1 < total_rounds and i % 2 == 0:
				var next_step_x = total_width / (total_players_in_round / 2.0)
				var next_start_x = start_x + next_step_x / 2.0
				var next_x = next_start_x + (i / 2.0) * next_step_x
				
				var p1 = Vector2(x, y + 10.0)
				var p2 = Vector2(x + step_x, y + 10.0)
				var p_mid_1 = Vector2(x, y + 25.0)
				var p_mid_2 = Vector2(x + step_x, y + 25.0)
				var p_next = Vector2(next_x, y + step_y - 20.0)
				
				# 绘制连线
				draw_line(p1, p_mid_1, Color(0.3, 0.3, 0.3), 1.5)
				draw_line(p2, p_mid_2, Color(0.3, 0.3, 0.3), 1.5)
				draw_line(p_mid_1, p_mid_2, Color(0.3, 0.3, 0.3), 1.5)
				draw_line(Vector2((p1.x + p2.x)/2.0, y + 25.0), p_next, Color(0.3, 0.3, 0.3), 1.5)
