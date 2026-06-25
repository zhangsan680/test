class_name RPSGame
extends RefCounted

## The rules engine and economy. Holds every player and resolves duels,
## star transfers, the (dynamic) star market, loans with interest, card trades,
## AI deal offers and the survival judgement. Knows nothing about rendering -
## the scene drives it and listens to signals.

signal logged(text: String)
signal eliminated(p: Player)
signal duel_done(a: Player, b: Player, card_a: int, card_b: int, result: int)

const SURVIVE_STARS: int = 3
const STAR_BASE_PRICE: int = 100
const SELL_FACTOR: float = 0.6
const LOAN_CHUNK: int = 100
const LOAN_CAP: int = 600
const INTEREST_RATE: float = 0.04
const MATCH_SECONDS: float = 240.0  # 4 minutes, compressed from the manga's 4 hours
const START_MONEY: int = 250

const ALIASES: Array = ["Viper", "Banker", "Ghost", "Magpie", "Fox", "Crane", "Shark", "Wolf"]

var players: Array = []
var human: Player = null
var time_left: float = MATCH_SECONDS
var finished: bool = false
var offer: Dictionary = {}  # pending AI deal: {from: Player, kind: "buy"/"sell", price: int}

func setup(num_ai: int) -> void:
	players.clear()
	time_left = MATCH_SECONDS
	finished = false
	offer = {}
	human = Player.new(0, "You", true)
	human.money = START_MONEY
	players.append(human)
	var aliases: Array = ALIASES.duplicate()
	aliases.shuffle()
	for i in range(num_ai):
		var p: Player = Player.new(i + 1, aliases[i % aliases.size()], false)
		p.personality = randi() % 4  # number of AIBrain.Personality values
		p.money = START_MONEY
		players.append(p)

func alive_players() -> Array:
	return players.filter(func(p): return p.alive)

func can_duel(p: Player) -> bool:
	return p.alive and p.cards_left() > 0 and p.stars > 0

# --- Duels ---

## Resolve one match. Both cards are consumed regardless of outcome; a tie burns
## cards but moves no star. Returns the result from a's perspective (1/-1/0).
func play_duel(a: Player, b: Player, card_a: int, card_b: int) -> int:
	if a.count_of(card_a) <= 0 or b.count_of(card_b) <= 0:
		return 0
	a.hand[card_a] = a.count_of(card_a) - 1
	b.hand[card_b] = b.count_of(card_b) - 1
	var result: int = CardType.compare(card_a, card_b)
	if result == 1:
		_transfer_star(b, a)
	elif result == -1:
		_transfer_star(a, b)
	duel_done.emit(a, b, card_a, card_b, result)
	_check_elim(a)
	_check_elim(b)
	return result

func _transfer_star(loser: Player, winner: Player) -> void:
	loser.stars -= 1
	winner.stars += 1

func _check_elim(p: Player) -> void:
	if p.alive and p.stars <= 0:
		p.alive = false
		eliminated.emit(p)
		logged.emit("%s lost their last star - bankrupt and out." % p.display_name)

# --- Dynamic star pricing ---

func total_stars() -> int:
	var t: int = 0
	for p in players:
		if p.alive:
			t += p.stars
	return t

## Stars get pricier as the clock runs down and as they grow scarce on the table.
func star_price() -> int:
	var time_factor: float = 1.0 + (1.0 - clampf(time_left / MATCH_SECONDS, 0.0, 1.0)) * 0.8
	var start_total: int = max(players.size() * 3, 1)
	var scarcity: float = 1.0 + clampf(float(start_total - total_stars()) / float(start_total), 0.0, 1.0) * 0.6
	return int(round(STAR_BASE_PRICE * time_factor * scarcity))

func star_buy_price() -> int:
	return star_price()

func star_sell_price() -> int:
	return int(round(star_price() * SELL_FACTOR))

# --- Star market (trading with the house at a spread) ---

func buy_star(p: Player) -> bool:
	var price: int = star_buy_price()
	if p.money >= price:
		p.money -= price
		p.stars += 1
		return true
	return false

func sell_star(p: Player) -> bool:
	if p.stars > 1:  # never sell your last star - that would be suicide
		p.stars -= 1
		p.money += star_sell_price()
		return true
	return false

# --- Loans with compounding interest ---

func borrow(p: Player) -> bool:
	if p.debt + LOAN_CHUNK <= LOAN_CAP:
		p.debt += LOAN_CHUNK
		p.money += LOAN_CHUNK
		return true
	return false

