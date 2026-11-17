extends RefCounted
## Level 4's guide: what each part of the room on screen is and does, in the shape the level
## runner's guide panel shows (ui/instruction_guide.gd). A waveform room gets its gates, each drawn
## as it is in the circuit, and the words for reading its diagram; a pipelining room gets its
## circuit's parts, the pipeline's stages, and the words its questions use.

const TimingVisuals := preload("res://levels/level_4/timing_visuals.gd")
const Style := preload("res://ui/style.gd")

## Every gate and part a circuit can hold. "title" lights the {letters} of its short name, "forms"
## are its equation and its truth table (inputs then output), and "more" says the rest.
const PARTS := {
	"not": {"title": "{NOT} gate (inverter)", "forms": ["Y = NOT A", "0→1   1→0"],
		"more": "Flips its input: the output is 1 when the input is 0, and 0 when it is 1. The small circle means \"inverted\"."},
	"and": {"title": "{AND} gate", "forms": ["Y = A AND B", "00→0  01→0  10→0  11→1"],
		"more": "The output is 1 only while every input is 1. Flat back, round front."},
	"or": {"title": "{OR} gate", "forms": ["Y = A OR B", "00→0  01→1  10→1  11→1"],
		"more": "The output is 1 while at least one input is 1. Curved back, pointed front."},
	"xor": {"title": "e{X}clusive {OR} gate", "forms": ["Y = A XOR B", "00→0  01→1  10→1  11→0"],
		"more": "The output is 1 while the inputs differ. An OR gate with a second curve behind it."},
	"nand": {"title": "{N}ot-{AND} gate", "forms": ["Y = NOT (A AND B)", "00→1  01→1  10→1  11→0"],
		"more": "An AND gate with its output flipped: 0 only while every input is 1."},
	"nor": {"title": "{N}ot-{OR} gate", "forms": ["Y = NOT (A OR B)", "00→1  01→0  10→0  11→0"],
		"more": "An OR gate with its output flipped: 1 only while every input is 0."},
	"dff": {"title": "{D} {f}lip-{f}lop, positive-edge-triggered", "forms": ["rising clock edge: Q = D", "otherwise: Q holds"],
		"more": "One bit of memory. At each rising edge of the clock (the input marked > C) it copies D to Q, and it holds Q steady until the next rising edge, whatever D does in between."},
	"reg": {"title": "{Reg}ister", "forms": ["rising clock edge: Q = D", "otherwise: Q holds"],
		"more": "A row of flip-flops that stores a whole number. It takes its input at each rising clock edge, so a value needs one clock cycle to get from one register to the next."},
	"gold": {"title": "{Pipeline} register", "forms": ["cuts a long path in two", "adds a cycle of latency"],
		"more": "A register added in the middle of a circuit (drawn in gold). Each piece between registers is a stage: the clock only has to cover the longest stage, so it can tick faster."},
	"add": {"title": "{Add}er", "forms": ["s = a + b", "takes its propagation delay"],
		"more": "Combinational logic: its output follows its inputs, one propagation delay later."},
	"mul": {"title": "{Mul}tiplier", "forms": ["p = a × b", "takes its propagation delay"],
		"more": "Combinational logic: its output follows its inputs, one propagation delay later."},
}
## The circuit's pins, which every wave room has.
const PINS := [
	{"code": "A", "title": "{Input} pin", "more": "The square with a circle at the left: a signal that comes from outside the circuit, whose waveform is given. While you point at a moment on the grid, its circle fills in when the signal is 1."},
	{"code": "Y", "title": "{Output} pin", "more": "The double circle at the right: a signal the circuit produces."},
]
## Words for reading a waveform diagram, and when a room uses each.
const TIMING := [
	{"when": "always", "code": "0 / 1", "title": "{Waveform}", "forms": ["high line = 1", "low line = 0"],
		"more": "A signal's value over time, read left to right. An edge is where it changes: rising (0 to 1) or falling (1 to 0)."},
	{"when": "delays", "code": "tpd", "title": "{p}ropagation {d}elay", "forms": ["output changes tpd after its input", ""],
		"more": "How long a gate takes to show a change at its input. A change that passes through several gates arrives after the sum of their delays."},
	{"when": "clock", "code": "clk", "title": "{cl}oc{k}", "forms": ["rising edge: 0 → 1", "period: one full cycle"],
		"more": "A signal that ticks at a steady rate. The dashed lines on the grid mark its rising edges, the only moments a flip-flop looks at D."},
	{"when": "clk-to-q", "code": "clk→q", "title": "{clk-to-q} delay", "forms": ["Q changes clk-to-q after the edge", ""],
		"more": "A flip-flop's own delay: the time from the rising edge until the new value shows on Q."},
]
## The five stages, under either of the names the lectures use.
const STAGES := [
	{"names": ["IF", "F"], "title": "{I}nstruction {F}etch", "more": "Reads the instruction from memory at the PC."},
	{"names": ["ID", "D"], "title": "{I}nstruction {D}ecode", "more": "Splits up the instruction, sets the control signals, and reads the register file. A stalled instruction waits here."},
	{"names": ["EX", "X"], "title": "{Ex}ecute", "more": "The ALU does its work: arithmetic, an address for a load or store, a branch's comparison. Forwarded values arrive here."},
	{"names": ["MEM", "M"], "title": "{Mem}ory", "more": "Reads or writes data memory. Only loads and stores use it; a load's word is ready at the end of this stage."},
	{"names": ["WB", "W"], "title": "{W}rite {B}ack", "more": "Writes the result to the register file. An instruction decoding in the same cycle already reads the new value."},
]
## Words the pipelining questions use; each is listed when one of its "needs" appears in the room.
const WORDS := [
	{"needs": [], "code": "Tclk", "title": "Minimum {clock} period", "forms": ["clk-to-q + longest path", "between two registers"],
		"more": "The clock can tick no faster than the slowest stage allows: the longest path from one register to the next, plus the clk-to-q delay."},
	{"needs": ["latency"], "code": "latency", "title": "{Latency}", "forms": ["time for ONE operation", "cycles × clock period"],
		"more": "How long one operation takes from start to finish. Pipelining usually makes it a little worse."},
	{"needs": ["throughput"], "code": "rate", "title": "{Throughput}", "forms": ["operations finished per second", ""],
		"more": "How much work gets done over time. Pipelining improves it, because a new operation starts every cycle."},
	{"needs": ["speedup"], "code": "speedup", "title": "{Speedup}", "forms": ["old time ÷ new time", "above 1 means faster"],
		"more": "How many times faster the new design finishes the same work."},
	{"needs": ["stalls"], "code": "stall", "title": "{Stall} (bubble)", "forms": ["hold in D one more cycle", "all behind wait too"],
		"more": "An instruction waits in decode because a value it reads is not ready (a data hazard). Without forwarding, it waits until the writer reaches W."},
	{"needs": ["forward"], "code": "fwd", "title": "{Forwarding}", "forms": ["result ready: end of X", "a load's word: end of M"],
		"more": "Hands a result straight into the next instruction's X from a pipeline register (EX/MEM or MEM/WB), without waiting for write back, so most values arrive without a stall. A load's word is only ready at the end of M, so a load followed at once by its use still stalls one cycle."},
	{"needs": ["cpi"], "code": "CPI", "title": "{C}ycles {p}er {i}nstruction", "forms": ["(instructions + stall cycles)", "÷ instructions"],
		"more": "1 for a pipeline that never stalls. Every stall or flushed instruction adds a cycle and pushes it above 1."},
]


