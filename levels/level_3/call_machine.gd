extends RefCounted
## Level 3's machine, as the game runs it: code from CODE_BASE, a stack of words below STACK_TOP
## holding junk until something is saved there, and the Chip Chomper as the caller. Before each
## call the Chomper fills every register with junk, sets sp to the top of the stack and ra to
## CHOMPER, puts the call's arguments in a0-a7, and jumps to the room's entry; the call ends when
## the code returns to CHOMPER. A run also records a trace of every step (for the tower and the
## walkthrough's captions), and can stop where a walkthrough waits for a move not made yet.
## Mirrors server/call_stack.py; the server replays and has the final say.

const PuzzleRoom := preload("res://levels/level_1/puzzle_room.gd")
const Assembly := preload("res://levels/level_2/assembly.gd")
const Registers := preload("res://ui/registers.gd")
const BRANCHES := Assembly.BRANCHES
const MASK := 0xFFFFFFFF
const CODE_BASE := 0x100
const CHOMPER := 0x400  ## The Chomper's own code: returning here ends a call.
const STACK_TOP := 0x7FF0
const JUNK := 0xDEADBEEF
const STACK_WORDS := 32
const STEP_LIMIT := 3000
const FIELDS := ["a0", "a1", "s0", "ra", "ret"]
const RULES := ["caller-save", "callee-save", "save-ra", "restore-sp"]

## ra and the s registers are the caller's, so a callee that saves them puts them back. Anything
## else it saves (an argument, a temporary) is for its own code to read back.
static func restored(name: String) -> bool:
	return name == "ra" or name.begins_with("s") and name.substr(1).is_valid_int()

## The prologue and epilogue a frame layout writes (frame[0] is sp+0): make room, save each
## register from the top word down, and on the way out restore ra and the s registers from sp+0
## up and give the room back. An empty frame writes nothing.
static func frame_lines(frame: Array) -> Array:
	if frame.is_empty():
		return [[], []]
	var size := 4 * frame.size()
	var prologue: Array = ["addi sp, sp, -%d" % size]
	for k in range(frame.size() - 1, -1, -1):
		prologue.append("sw %s, %d(sp)" % [frame[k], 4 * k])
	var epilogue: Array = []
	for k in range(frame.size()):
		if restored(str(frame[k])):
			epilogue.append("lw %s, %d(sp)" % [frame[k], 4 * k])
	epilogue.append("addi sp, sp, %d" % size)
	return [prologue, epilogue]

## A walkthrough's moments, in the order they appear in its code.
static func moments(room: Dictionary) -> Array:
	return room.code.filter(func(entry): return entry.has("moment"))

## The room's program: its lines from CODE_BASE, 4 bytes apart (with a frame room's prologue and
## epilogue, or a walkthrough's picked moves, written in), which part each line belongs to ("body",
## "prologue", "epilogue", or "your move"), the address of each label, where empty parts would go
## ("slots", for the listing; a move's names its moment), the address where each move not made yet
## waits ("stops": address to moment), and each line's note, by line.
static func assemble(room: Dictionary, frame: Array = [], choices: Array = []) -> Dictionary:
	var entries := moments(room)
	var options: Array = []
	for k in range(entries.size()):
		var pick := int(choices[k]) if k < choices.size() and choices[k] != null else -1
		options.append(entries[k].options[pick] if pick >= 0 else null)
		if pick >= 0 and str(entries[k].moment) == "frame":
			frame = entries[k].options[pick].frame
	var written := frame_lines(frame)
	var lines: Array = []
	var parts: Array = []
	var labels := {}
	var slots: Array = []
	var stops := {}
	var notes := {}
	var moment := 0
	for entry in room.code:
		if entry.has("label"):
			labels[str(entry.label)] = CODE_BASE + 4 * lines.size()
		elif entry.has("line"):
			if entry.has("note"):
				notes[lines.size()] = str(entry.note)
			lines.append(str(entry.line))
			parts.append("body")
		elif entry.get("prologue", false) or entry.get("epilogue", false):
			var part := "prologue" if entry.get("prologue", false) else "epilogue"
			var wrote: Array = written[0] if part == "prologue" else written[1]
			if wrote.is_empty():
				slots.append({"at": lines.size(), "part": part})
			for line in wrote:
				lines.append(line)
				parts.append(part)
		elif entry.has("moment"):
			var option = options[moment]
			if option == null:
				stops[CODE_BASE + 4 * lines.size()] = moment
				slots.append({"at": lines.size(), "part": "moment", "moment": moment})
			else:
				var frame_move := str(entry.moment) == "frame"
				for line in (written[0] if frame_move else option.lines):
					lines.append(str(line))
					parts.append("prologue" if frame_move else "your move")
			moment += 1
	return {"lines": lines, "parts": parts, "labels": labels, "slots": slots, "stops": stops, "notes": notes}

