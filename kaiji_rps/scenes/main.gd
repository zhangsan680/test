extends Node3D
## Restricted Rock-Paper-Scissors - the whole presentation layer.
## The 3D table, the HUD and the duel flow are all built in code so the
## scene file can stay a one-line entry point. The rules and economy live in
## RPSGame; this node just drives it and renders the result.

enum State { IDLE, RESOLVING, MARKET, OFFER, FINISHED }

const NUM_AI: int = 5
const TABLE_RADIUS: float = 3.2
const SEAT_RADIUS: float = 3.6
const AI_TICK: float = 1.3       # seconds between background AI duels
const INTEREST_TICK: float = 12.0  # seconds between debt interest charges

var game: RPSGame
var state: int = State.IDLE
var selected: Player = null
var ai_accum: float = 0.0
var interest_accum: float = 0.0

# 3D refs
var seat_labels: Dictionary = {}   # player id -> Label3D
var pile_cards: Dictionary = {}    # CardType.Kind -> MeshInstance3D
var pile_counts: Dictionary = {}   # CardType.Kind -> Label3D
var reveal_nodes: Array = []

# HUD refs
var status_label: Label
var hint_label: Label
var log_box: RichTextLabel
var opp_buttons: Array = []        # one Button per AI, aligned to players[1..]
var rps_buttons: Dictionary = {}   # CardType.Kind -> Button
var market_btn: Button
var market_panel: Panel
var market_info: Label
var market_msg: Label
var buy_btn: Button
var sell_btn: Button
var borrow_btn: Button
var repay_btn: Button
var give_opt: OptionButton
var get_opt: OptionButton
var offer_panel: Panel
var offer_label: Label
var results_panel: Panel
var results_label: Label


func _ready() -> void:
	randomize()
	game = RPSGame.new()
	game.setup(NUM_AI)
	game.logged.connect(_log)
	game.eliminated.connect(func(_p): _refresh())
	_build_world()
	_build_hud()
	_log("Restricted Rock-Paper-Scissors. 12 cards, 3 stars, 4 minutes.")
	_log("Empty your hand AND keep at least 3 stars to survive.")
	_refresh()


func _process(delta: float) -> void:
	if state == State.FINISHED:
		return
	game.time_left -= delta
	if game.time_left <= 0.0:
		game.time_left = 0.0
		_finish()
		return
	ai_accum += delta
	if ai_accum >= AI_TICK:
		ai_accum = 0.0
		game.random_ai_duel()
		game.ai_market_tick()
		_maybe_offer()
		_refresh()
	interest_accum += delta
	if interest_accum >= INTEREST_TICK:
		interest_accum = 0.0
		game.accrue_interest()
		_refresh()
	_update_status()


# ------------------------------------------------------------------ 3D world

func _build_world() -> void:
	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(50, 50)
	floor_mesh.mesh = pm
	floor_mesh.position = Vector3(0, -0.16, 0)
	floor_mesh.material_override = _flat_mat(Color(0.04, 0.04, 0.06))
	add_child(floor_mesh)

	var table := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = TABLE_RADIUS
	cyl.bottom_radius = TABLE_RADIUS
	cyl.height = 0.3
	table.mesh = cyl
	table.material_override = _flat_mat(Color(0.06, 0.18, 0.10))
	add_child(table)

	var cam := Camera3D.new()
	cam.fov = 46.0
	cam.position = Vector3(0, 7.6, 8.4)
	cam.current = true
	add_child(cam)
	cam.look_at(Vector3(0, 0, 0.8), Vector3.UP)

	var spot := SpotLight3D.new()
	spot.position = Vector3(0, 9, 1.5)
	spot.light_energy = 12.0
	spot.light_color = Color(1.0, 0.95, 0.85)
	spot.spot_range = 30.0
	spot.spot_angle = 40.0
	add_child(spot)
	# Pointing nearly straight down, so use a non-vertical up vector to avoid a
	# degenerate look_at basis.
	spot.look_at(Vector3(0, 0, 0), Vector3(0, 0, -1))

	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 6, 9)
	fill.light_energy = 2.0
	fill.omni_range = 45.0
	fill.light_color = Color(0.7, 0.75, 0.9)
	add_child(fill)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-65, -20, 0)
	key.light_energy = 0.5
	add_child(key)

	var total: int = game.players.size()
	for i in range(total):
		var p: Player = game.players[i]
		var seat: Vector3 = _seat_pos(i, total, SEAT_RADIUS)
		var col: Color = Color(0.6, 0.9, 1.0) if p.is_human else Color(0.9, 0.9, 0.95)
		var lbl := _make_label3d("", col, 40)
		lbl.position = seat + Vector3(0, 0.7, 0)
		add_child(lbl)
		seat_labels[p.id] = lbl

	# The human's three card piles sit on the table in front of their seat.
	var front: Vector3 = _seat_pos(0, total, SEAT_RADIUS)
	var slots := [-0.95, 0.0, 0.95]
	var kinds := CardType.all_kinds()
	for j in range(kinds.size()):
		var k: int = kinds[j]
		var card := _make_card_node(k, true)
		card.position = Vector3(slots[j], 0.2, front.z - 0.8)
		add_child(card)
		pile_cards[k] = card
		var cnt := _make_label3d("x4", Color(1, 1, 1), 36)
		cnt.position = card.position + Vector3(0, -0.05, 0.65)
		add_child(cnt)
		pile_counts[k] = cnt


