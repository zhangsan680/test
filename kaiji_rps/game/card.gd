class_name CardType
extends RefCounted

## Pure helpers for the three card kinds. No state lives here.

enum Kind { ROCK, SCISSORS, PAPER }

## Returns 1 when a beats b, -1 when b beats a, 0 on a tie.
static func compare(a: int, b: int) -> int:
	if a == b:
		return 0
	match a:
		Kind.ROCK:
			return 1 if b == Kind.SCISSORS else -1
		Kind.SCISSORS:
			return 1 if b == Kind.PAPER else -1
		Kind.PAPER:
			return 1 if b == Kind.ROCK else -1
	return 0

static func kind_name(k: int) -> String:
	match k:
		Kind.ROCK:
			return "Rock"
		Kind.SCISSORS:
			return "Scissors"
		Kind.PAPER:
			return "Paper"
	return "?"

static func kind_letter(k: int) -> String:
	match k:
		Kind.ROCK:
			return "R"
		Kind.SCISSORS:
			return "S"
		Kind.PAPER:
			return "P"
	return "?"

## Card-face colour used by the procedural art (red / blue / gold).
static func kind_color(k: int) -> Color:
	match k:
		Kind.ROCK:
			return Color(0.80, 0.27, 0.24)
		Kind.SCISSORS:
			return Color(0.27, 0.52, 0.82)
		Kind.PAPER:
			return Color(0.83, 0.72, 0.36)
	return Color.WHITE

static func all_kinds() -> Array:
	return [Kind.ROCK, Kind.SCISSORS, Kind.PAPER]
