class_name AIBrain
extends RefCounted

## Stateless decision helpers for AI players. Personalities give each opponent
## a readable "tell" the human can try to exploit.

enum Personality { BALANCED, AGGRESSIVE, CAUTIOUS, BLUFFER }

static func personality_name(p: int) -> String:
	match p:
		Personality.BALANCED:
			return "calm, plays the odds"
		Personality.AGGRESSIVE:
			return "aggressive, loves the Rock"
		Personality.CAUTIOUS:
			return "cautious, dumps its surplus"
		Personality.BLUFFER:
			return "erratic, hard to read"
	return "unknown"

## Pick a card to play, weighted by what the player still holds plus a
## personality bias. Opponent hands are hidden, so this is deliberately a
## flavour-driven heuristic rather than a solver.
static func choose_card(p: Player) -> int:
	var weights: Dictionary = {}
	for k in CardType.all_kinds():
		var c: int = p.count_of(k)
		if c <= 0:
			weights[k] = 0.0
			continue
		match p.personality:
			Personality.AGGRESSIVE:
				weights[k] = float(c) * (2.5 if k == CardType.Kind.ROCK else 1.0)
			Personality.CAUTIOUS:
				weights[k] = float(c * c)  # leans toward its most abundant card
			Personality.BLUFFER:
				weights[k] = 1.0  # near-uniform over whatever is available
			_:
				weights[k] = float(c)  # BALANCED: proportional to the hand
	return _weighted_pick(weights)

static func _weighted_pick(weights: Dictionary) -> int:
	var total: float = 0.0
	for k in weights:
		total += weights[k]
	if total <= 0.0:
		return CardType.Kind.ROCK
	var roll: float = randf() * total
	var acc: float = 0.0
	for k in weights:
		acc += weights[k]
		if roll <= acc:
			return k
	return weights.keys()[0]