func _seat_pos(i: int, total: int, radius: float) -> Vector3:
	var ang: float = float(i) / float(total) * TAU
	return Vector3(sin(ang) * radius, 0.0, cos(ang) * radius)


func _flat_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.8
	m.metallic = 0.0
	return m


func _make_label3d(txt: String, col: Color, fsize: int) -> Label3D:
	var l := Label3D.new()
	l.text = txt
	l.font_size = fsize
	l.pixel_size = 0.006
	l.modulate = col
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	return l


func _make_card_node(kind: int, face_up: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.66, 0.04, 0.95)
	mi.mesh = bm
	var face: Color = CardType.kind_color(kind) if face_up else Color(0.12, 0.12, 0.16)
	mi.material_override = _flat_mat(face)
	var letter: String = CardType.kind_letter(kind) if face_up else "?"
	var lcol: Color = Color(0.05, 0.05, 0.05) if face_up else Color(0.7, 0.7, 0.8)
	var lbl := _make_label3d(letter, lcol, 130)
	lbl.position = Vector3(0, 0.28, 0)
	mi.add_child(lbl)
	return mi


# ------------------------------------------------------------------ HUD

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var status := _panel(root, Vector2(16, 16), Vector2(300, 190))
	status_label = _label(status, Vector2(12, 10), Vector2(276, 170), "", 15)

	hint_label = _label(root, Vector2(332, 22), Vector2(620, 30), "", 18)

	var opp := _panel(root, Vector2(16, 218), Vector2(300, 392))
	_label(opp, Vector2(12, 8), Vector2(276, 24), "OPPONENTS  (click to target)", 15)
	for i in range(NUM_AI):
		var b := _button(opp, Vector2(12, 40 + i * 68), Vector2(276, 62), "")
		b.pressed.connect(_on_opponent.bind(i))
		opp_buttons.append(b)

	var logp := _panel(root, Vector2(964, 16), Vector2(300, 470))
	_label(logp, Vector2(12, 8), Vector2(276, 22), "LOG", 15)
	log_box = RichTextLabel.new()
	log_box.position = Vector2(12, 34)
	log_box.size = Vector2(276, 424)
	log_box.scroll_following = true
	logp.add_child(log_box)

	var bar := _panel(root, Vector2(332, 632), Vector2(620, 72))
	var kinds := CardType.all_kinds()
	for j in range(kinds.size()):
		var k: int = kinds[j]
		var rb := _button(bar, Vector2(12 + j * 96, 12), Vector2(90, 48), "Play " + CardType.kind_letter(k))
		rb.pressed.connect(_on_play_card.bind(k))
		rps_buttons[k] = rb
	market_btn = _button(bar, Vector2(316, 12), Vector2(140, 48), "Market / Trade")
	market_btn.pressed.connect(_open_market)
	var endb := _button(bar, Vector2(468, 12), Vector2(140, 48), "End Match Now")
	endb.pressed.connect(_finish)

	_build_market_panel(root)
	_build_offer_panel(root)
	_build_results_panel(root)


