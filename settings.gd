# 【settings.gd 完整代码】
extends Control

@onready var api_key_input = $PanelContainer/VBoxContainer/ApiKeyInput
@onready var model_opt = $PanelContainer/VBoxContainer/ModelOpt
@onready var save_close_btn = $PanelContainer/VBoxContainer/SaveCloseBtn
@onready var window_mode_opt = $PanelContainer/VBoxContainer/WindowModeOpt # 新增绑定
@onready var locale_opt = $PanelContainer/VBoxContainer/LocaleOpt # 新增绑定
func _ready():
	save_close_btn.pressed.connect(_on_save_close_pressed)
	
	api_key_input.secret = true
	api_key_input.text = ConfigManager.ai_api_key
	
	model_opt.clear()
	model_opt.add_item("deepseek-chat")
	model_opt.add_item("gpt-4o-mini")
	model_opt.select(0 if ConfigManager.ai_model == "deepseek-chat" else 1)
	window_mode_opt.clear()
	window_mode_opt.add_item("标准窗口模式 (Windowed)", 0)
	window_mode_opt.add_item("无边框窗口 (Borderless)", 1)
	window_mode_opt.add_item("物理全屏 (Fullscreen)", 2)
	window_mode_opt.select(ConfigManager.window_mode_idx) # 回显状态
	locale_opt.clear()
	locale_opt.add_item("简体中文 (Simplified Chinese)", 0)
	locale_opt.add_item("English (US)", 1)
	locale_opt.select(0 if ConfigManager.locale_code == "zh" else 1) # 回显状态
func _on_save_close_pressed():
	ConfigManager.ai_api_key = api_key_input.text
	ConfigManager.ai_model = model_opt.get_item_text(model_opt.selected)
	ConfigManager.apply_window_mode(window_mode_opt.selected)
	
	# 【核心新增】：在保存并关闭时，动态触发语言切换
	var selected_lang_code = "zh" if locale_opt.selected == 0 else "en"
	ConfigManager.locale_code = selected_lang_code
	TranslationServer.set_locale(selected_lang_code) # 告诉底层翻译服务器切换语言
	
	ConfigManager.save_game()
	queue_free()