## A small drawing of one part, wired to pins, as the room's circuit draws it.
static func icon(op: String) -> Control:
	var spec := {"labels": false, "inputs": [{"name": "A", "at": [0, 0]}], "outputs": ["Y"],
		"gates": [{"out": "Y", "op": "reg" if op == "gold" else op, "in": ["A"], "at": [1, 0], "gold": op == "gold"}]}
	if op in ["and", "or", "xor", "nand", "nor", "add", "mul"]:
		spec.inputs.append({"name": "B", "at": [0, 1]})
		spec.gates[0].in = ["A", "B"]
		spec.gates[0].at = [1, 0.5]
	elif op == "dff":
		spec.inputs = [{"name": "D", "at": [0, 0]}, {"name": "clk", "at": [0, 1]}]
		spec.outputs = ["Q"]
		spec.gates[0] = {"out": "Q", "op": "dff", "in": ["D"], "clk": "clk", "at": [1, 0.5]}
	var view = TimingVisuals.CircuitView.new(spec)
	view.custom_minimum_size = Vector2(190, 92 if spec.inputs.size() > 1 else 58)
	return view

static func _part(op: String) -> Dictionary:
	var entry: Dictionary = PARTS[op].duplicate()
	entry.icon = icon(op)
	entry.color = Style.GOLD if op == "gold" else Style.CYAN
	return entry