## What the Chomper leaves in register x<number> before its call number <call> (from 0).
static func junk(call: int, number: int) -> int:
	return 0x5A00 + 0x100 * call + number

## The registers and stack the Chomper's call number <index> starts with.
static func setup(room: Dictionary, index: int) -> Dictionary:
	var regs: Array = [0]
	for n in range(1, 32):
		regs.append(junk(index, n))
	regs[2] = STACK_TOP
	regs[1] = CHOMPER
	var args: Dictionary = room.calls[index].get("args", {})
	for name in args:
		regs[Registers.number(str(name))] = int(args[name]) & MASK
	var memory := {}
	for k in range(1, stack_words(room) + 1):
		memory[STACK_TOP - 4 * k] = JUNK
	return {"regs": regs, "memory": memory}

static func stack_words(room: Dictionary) -> int:
	return int(room.get("stack_words", STACK_WORDS))

## The lowest stack address the heap hasn't eaten after <steps> instructions. In the finale the
## Chomper eats one word every `every` instructions from instruction `start`, from the bottom of
## the stack up; other rooms have no Chomper in the heap.
static func heap_line(room: Dictionary, steps: int) -> int:
	var bottom := STACK_TOP - 4 * stack_words(room)
	if not room.has("chomper") or steps < int(room.chomper.start):
		return bottom
	return bottom + 4 * ((steps - int(room.chomper.start)) / int(room.chomper.every) + 1)

## The Chomper's call number <index>. Returns the registers and stack it ended with, the pc, why
## it crashed if it did ("fault": {"kind", "at"}, or empty), its calls in the order they were made
## (each with the function, depth, a0, a1 and s0 on entry, the ra it was given, the sp it was
## called with, and what it returned), and the trace of every step it took. With `stops`, it pauses
## before running any address there ("paused": that moment; -1 if it never paused).
static func run(room: Dictionary, program_lines: Array, labels: Dictionary, index: int,
		stops: Dictionary = {}) -> Dictionary:
	var program: Array = []
	for line in program_lines:
		program.append(Assembly.parse(str(line)))
	var start := setup(room, index)
	var regs: Array = start.regs
	var memory: Dictionary = start.memory
	var functions := {}
	for name in labels:
		functions[int(labels[name])] = str(name)
	var last := CODE_BASE + 4 * program.size()
	var entry := str(room.entry)
	var first := {"function": entry, "depth": 1, "a0": regs[10], "a1": regs[11], "a2": regs[12], "s0": regs[8],
		"ra": CHOMPER, "sp": STACK_TOP}
	var result := {"regs": regs, "memory": memory, "pc": int(labels[entry]), "fault": {}, "steps": 0,
		"calls": [first], "trace": [], "paused": -1}
	var open_calls: Array = [first]
	var pc := int(labels[entry])
	var steps := 0
	while pc != CHOMPER:
		if pc % 4 != 0 or pc < CODE_BASE or pc >= last:
			result.fault = {"kind": "code", "at": pc}
			break
		if stops.has(pc):
			result.paused = int(stops[pc])
			break
		steps += 1
		if steps > STEP_LIMIT:
			result.fault = {"kind": "loop", "at": 0}
			break
		var ins: Dictionary = program[(pc - CODE_BASE) / 4]
		var op := str(ins.op)
		var step := {"pc": pc, "op": op, "next": pc + 4, "reg": -1, "value": 0, "address": -1, "stored": "",
			"call": {}, "returned": false}
		if op in BRANCHES:
			if Assembly.branch_taken(op, regs[int(ins.rs1)], regs[int(ins.rs2)]):
				step.next = int(labels[ins.target])
		elif op == "jal":
			step.next = int(labels[ins.target])
			_write(regs, step, int(ins.rd), pc + 4)
			if int(ins.rd) == 1:
				var record := {"function": functions.get(int(step.next), str(ins.target)), "depth": open_calls.size() + 1,
					"a0": regs[10], "a1": regs[11], "a2": regs[12], "s0": regs[8], "ra": pc + 4, "sp": regs[2]}
				result.calls.append(record)
				open_calls.append(record)
				step.call = record
		elif op == "jalr":
			step.next = (int(regs[int(ins.rs1)]) + int(ins.imm)) & MASK & ~1
			if int(ins.rd) != 0:
				_write(regs, step, int(ins.rd), pc + 4)
			elif int(ins.rs1) == 1 and not open_calls.is_empty():
				var closing: Dictionary = open_calls.pop_back()
				closing.ret = regs[10]
				step.returned = true
		elif op == "lw" or op == "sw":
			var address: int = (int(regs[int(ins.rs1)]) + int(ins.imm)) & MASK
			step.address = address
			var kind := "aligned" if address % 4 != 0 else "memory" if not memory.has(address) \
				else "overflow" if address < heap_line(room, steps) else ""
			if not kind.is_empty():
				step.crash = true
				result.trace.append(step)
				result.fault = {"kind": kind, "at": address}
				break
			if op == "sw":
				memory[address] = regs[int(ins.rs2)]
				step.stored = Registers.name(int(ins.rs2))
				step.value = memory[address]
			else:
				_write(regs, step, int(ins.rd), int(memory[address]))
		else:
			var second: int = regs[int(ins.rs2)] if ins.has("rs2") else int(ins.imm) & MASK
			_write(regs, step, int(ins.rd), PuzzleRoom.execute(op, regs[int(ins.rs1)], second, 32))
		regs[0] = 0
		step.sp = regs[2]
		step.heap = heap_line(room, steps)
		result.trace.append(step)
		pc = int(step.next)
	result.pc = pc
	result.steps = steps
	return result

