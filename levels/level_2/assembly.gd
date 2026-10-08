extends RefCounted
## Reading the assembly lines Level 2 writes, shared by its maze rooms and code rooms. Registers can
## be ABI names (a0, sp) or x-names. Mirrors parse_line and branch_taken in server/puzzles.py.

const PuzzleRoom := preload("res://levels/level_1/puzzle_room.gd")
const Registers := preload("res://ui/registers.gd")
const Style := preload("res://ui/style.gd")
const BRANCHES := ["beq", "bne", "blt", "bge", "bltu", "bgeu"]
const CODE_BASE := 0x100  ## A code room's first instruction; matches server/puzzles.py.
const EXIT := 0x400  ## Where main's caller (the OS) waits: returning here ends a code room's program.
const JUNK := 0xDEADBEEF  ## What a stack word holds before anything is saved in it.


## How a word reads in a code room: junk before anything is saved there, addresses in hex, and
## numbers as C prints them.
static func word_text(value: int) -> String:
	if value == JUNK:
		return "junk"
	return "0x%X" % value if value >= CODE_BASE and value < 0x80000000 else Style.word_text(value)


## One line: an instruction as a dictionary of op and fields (registers as numbers), or a label.
static func parse(line: String) -> Dictionary:
	if line.ends_with(":"):
		return {"op": "label", "name": line.trim_suffix(":")}
	var parts := line.replace(",", "").split(" ")
	var op := parts[0]
	match op:
		"lw", "sw":
			var place := parts[2].trim_suffix(")").split("(")
			return {"op": op, "rd" if op == "lw" else "rs2": Registers.number(parts[1]), "imm": int(place[0]),
				"rs1": Registers.number(place[1])}
		"jalr":
			var place := parts[2].trim_suffix(")").split("(")
			return {"op": "jalr", "rd": Registers.number(parts[1]), "imm": int(place[0]), "rs1": Registers.number(place[1])}
		"jal":
			return {"op": "jal", "rd": Registers.number(parts[1]), "target": parts[2]}
		"j":
			return {"op": "jal", "rd": 0, "target": parts[1]}
		"la":
			return {"op": "la", "rd": Registers.number(parts[1]), "target": parts[2]}
	if op in BRANCHES:
		return {"op": op, "rs1": Registers.number(parts[1]), "rs2": Registers.number(parts[2]), "target": parts[3]}
	if parts[3].is_valid_int():
		return {"op": op, "rd": Registers.number(parts[1]), "rs1": Registers.number(parts[2]), "imm": int(parts[3])}
	return {"op": op, "rd": Registers.number(parts[1]), "rs1": Registers.number(parts[2]),
		"rs2": Registers.number(parts[3])}


static func branch_taken(op: String, a: int, b: int) -> bool:
	match op:
		"beq": return a == b
		"bne": return a != b
		"blt": return PuzzleRoom.signed(a) < PuzzleRoom.signed(b)
		"bge": return PuzzleRoom.signed(a) >= PuzzleRoom.signed(b)
		"bltu": return a < b
		"bgeu": return a >= b
	return false