func repay(p: Player) -> bool:
	var amount: int = min(LOAN_CHUNK, p.debt)
	if amount > 0 and p.money >= amount:
		p.money -= amount
		p.debt -= amount
		return true
	return false

func accrue_interest() -> void:
	for p in players:
		if p.alive and p.debt > 0:
			p.debt = int(ceil(p.debt * (1.0 + INTEREST_RATE)))

func net_worth(p: Player) -> int:
	return p.money + p.stars * star_sell_price() - p.debt

# --- Card trading (1-for-1 swap, conserves the closed card economy) ---

func trade_cards(proposer: Player, partner: Player, give_kind: int, recv_kind: int) -> bool:
	if proposer.count_of(give_kind) <= 0 or partner.count_of(recv_kind) <= 0:
		return false
	proposer.hand[give_kind] = proposer.count_of(give_kind) - 1
	proposer.hand[recv_kind] = proposer.count_of(recv_kind) + 1
	partner.hand[recv_kind] = partner.count_of(recv_kind) - 1
	partner.hand[give_kind] = partner.count_of(give_kind) + 1
	return true

## AI judges a swap where it would give ai_gives and receive ai_gets.
func ai_should_accept_trade(ai: Player, ai_gives: int, ai_gets: int) -> bool:
	if ai_gives == ai_gets or ai.count_of(ai_gives) <= 0:
		return false
	if ai.count_of(ai_gives) > ai.count_of(ai_gets):
		return randf() < 0.8
	return randf() < 0.15

# --- AI deal offers to the human (negotiation layer) ---

## Maybe stage one pending offer from a live AI. "buy" = the AI buys a star from
## you (you lose a star, gain cash); "sell" = the AI sells you a star.
func generate_offer() -> void:
	if not offer.is_empty():
		return
	var pool: Array = players.filter(func(p): return p.alive and not p.is_human)
	if pool.is_empty():
		return
	var ai: Player = pool.pick_random()
	if randf() < 0.5:
		# AI wants to buy one of your stars, tempting you above the house sell price.
		if human.stars <= 1 or ai.money < star_sell_price():
			return
		var price: int = int(star_sell_price() * randf_range(1.1, 1.5))
		price = min(price, ai.money)
		offer = {"from": ai, "kind": "buy", "price": price}
	else:
		# AI offers to sell you a star below the house buy price - a bargain, for cash.
		if ai.stars <= 1:
			return
		var price: int = int(star_buy_price() * randf_range(0.7, 0.95))
		offer = {"from": ai, "kind": "sell", "price": price}

func accept_offer() -> bool:
	if offer.is_empty():
		return false
	var ai: Player = offer["from"]
	var price: int = offer["price"]
	var ok: bool = false
	if offer["kind"] == "buy":
		if human.stars > 1 and ai.money >= price:
			human.stars -= 1
			ai.stars += 1
			ai.money -= price
			human.money += price
			ok = true
	else:
		if ai.stars > 1 and human.money >= price:
			ai.stars -= 1
			human.stars += 1
			human.money -= price
			ai.money += price
			ok = true
	offer = {}
	return ok

func decline_offer() -> void:
	offer = {}

# --- Background economy: AI players act on their own each tick ---

func random_ai_duel() -> void:
	var pool: Array = players.filter(func(p):
		return p.alive and not p.is_human and p.cards_left() > 0 and p.stars > 0)
	if pool.size() < 2:
		return
	pool.shuffle()
	var a: Player = pool[0]
	var b: Player = pool[1]
	play_duel(a, b, AIBrain.choose_card(a), AIBrain.choose_card(b))

func ai_market_tick() -> void:
	var late: bool = time_left < MATCH_SECONDS * 0.4
	for p in players:
		if p.is_human or not p.alive:
			continue
		if late and p.stars < SURVIVE_STARS:
			if p.money < star_buy_price() and randf() < 0.25:
				borrow(p)
			elif p.money >= star_buy_price() and randf() < 0.3:
				buy_star(p)
		elif p.stars > SURVIVE_STARS + 1 and randf() < 0.2:
			sell_star(p)
		elif p.debt > 0 and p.money >= LOAN_CHUNK and randf() < 0.2:
			repay(p)

func finish() -> void:
	finished = true

func survivors() -> Array:
	return players.filter(func(p): return p.survived())
