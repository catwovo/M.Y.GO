# 【替换 deck_builder.gd 完整脚本：净化为纯粹的卡组整备大厅】
extends Control

@onready var deck_status_label = $DeckEdit/DeckStatusLabel
@onready var card_grid = $DeckEdit/ScrollContainer/CardGrid
@onready var tips_label = $TipsLabel
@onready var back_btn = $BackButton

var card_scene = preload("res://Card.tscn")

func _ready():
	back_btn.pressed.connect(_on_back_pressed)
	tips_label.text = tr("DECK_TIPS_WELCOME")
	update_deck_status()
	populate_card_grid()

func _on_back_pressed():
	get_tree().change_scene_to_file("res://ModeSelection.tscn")

func update_deck_status():
	if deck_status_label:
		deck_status_label.text = tr("DECK_STATUS") % ConfigManager.current_deck.size()

func populate_card_grid():
	
	for child in card_grid.get_children():
		child.queue_free()
		
	var all_cards = ConfigManager.get_all_card_resources()

	for data in all_cards:
		if data.card_name in ConfigManager.unlocked_cards:
			var card_inst = card_scene.instantiate()
			card_grid.add_child(card_inst)
			card_inst.setup_card(data)
			
			if data.card_name in ConfigManager.current_deck:
				card_inst.modulate = Color.WHITE
			else:
				card_inst.modulate = Color(0.55, 0.55, 0.55)
				
			card_inst.pressed.connect(_on_deck_card_clicked.bind(data, card_inst))

func _on_deck_card_clicked(data: CardData, card_inst: TextureButton):
	var p_name = data.card_name
	if p_name in ConfigManager.current_deck:
		ConfigManager.current_deck.erase(p_name)
		card_inst.modulate = Color(0.55, 0.55, 0.55)
		tips_label.text = tr("DECK_TIPS_REMOVE") % p_name
	else:
		if ConfigManager.current_deck.size() < 20:
			ConfigManager.current_deck.append(p_name)
			card_inst.modulate = Color.WHITE
			tips_label.text = tr("DECK_TIPS_ADD") % p_name
		else:
			tips_label.text = tr("DECK_TIPS_FULL")
			
	ConfigManager.save_game()
	update_deck_status()
