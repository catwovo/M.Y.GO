# 【替换 Card.gd 脚本：加入高颜值炉石级鼠标悬停弹出动效】
extends TextureButton

@export var card_data: CardData 

@onready var portrait_rect = $VBoxContainer/PortraitRect
@onready var name_label = $VBoxContainer/NameLabel
@onready var desc_label = $VBoxContainer/DescLabel

# 动画渐变器
var tween: Tween
var is_in_hand: bool = false

func _ready():
	if card_data:
		setup_card(card_data)
	is_in_hand = (get_parent() != null and get_parent().name == "HandUI")
	# 1. 绑定鼠标进入/移出信号
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func setup_card(data: CardData):
	card_data = data
	if name_label: name_label.text = data.card_name
	if desc_label: 
		desc_label.text = "[%s]\n%s" % [data.rarity, data.description]
		# 强制重算一次尺寸，彻底防溢出
		desc_label.custom_minimum_size.x = 160 # 替换为你卡牌合适的宽度
		desc_label.size.x = 160
	if portrait_rect and data.portrait:
		portrait_rect.texture = data.portrait
# 2. 当鼠标悬停在卡牌上时：向上弹跳并放大
func _on_mouse_entered():
	if tween: tween.kill()
	tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	if is_in_hand:
		# 模式 A：对局手牌 -> 底部对齐大弹跳
		pivot_offset = Vector2(size.x / 2.0, size.y)
		tween.tween_property(self, "position:y", -25.0, 0.15)
		tween.tween_property(self, "scale", Vector2(1.08, 1.08), 0.15)
	else:
		# 模式 B：卡组/对阵网格卡 -> 中心对齐轻量微放大 (不改变 position，100% 绝对不会破坏网格排版和卡死)
		pivot_offset = size / 2.0 # 居中锚点
		tween.tween_property(self, "scale", Vector2(1.04, 1.04), 0.12)

# 鼠标移出
func _on_mouse_exited():
	if tween: tween.kill()
	tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	if is_in_hand:
		tween.tween_property(self, "position:y", 0.0, 0.15)
		tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.15)
	else:
		# 菜单卡复原
		tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.12)