static func _word(item: Dictionary) -> Dictionary:
	var entry := {"code": item.code, "color": Style.GOLD, "title": item.title, "more": item.more}
	if item.has("forms"):
		entry.forms = item.forms
	return entry

## The guide for a room, from its payload.
static func for_room(room: Dictionary) -> Dictionary:
	var sections: Array = []
	var ops: Array = []
	for gate in room.get("circuit", {}).get("gates", []):
		var op := "gold" if gate.get("gold", false) and gate.op == "reg" else str(gate.op)
		if PARTS.has(op) and op not in ops:
			ops.append(op)
	if not ops.is_empty():
		var parts: Array = []
		for op in PARTS:  # In the guide's order, not the circuit's.
			if op in ops:
				parts.append(_part(op))
		sections.append({"heading": "Parts of this circuit", "entries": parts})
	if room.kind == "wave":
		var delays: Dictionary = room.get("delays", {})
		var reading: Array = []
		for item in TIMING:
			var used: bool = item.when == "always" or (item.when == "delays" and delays.keys().any(func(op): return op != "dff")) \
				or (item.when == "clock" and room.has("clock")) or (item.when == "clk-to-q" and delays.has("dff"))
			if used:
				reading.append(_word(item))
		for item in PINS:
			reading.append(_word(item))
		sections.append({"heading": "Reading the diagram", "entries": reading})
		return {"title": "Circuit guide", "sections": sections,
			"legend": "Click a gold row of the grid to put an edge where the signal changes. Point at any moment and the circuit shows it: a wire is bright while it carries 1."}
	var chart: Dictionary = room.get("chart", {})
	var stages: Array = []
	for stage in STAGES:
		for name in chart.get("stages", []):
			if name in stage.names:
				stages.append({"code": str(name), "color": Style.PURPLE, "title": stage.title, "more": stage.more})
	if not stages.is_empty():
		sections.append({"heading": "Pipeline stages", "entries": stages})
	# Everything the room says, to find which words it uses.
	var text := " ".join(PackedStringArray(room.get("facts", []) + room.get("columns", []))).to_lower()
	for ask in room.get("asks", []):
		text += " " + str(ask.ask).to_lower()
	for row in room.get("rows", []):
		if row[0] is String:
			text += " " + str(row[0]).to_lower()
	if chart.has("stalls"):
		text += " stalls"
	if chart.get("forwarding", false):
		text += " forward"
	var words: Array = []
	for item in WORDS:
		if item.needs.is_empty() or item.needs.any(func(word): return text.contains(word)):
			words.append(_word(item))
	sections.append({"heading": "Words on this gate", "entries": words})
	var only_circuit: bool = room.has("circuit") and not room.has("chart")
	return {"title": "Circuit guide" if only_circuit else "Pipeline guide", "sections": sections,
		"legend": "Registers pass values on at each clock tick; everything between two registers has to finish within one clock period." if only_circuit
			else "A pipeline diagram has a row for each instruction and a column for each clock cycle; a cell names the stage the instruction is in."}
