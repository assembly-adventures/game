extends RefCounted
## RISC-V register names. The game writes the ABI names the course uses (a0, t1, sp, ra; x0 stays
## x0) and shows each one's x-name beside it, so the mapping sticks. Mirrors REGISTERS in
## server/puzzles.py.

const NAMES := ["x0", "ra", "sp", "gp", "tp", "t0", "t1", "t2", "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5", "a6",
	"a7", "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6"]


## The ABI name of register `n`.
static func name(n: int) -> String:
	return NAMES[n]


## A register's number from its ABI name or its x-name.
static func number(text: String) -> int:
	if text == "zero":
		return 0
	if text == "fp":
		return 8
	var at := NAMES.find(text)
	return at if at >= 0 else int(text.substr(1))


## A register's ABI name from its x-name (or its ABI name).
static func abi(text: String) -> String:
	return NAMES[number(text)]
