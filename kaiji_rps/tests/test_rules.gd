extends SceneTree
## Headless sanity check for the pure rules + economy layer.
## Run from the project folder:
##   godot --headless --path . --script res://tests/test_rules.gd

func _initialize() -> void:
	var failed: int = 0

	failed += _check("rock beats scissors", CardType.compare(CardType.Kind.ROCK, CardType.Kind.SCISSORS) == 1)
	failed += _check("scissors beats paper", CardType.compare(CardType.Kind.SCISSORS, CardType.Kind.PAPER) == 1)
	failed += _check("paper beats rock", CardType.compare(CardType.Kind.PAPER, CardType.Kind.ROCK) == 1)
	failed += _check("same kind ties", CardType.compare(CardType.Kind.ROCK, CardType.Kind.ROCK) == 0)

	var g := RPSGame.new()
	g.setup(3)
	failed += _check("4 players total", g.players.size() == 4)
	failed += _check("human starts with 12 cards", g.human.cards_left() == 12)
	failed += _check("human starts with 3 stars", g.human.stars == 3)

	var a: Player = g.players[0]
	var b: Player = g.players[1]
	var a_stars: int = a.stars
	var b_stars: int = b.stars
	g.play_duel(a, b, CardType.Kind.ROCK, CardType.Kind.SCISSORS)  # a wins
	failed += _check("winner gains a star", a.stars == a_stars + 1)
	failed += _check("loser loses a star", b.stars == b_stars - 1)
	failed += _check("both cards consumed", a.cards_left() == 11 and b.cards_left() == 11)

	var s := Player.new(9, "Tester", false)
	s.hand = {CardType.Kind.ROCK: 0, CardType.Kind.SCISSORS: 0, CardType.Kind.PAPER: 0}
	s.stars = 3
	failed += _check("survive with empty hand + 3 stars", s.survived())
	s.stars = 2
	failed += _check("fail with only 2 stars", not s.survived())
	s.stars = 3
	s.hand[CardType.Kind.ROCK] = 1
	failed += _check("fail with cards still in hand", not s.survived())

	# --- Dynamic star pricing ---
	g.time_left = RPSGame.MATCH_SECONDS
	var price_full: int = g.star_price()
	failed += _check("base price at full time", price_full == RPSGame.STAR_BASE_PRICE)
	g.time_left = 0.0
	var price_end: int = g.star_price()
	failed += _check("price rises as time runs out", price_end > price_full)
	g.time_left = RPSGame.MATCH_SECONDS

	# --- Star market with dynamic price ---
	var m := Player.new(8, "Money", false)
	m.money = 400
	var buy_price: int = g.star_buy_price()
	var bought: bool = g.buy_star(m)
	failed += _check("buy star spends dynamic price and adds a star",
		bought and m.stars == 4 and m.money == 400 - buy_price)

	# --- Loans + interest ---
	var d := g.human
	var cash0: int = d.money
	g.borrow(d)
	failed += _check("borrow adds debt and cash", d.debt == RPSGame.LOAN_CHUNK and d.money == cash0 + RPSGame.LOAN_CHUNK)
	g.repay(d)
	failed += _check("repay clears debt and cash", d.debt == 0 and d.money == cash0)
	d.debt = 100
	g.accrue_interest()
	failed += _check("interest compounds the debt", d.debt == int(ceil(100 * (1.0 + RPSGame.INTEREST_RATE))))

	# --- Net worth ---
	var nw := Player.new(7, "NW", false)
	nw.money = 50
	nw.stars = 2
	nw.debt = 30
	failed += _check("net worth = cash + stars*sell - debt",
		g.net_worth(nw) == 50 + 2 * g.star_sell_price() - 30)

	# --- AI deal offer (sell a star to you) ---
	var ai: Player = g.players[2]
	ai.stars = 3
	ai.money = 100
	g.human.stars = 3
	g.human.money = 200
	g.offer = {"from": ai, "kind": "sell", "price": 80}
	var accepted: bool = g.accept_offer()
	failed += _check("accepting a sell offer moves a star and cash",
		accepted and g.human.stars == 4 and g.human.money == 120 and ai.stars == 2 and ai.money == 180)
	failed += _check("offer clears after resolving", g.offer.is_empty())

	# --- Card trade conserves totals ---
	var p1: Player = g.players[2]
	var p2: Player = g.players[3]
	var before: int = p1.cards_left() + p2.cards_left()
	g.trade_cards(p1, p2, CardType.Kind.ROCK, CardType.Kind.PAPER)
	failed += _check("1-for-1 swap conserves the card total", p1.cards_left() + p2.cards_left() == before)

	if failed == 0:
		print("\nALL TESTS PASSED")
	else:
		print("\nFAILURES: %d" % failed)
	quit(0 if failed == 0 else 1)


func _check(label: String, cond: bool) -> int:
	if cond:
		print("  ok   - " + label)
		return 0
	print("  FAIL - " + label)
	return 1