static func _write(regs: Array, step: Dictionary, rd: int, value: int) -> void:
	if rd != 0:
		regs[rd] = value & MASK
		step.reg = rd
		step.value = regs[rd]

## Every one of the Chomper's calls, checked against the contract: it must return (no crash), with
## the expected value in a0 if the call names one, and with s0-s11 and sp as the Chomper set them.
## Each row lists what went wrong: "value", a register's name, "sp", or a crash's kind.
static func audit(room: Dictionary, frame: Array = [], choices: Array = []) -> Array:
	var built := assemble(room, frame, choices)
	var rows: Array = []
	for index in range(room.calls.size()):
		var before: Array = setup(room, index).regs
		var state := run(room, built.lines, built.labels, index)
		var problems: Array = []
		if not state.fault.is_empty():
			problems.append(str(state.fault.kind))
		else:
			var call: Dictionary = room.calls[index]
			if call.has("expect") and int(state.regs[10]) != int(call.expect) & MASK:
				problems.append("value")
			for n in [8, 9, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27]:
				if int(state.regs[n]) != int(before[n]):
					problems.append(Registers.name(n))
			if int(state.regs[2]) != STACK_TOP:
				problems.append("sp")
		rows.append({"passed": problems.is_empty(), "problems": problems, "state": state, "before": before})
	return rows

## The calls of an elevator room's function in its one run, outermost first.
static func chain(room: Dictionary) -> Array:
	var built := assemble(room)
	var state := run(room, built.lines, built.labels, 0)
	return state.calls.filter(func(call): return call.function == str(room.function))

## Mirrors grade_call_stack in server/call_stack.py for guest mode, where the game grades itself.
## Malformed answers (the server refuses them) are simply wrong here.
static func grade(room: Dictionary, response: Dictionary) -> bool:
	match str(room.kind):
		"walk":
			var choices = response.get("choices")
			var entries := moments(room)
			if not (choices is Array) or choices.size() != entries.size():
				return false
			var picks: Array = []
			for k in range(choices.size()):
				var pick = choices[k]
				if (typeof(pick) != TYPE_INT and typeof(pick) != TYPE_FLOAT) or int(pick) < 0 \
						or int(pick) >= entries[k].options.size():
					return false
				picks.append(int(pick))
			return audit(room, [], picks).all(func(row): return row.passed)
		"frame":
			var frame = response.get("frame")
			if not (frame is Array) or frame.size() > int(room.max_slots):
				return false
			var seen := {}
			for name in frame:
				if not (name is String) or name not in room.blocks or seen.has(name):
					return false
				seen[name] = true
			return audit(room, frame).all(func(row): return row.passed)
		"elevator":
			var values = response.get("values")
			if not (values is Array) or values.size() != room.blanks.size():
				return false
			var floors := chain(room)
			for k in range(values.size()):
				if typeof(values[k]) != TYPE_INT and not (typeof(values[k]) == TYPE_FLOAT and values[k] == floor(values[k])):
					return false
				var blank: Array = room.blanks[k]
				if int(floors[int(blank[0])].get(str(blank[1]), -1)) != int(values[k]) & MASK:
					return false
			return true
		"lawyer":
			var line = response.get("line")
			var rule = response.get("clause")
			if (typeof(line) != TYPE_INT and typeof(line) != TYPE_FLOAT) or not (rule is String):
				return false
			return int(line) in room.verdict.lines.map(func(n): return int(n)) and rule == str(room.verdict.clause)
	return false