func _panel(parent: Control, pos: Vector2, sz: Vector2) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = sz
	parent.add_child(p)
	return p


func _label(parent: Control, pos: Vector2, sz: Vector2, txt: String, fsize: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = sz
	l.text = txt
	l.add_theme_font_size_override("font_size", fsize)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func _button(parent: Control, pos: Vector2, sz: Vector2, txt: String) -> Button:
	var b := Button.new()
	b.position = pos
	b.size = sz
	b.text = txt
	parent.add_child(b)
	return b


func _build_market_panel(root: Control) -> void:
	market_panel = _panel(root, Vector2(340, 150), Vector2(600, 432))
	market_panel.visible = false
	_label(market_panel, Vector2(16, 12), Vector2(560, 28), "MARKET", 20)
	market_info = _label(market_panel, Vector2(16, 44), Vector2(568, 24), "", 14)

	buy_btn = _button(market_panel, Vector2(16, 78), Vector2(270, 44), "Buy 1 star")
	buy_btn.pressed.connect(_on_buy_star)
	sell_btn = _button(market_panel, Vector2(300, 78), Vector2(270, 44), "Sell 1 star")
	sell_btn.pressed.connect(_on_sell_star)

	borrow_btn = _button(market_panel, Vector2(16, 128), Vector2(270, 44), "Borrow")
	borrow_btn.pressed.connect(_on_borrow)
	repay_btn = _button(market_panel, Vector2(300, 128), Vector2(270, 44), "Repay")
	repay_btn.pressed.connect(_on_repay)

	_label(market_panel, Vector2(16, 184), Vector2(560, 24), "Card swap with your selected opponent (1-for-1):", 14)
	_label(market_panel, Vector2(16, 216), Vector2(120, 24), "You give:", 14)
	give_opt = _card_option(market_panel, Vector2(140, 212))
	_label(market_panel, Vector2(16, 252), Vector2(120, 24), "You get:", 14)
	get_opt = _card_option(market_panel, Vector2(140, 248))
	get_opt.select(1)  # default to a different kind than "give"
	var propose := _button(market_panel, Vector2(320, 212), Vector2(250, 44), "Propose swap")
	propose.pressed.connect(_on_propose_trade)

	market_msg = _label(market_panel, Vector2(16, 296), Vector2(560, 60), "", 14)
	var close := _button(market_panel, Vector2(16, 372), Vector2(560, 44), "Close")
	close.pressed.connect(_close_market)


func _card_option(parent: Control, pos: Vector2) -> OptionButton:
	var o := OptionButton.new()
	o.position = pos
	o.size = Vector2(150, 32)
	for k in CardType.all_kinds():
		o.add_item(CardType.kind_name(k), k)
	parent.add_child(o)
	return o


func _build_offer_panel(root: Control) -> void:
	offer_panel = _panel(root, Vector2(380, 240), Vector2(520, 210))
	offer_panel.visible = false
	_label(offer_panel, Vector2(20, 14), Vector2(480, 26), "A DEAL IS OFFERED", 18)
	offer_label = _label(offer_panel, Vector2(20, 48), Vector2(480, 84), "", 15)
	var accept := _button(offer_panel, Vector2(20, 144), Vector2(230, 48), "Accept")
	accept.pressed.connect(_on_accept_offer)
	var decline := _button(offer_panel, Vector2(270, 144), Vector2(230, 48), "Decline")
	decline.pressed.connect(_on_decline_offer)


func _build_results_panel(root: Control) -> void:
	results_panel = _panel(root, Vector2(290, 96), Vector2(700, 528))
	results_panel.visible = false
	_label(results_panel, Vector2(20, 16), Vector2(660, 32), "TIME'S UP - FINAL STANDINGS", 22)
	results_label = _label(results_panel, Vector2(20, 56), Vector2(660, 384), "", 15)
	var again := _button(results_panel, Vector2(20, 460), Vector2(320, 48), "New Match")
	again.pressed.connect(func(): get_tree().reload_current_scene())
	var quit := _button(results_panel, Vector2(360, 460), Vector2(320, 48), "Quit")
	quit.pressed.connect(func(): get_tree().quit())


# ------------------------------------------------------------------ refresh

func _refresh() -> void:
	_update_status()
	_update_opponents()
	_update_seats()
	_update_piles()
	_update_market()
	_update_actions()


func _update_status() -> void:
	if status_label == null:
		return
	var m: int = int(game.time_left) / 60
	var s: int = int(game.time_left) % 60
	var h: Player = game.human
	status_label.text = "TIME  %d:%02d\nStars: %d   Cash: %d   Debt: %d\nCards: %d  (R%d S%d P%d)\nStar price ~%d   Net worth %d\nGoal: empty hand + 3+ stars" % [
		m, s, h.stars, h.money, h.debt, h.cards_left(),
		h.count_of(CardType.Kind.ROCK), h.count_of(CardType.Kind.SCISSORS), h.count_of(CardType.Kind.PAPER),
		game.star_price(), game.net_worth(h)]


func _update_opponents() -> void:
	for i in range(opp_buttons.size()):
		var p: Player = game.players[i + 1]
		var b: Button = opp_buttons[i]
		var tag: String = "  [OUT]" if not p.alive else ("  <-target" if p == selected else "")
		b.text = "%s   stars %d  cards %d%s\n(%s)" % [
			p.display_name, p.stars, p.cards_left(), tag, AIBrain.personality_name(p.personality)]
		b.disabled = not (state == State.IDLE and p.alive)


func _update_seats() -> void:
	for p in game.players:
		var lbl: Label3D = seat_labels[p.id]
		lbl.text = "%s\n* %d   C %d" % [p.display_name, p.stars, p.cards_left()]
		if not p.alive:
			lbl.modulate = Color(0.5, 0.22, 0.22)
		elif p == selected:
			lbl.modulate = Color(1.0, 0.85, 0.3)
		elif p.is_human:
			lbl.modulate = Color(0.6, 0.9, 1.0)
		else:
			lbl.modulate = Color(0.9, 0.9, 0.95)


func _update_piles() -> void:
	for k in pile_cards:
		var n: int = game.human.count_of(k)
		pile_counts[k].text = "%s x%d" % [CardType.kind_letter(k), n]
		var mi: MeshInstance3D = pile_cards[k]
		var base: Color = CardType.kind_color(k)
		mi.material_override.albedo_color = base if n > 0 else base.darkened(0.6)


func _update_market() -> void:
	if buy_btn == null:
		return
	buy_btn.text = "Buy 1 star (-%d)" % game.star_buy_price()
	sell_btn.text = "Sell 1 star (+%d)" % game.star_sell_price()
	borrow_btn.text = "Borrow %d" % RPSGame.LOAN_CHUNK
	repay_btn.text = "Repay %d" % RPSGame.LOAN_CHUNK
	buy_btn.disabled = game.human.money < game.star_buy_price()
	sell_btn.disabled = game.human.stars <= 1
	borrow_btn.disabled = game.human.debt + RPSGame.LOAN_CHUNK > RPSGame.LOAN_CAP
	repay_btn.disabled = game.human.debt <= 0 or game.human.money < min(RPSGame.LOAN_CHUNK, game.human.debt)
	market_info.text = "Buy %d / Sell %d   |   Cash %d   Debt %d (interest every %ds)" % [
		game.star_buy_price(), game.star_sell_price(), game.human.money, game.human.debt, int(INTEREST_TICK)]


func _update_actions() -> void:
	var can_play: bool = state == State.IDLE and selected != null \
		and game.can_duel(game.human) and game.can_duel(selected)
	for k in rps_buttons:
		rps_buttons[k].disabled = not (can_play and game.human.count_of(k) > 0)
	if market_btn != null:
		market_btn.disabled = state != State.IDLE
	_update_hint()


func _update_hint() -> void:
	if hint_label == null:
		return
	match state:
		State.IDLE:
			if game.human.cards_left() == 0:
				hint_label.text = "Hand cleared! Hold on until time runs out."
			elif selected == null:
				hint_label.text = "Click an opponent on the left to target them."
			else:
				hint_label.text = "Targeting %s. Play a card to duel, or open Market to trade." % selected.display_name
		State.RESOLVING:
			hint_label.text = "..."
		State.MARKET:
			hint_label.text = "Market open."
		State.OFFER:
			hint_label.text = "A deal is on the table - accept or decline."
		State.FINISHED:
			hint_label.text = "Match over."


# ------------------------------------------------------------------ actions

func _on_opponent(index: int) -> void:
	if state != State.IDLE:
		return
	var p: Player = game.players[index + 1]
	if not p.alive:
		return
	selected = p
	_refresh()


func _on_play_card(kind: int) -> void:
	if state != State.IDLE or selected == null:
		return
	if not game.can_duel(game.human):
		_log("You can't duel - you need a card and a star.")
		return
	if not game.can_duel(selected):
		_log("%s can't duel right now." % selected.display_name)
		return
	if game.human.count_of(kind) <= 0:
		return
	var opp: Player = selected
	var ai_card: int = AIBrain.choose_card(opp)
	var result: int = game.play_duel(game.human, opp, kind, ai_card)
	var line: String = "You played %s, %s played %s. " % [
		CardType.kind_name(kind), opp.display_name, CardType.kind_name(ai_card)]
	if result == 1:
		line += "WIN - took a star."
	elif result == -1:
		line += "LOSE - lost a star."
	else:
		line += "Draw - both cards burned."
	_log(line)
	state = State.RESOLVING
	_refresh()
	_show_reveal(kind, ai_card, result)


func _show_reveal(human_kind: int, ai_kind: int, result: int) -> void:
	_clear_reveal()
	var hc := _make_card_node(human_kind, true)
	hc.position = Vector3(-0.9, 0.6, 0.0)
	hc.scale = Vector3.ONE * 0.01
	add_child(hc)
	var ac := _make_card_node(ai_kind, true)
	ac.position = Vector3(0.9, 0.6, 0.0)
	ac.scale = Vector3.ONE * 0.01
	add_child(ac)
	reveal_nodes = [hc, ac]
	var banner: String = "DRAW"
	if result == 1:
		banner = "YOU WIN"
	elif result == -1:
		banner = "YOU LOSE"
	hint_label.text = banner
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(hc, "scale", Vector3.ONE, 0.25)
	t.tween_property(ac, "scale", Vector3.ONE, 0.25)
	t.tween_property(hc, "position:y", 1.05, 0.25)
	t.tween_property(ac, "position:y", 1.05, 0.25)
	t.set_parallel(false)
	t.tween_interval(1.1)
	t.tween_callback(_end_reveal)


func _end_reveal() -> void:
	_clear_reveal()
	if state == State.RESOLVING:
		state = State.IDLE
	if selected != null and not game.can_duel(selected):
		selected = null
	_refresh()


func _clear_reveal() -> void:
	for n in reveal_nodes:
		if is_instance_valid(n):
			n.queue_free()
	reveal_nodes.clear()


# ------------------------------------------------------------------ market

func _open_market() -> void:
	if state != State.IDLE:
		return
	state = State.MARKET
	market_msg.text = "" if selected != null else "Tip: pick an opponent first to enable card swaps."
	market_panel.visible = true
	_refresh()


func _close_market() -> void:
	market_panel.visible = false
	if state == State.MARKET:
		state = State.IDLE
	_refresh()


func _on_buy_star() -> void:
	if game.buy_star(game.human):
		_log("Bought a star.")
		market_msg.text = "Bought a star."
	else:
		market_msg.text = "Not enough money - try a loan."
	_refresh()


func _on_sell_star() -> void:
	if game.sell_star(game.human):
		_log("Sold a star.")
		market_msg.text = "Sold a star."
	else:
		market_msg.text = "Can't sell your last star."
	_refresh()


func _on_borrow() -> void:
	if game.borrow(game.human):
		_log("Borrowed %d. Debt now %d." % [RPSGame.LOAN_CHUNK, game.human.debt])
		market_msg.text = "Borrowed %d. It accrues interest." % RPSGame.LOAN_CHUNK
	else:
		market_msg.text = "Loan cap reached (%d)." % RPSGame.LOAN_CAP
	_refresh()


func _on_repay() -> void:
	if game.repay(game.human):
		_log("Repaid %d. Debt now %d." % [RPSGame.LOAN_CHUNK, game.human.debt])
		market_msg.text = "Repaid some debt."
	else:
		market_msg.text = "Nothing to repay, or not enough cash."
	_refresh()


func _on_propose_trade() -> void:
	if selected == null:
		market_msg.text = "Pick an opponent first (left panel)."
		return
	var give_kind: int = give_opt.get_selected_id()
	var get_kind: int = get_opt.get_selected_id()
	if give_kind == get_kind:
		market_msg.text = "Pick two different card kinds."
		return
	if game.human.count_of(give_kind) <= 0:
		market_msg.text = "You have no %s to give." % CardType.kind_name(give_kind)
		return
	# From the AI's side it gives get_kind and receives give_kind.
	if game.ai_should_accept_trade(selected, get_kind, give_kind) \
		and game.trade_cards(game.human, selected, give_kind, get_kind):
		_log("Swapped your %s for %s's %s." % [
			CardType.kind_name(give_kind), selected.display_name, CardType.kind_name(get_kind)])
		market_msg.text = "%s accepted the swap." % selected.display_name
	else:
		market_msg.text = "%s refused the swap." % selected.display_name
	_refresh()


# ------------------------------------------------------------------ AI offers

func _maybe_offer() -> void:
	if state != State.IDLE or not game.offer.is_empty():
		return
	if randf() < 0.35:
		game.generate_offer()
		if not game.offer.is_empty():
			_show_offer()


func _show_offer() -> void:
	state = State.OFFER
	var ai: Player = game.offer["from"]
	var price: int = game.offer["price"]
	if game.offer["kind"] == "buy":
		offer_label.text = "%s wants to BUY one of your stars for %d.\nYou would drop to %d stars and gain %d cash." % [
			ai.display_name, price, game.human.stars - 1, price]
	else:
		offer_label.text = "%s offers to SELL you a star for %d.\nYou would rise to %d stars and pay %d cash." % [
			ai.display_name, price, game.human.stars + 1, price]
	offer_panel.visible = true
	_refresh()


func _on_accept_offer() -> void:
	if game.accept_offer():
		_log("Deal accepted.")
	else:
		_log("The deal fell through.")
	offer_panel.visible = false
	if state == State.OFFER:
		state = State.IDLE
	_refresh()


func _on_decline_offer() -> void:
	game.decline_offer()
	offer_panel.visible = false
	if state == State.OFFER:
		state = State.IDLE
	_log("You declined the offer.")
	_refresh()


# ------------------------------------------------------------------ finish

func _finish() -> void:
	if state == State.FINISHED:
		return
	game.finish()
	state = State.FINISHED
	_clear_reveal()
	market_panel.visible = false
	offer_panel.visible = false
	var g := game
	var ranked: Array = game.players.duplicate()
	ranked.sort_custom(func(x, y): return g.net_worth(x) > g.net_worth(y))
	var you_ok: bool = game.human.survived()
	var lines: Array = []
	lines.append("YOU: %s   (stars %d, cards %d, cash %d, debt %d)" % [
		"SURVIVED" if you_ok else "FAILED",
		game.human.stars, game.human.cards_left(), game.human.money, game.human.debt])
	lines.append("Survive = empty hand AND 3+ stars at the bell.")
	lines.append("")
	lines.append("Net-worth ranking (cash + stars - debt):")
	var rank: int = 1
	for p in ranked:
		var verdict: String = "survived" if p.survived() else ("OUT" if not p.alive else "failed")
		lines.append("%d. %s%s - %s  (net %d, stars %d, cards %d)" % [
			rank, p.display_name, "  <- you" if p.is_human else "", verdict,
			game.net_worth(p), p.stars, p.cards_left()])
		rank += 1
	results_label.text = "\n".join(lines)
	results_panel.visible = true
	_log("Match over. You %s." % ("SURVIVED" if you_ok else "did not survive"))
	_refresh()


func _log(text: String) -> void:
	if log_box != null:
		log_box.append_text(text + "\n")
	else:
		print(text)
