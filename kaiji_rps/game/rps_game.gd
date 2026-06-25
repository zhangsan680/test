class_name RPSGame
extends RefCounted

## The rules engine and economy. Holds every player and resolves duels,
## star transfers, the star market, card trades and the survival judgement.
## Knows nothing about rendering — the scene drives it and listens to signals.

signal logged(text: String)
signal eliminated(p: Player)
signal duel_done(a: Player, b: Player, card_a: int, card_b: int, result: int)

const SURVIVE_STARS: int = 3
const STAR_BUY_PRICE: int = 120
const STAR_SELL_PRICE: int = 70
const MATCH_SECONDS: float = 240.0  # 4 minutes, compressed from the manga's 4 hours
const START_MONEY: int = 300

const ALIASES: Array = ["Viper", "Banker", "Ghost", "Magpie", "Fox", "Crane", "Shark", "Wolf"]

var players: Array = []
var human: Player = null
var time_left: float = MATCH_SECONDS
var finished: bool = false

func setup(num_ai: int) -> void:
	players.clear()
	time_left = MATCH_SECONDS
	finished = false
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

## A player may duel while alive, holding at least one card and one star to risk.
func can_duel(p: Player) -> bool:
	return p.alive and p.cards_left() > 0 and p.stars > 0

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

# --- Star market (trading with the house at a spread) ---

func buy_star(p: Player) -> bool:
	if p.money >= STAR_BUY_PRICE:
		p.money -= STAR_BUY_PRICE
		p.stars += 1
		return true
	return false

func sell_star(p: Player) -> bool:
	if p.stars > 1:  # never sell your last star - that would be suicide
		p.stars -= 1
		p.money += STAR_SELL_PRICE
		return true
	return false

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
	# Rational when shedding a surplus card for a scarcer one, with some noise.
	if ai.count_of(ai_gives) > ai.count_of(ai_gets):
		return randf() < 0.8
	return randf() < 0.15

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
	var late: bool = time_left < MATCH_SECONDS * 0.35
	for p in players:
		if p.is_human or not p.alive:
			continue
		if late and p.stars < SURVIVE_STARS and p.money >= STAR_BUY_PRICE and randf() < 0.3:
			buy_star(p)
		elif p.stars > SURVIVE_STARS + 1 and p.money < STAR_BUY_PRICE and randf() < 0.2:
			sell_star(p)

func finish() -> void:
	finished = true

func survivors() -> Array:
	return players.filter(func(p): return p.survived())
