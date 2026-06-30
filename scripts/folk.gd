extends RefCounted
class_name Folk
## Static data + helpers for the resident identity system (gender, trait, trait
## level, faith). Phase A wires the WORKER trait end-to-end; the other traits and
## their buildings arrive in later phases but the tables already list them.

const TRAITS := ["worker", "farmer", "shepherd", "arcanist", "priestess", "warrior"]
const TRAIT_LABEL := {
	"worker": "Worker", "farmer": "Farmer", "shepherd": "Shepherd",
	"arcanist": "Arcanist", "priestess": "Priestess", "warrior": "Warrior",
}
# priestess is female-only (no priest). Everything else is gender-neutral.
const MALE_TRAITS := ["worker", "farmer", "shepherd", "arcanist", "warrior"]
const FEMALE_TRAITS := ["worker", "farmer", "shepherd", "arcanist", "priestess", "warrior"]

# Relative spawn weights for a new settler's trait. Common labourers dominate,
# warriors/arcanists are uncommon, priestesses rarest (and female-only, so the male
# pool renormalises over the remaining weights).
const TRAIT_WEIGHT := {
	"worker": 20, "farmer": 20, "shepherd": 20,   # 60% together
	"arcanist": 15, "warrior": 15,                # 30% together
	"priestess": 10,                              # 10%
}

# The building GROUP a trait earns its bonus + XP in (only on-trait postings level).
const TRAIT_WORKSITE := {
	"worker": "hut", "farmer": "farmstead", "shepherd": "pasture",
	"arcanist": "spire", "priestess": "temple", "warrior": "knight_order",
}
const TRAIT_COLOR := {
	"worker": Color(0.75, 0.75, 0.8), "farmer": Color(0.85, 0.78, 0.3),
	"shepherd": Color(0.6, 0.85, 0.5), "arcanist": Color(0.55, 0.6, 1.0),
	"priestess": Color(1.0, 0.95, 0.7), "warrior": Color(0.9, 0.4, 0.35),
}

const MAX_TRAIT_LEVEL := 5
const MAX_FAITH := 5
const FAITH_CAP_NO_TEMPLE := 4   # non-priestess can't pass 4 until a Temple is consecrated

# Productivity multiplier by trait level (index 0 = level 1 .. index 4 = level 5).
const TRAIT_MULT := [1.1, 1.25, 1.45, 1.7, 2.0]
# Trait XP needed to advance FROM a level (index 0 = L1->L2 .. index 3 = L4->L5),
# measured in working ticks at xp-rate 1.0. ~12 ticks/day; L4->L5 ≈ a 15-day cycle.
const TRAIT_XP_REQ := [24.0, 48.0, 90.0, 180.0]
# Faith productivity modifier and XP-rate modifier (index 0 = faith 1 .. 4 = faith 5).
const FAITH_PROD := [0.8, 0.9, 1.0, 1.1, 1.25]
const FAITH_XPRATE := [0.5, 0.75, 1.0, 1.25, 1.5]

const FED_DAYS_PER_FAITH := 3   # fed days to earn one faith level (slow to earn)
const FEMALE_RATIO_FLOOR := 0.4 # keep enough women that a Temple stays reachable

const MALE_NAMES := [
	"Bram", "Cael", "Doran", "Eron", "Finn", "Garr", "Hale", "Joss",
	"Kell", "Loth", "Marn", "Oren", "Pell", "Roan", "Sten", "Toft", "Wynn", "Ulf",
]
const FEMALE_NAMES := [
	"Aria", "Brynn", "Cora", "Della", "Esa", "Fenn", "Greta", "Hilde",
	"Isa", "Lyra", "Mira", "Nessa", "Orla", "Runa", "Saga", "Thora", "Vesna", "Wren",
]


static func roll_gender() -> String:
	return "f" if randf() < 0.5 else "m"


static func roll_trait(gender: String) -> String:
	var pool: Array = FEMALE_TRAITS if gender == "f" else MALE_TRAITS
	var total: int = 0
	for t in pool:
		total += int(TRAIT_WEIGHT.get(t, 1))
	if total <= 0:
		return pool[randi() % pool.size()]
	var roll: int = randi() % total
	for t in pool:
		roll -= int(TRAIT_WEIGHT.get(t, 1))
		if roll < 0:
			return t
	return pool[0]


static func name_for(gender: String) -> String:
	var pool: Array = FEMALE_NAMES if gender == "f" else MALE_NAMES
	return pool[randi() % pool.size()]


static func trait_mult(level: int) -> float:
	return TRAIT_MULT[clampi(level - 1, 0, MAX_TRAIT_LEVEL - 1)]


static func faith_prod(faith: int) -> float:
	return FAITH_PROD[clampi(faith - 1, 0, MAX_FAITH - 1)]


static func faith_xprate(faith: int) -> float:
	return FAITH_XPRATE[clampi(faith - 1, 0, MAX_FAITH - 1)]


static func xp_req(level: int) -> float:
	return TRAIT_XP_REQ[clampi(level - 1, 0, TRAIT_XP_REQ.size() - 1)]
