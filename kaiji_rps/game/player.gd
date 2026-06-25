class_name Player
extends RefCounted

## One participant in the Restricted Rock-Paper-Scissors match.
## Holds a hand of cards (counts per kind), stars, money and alive flag.

var id: int = 0
var display_name: String = ""
var is_human: bool = false
var personality: int = 0  ## AIBrain.Personality, ignored for the human

## hand maps CardType.Kind -> remaining count.
var hand: Dictionary = {}
var stars: int = 3
var money: int = 0
var alive: bool = true

func _init(p_id: int = 0, p_name: String = "", human: bool = false) -> void:
	id = p_id
	display_name = p_name
	is_human = human
	hand = {
		CardType.Kind.ROCK: 4,
		CardType.Kind.SCISSORS: 4,
		CardType.Kind.PAPER: 4,
	}

func cards_left() -> int:
	return count_of(CardType.Kind.ROCK) + count_of(CardType.Kind.SCISSORS) + count_of(CardType.Kind.PAPER)

func count_of(kind: int) -> int:
	return int(hand.get(kind, 0))

## Clear condition: every card played AND at least three stars in hand.
func survived() -> bool:
	return cards_left() == 0 and stars >= 3
