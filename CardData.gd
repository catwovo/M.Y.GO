# 【CardData.gd 完整代码】
class_name CardData
extends Resource

@export_group("卡牌视觉与基本信息")
@export var card_name: String = "未命名棋手"
# 稀有度
@export_enum("UR", "SSR", "SR", "R") var rarity: String = "R"
@export var portrait: Texture2D # 棋手头像
@export var description: String = "棋手战术描述..."

@export_group("GTP 引擎 AI 属性")
# 绑定的专属 AI 段位
@export_enum("preaz_15k", "preaz_10k", "preaz_5k", "preaz_1k", "preaz_1d", "preaz_3d", "preaz_5d", "preaz_9d") var ai_rank: String = "preaz_9d"
# 绑定的专属 AI 棋风
@export_enum("balanced", "aggressive", "defensive", "cosmic") var ai_style: String = "balanced"
