extends Node2D

@onready var tips_label = $CanvasLayer/TipsLabel
@onready var canvas = $CanvasLayer

var puzzle_board = {
	Vector2i(2,2): 2, # 白子在中心 (只剩右侧最后一气)
	Vector2i(2,1): 1, # 上方黑子
	Vector2i(2,3): 1, # 下方黑子
	Vector2i(1,2): 1  # 左侧黑子
}
var puzzle_solved = false

func _ready():

	canvas = CanvasLayer.new()
	add_child(canvas)
	
	# 2. 动态生成提示文本 TipsLabel
	tips_label = Label.new()
	tips_label.text = tr("PUZZLE_TIP")
	tips_label.position = Vector2(100, 320) # 摆放在棋盘下方
	canvas.add_child(tips_label)
func _draw():
	# 绘制棋盘 (可以将本段绘制逻辑移到子节点 PuzzleDraw 的 _draw 内部，MainMenu 保持干净)
	var cell = 50.0
	var offset = Vector2(100, 100)
	draw_rect(Rect2(offset - Vector2(25,25), Vector2(200,200)), Color(1.0, 1.0, 1.0, 0.0), true)
	for i in range(4):
		draw_line(offset + Vector2(i*cell, 0), offset + Vector2(i*cell, 150), Color.BLACK, 1.5)
		draw_line(offset + Vector2(0, i*cell), offset + Vector2(150, i*cell), Color.BLACK, 1.5)
	
	for pos in puzzle_board:
		var pixel_pos = offset + Vector2(pos.x * cell, pos.y * cell)
		var color = Color.BLACK if puzzle_board[pos] == 1 else Color.WHITE
		draw_circle(pixel_pos, 20.0, color)
		draw_circle(pixel_pos, 20.0, Color.BLACK if color == Color.WHITE else Color.GRAY, false, 1.5)

func _unhandled_input(event):
	if puzzle_solved: return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell = 50.0
		var offset = Vector2(100, 100)
		var grid_pos = Vector2i(round((event.position.x - offset.x)/cell), round((event.position.y - offset.y)/cell))
		
		# 【核心修复】：玩家必须点击白子右侧的 (3, 2) 交叉点，才能提掉白子通关！
		if grid_pos == Vector2i(3,2):
			puzzle_solved = true
			puzzle_board[Vector2i(3,2)] = 1  # 在 (3,2) 落下黑子
			puzzle_board.erase(Vector2i(2,2)) # 提掉 (2,2) 气尽的白子
			queue_redraw()
			tips_label.text = tr("PUZZLE_SOLVED")
			await get_tree().create_timer(1.0).timeout
			# 场景流转
			get_tree().change_scene_to_file("res://ModeSelection.tscn")
