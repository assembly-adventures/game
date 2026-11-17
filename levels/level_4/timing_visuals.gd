extends RefCounted
## What Level 4's rooms draw: a circuit of gates, flip-flops, and pipeline registers; the timing
## grid a waveform is drawn on; and the pipeline diagram (one row per instruction, one column per
## cycle). Colours, fonts, and drawing helpers come from ui/style.gd.

const Style := preload("res://ui/style.gd")
const BG := Style.BG
const CYAN := Style.CYAN
const PURPLE := Style.PURPLE
const GOLD := Style.GOLD
const GREEN := Style.GREEN
const RED := Style.RED
const ORANGE := Style.ORANGE
const DIM := Style.DIM
const SOCKET := Style.SOCKET
const TEXT := Style.TEXT
const MONO := Style.MONO


## A room's circuit, from its payload: `inputs` (named wires that start at the left), `gates`
## (each with its output's name, its `op`, its input signals, and where it sits on a grid of
## columns and rows), and `outputs` (signals that leave to the right). Gates are not, and, or,
## xor, nand, nor; a `dff` with its clock; and, for the pipelining rooms, `reg` (a register,
## gold when it is a pipeline register), `add`, `mul`, and `box` (a labelled block). With
## `labels`, every wire is named. `notes` puts a line under a gate (its delay), by output name.
## Parts are drawn the way the lectures' circuits are (Logisim's look): white bodies with dark
## outlines, a square pin with a circle for each input (a square wave for a clock), a double
## circle for each output, and boxes captioned Reg and Add. A pin's circle fills in while its
## signal is 1.
class CircuitView extends Control:
	const BODY := Color("eceff4")
	const INK := Color("0c0f16")
	const LETTER := Color("5d6573")
	const PIN := 16.0
	var circuit: Dictionary
	var notes: Dictionary = {}
	var lit := ""  # A signal to pick out: the one being drawn.
	var levels: Dictionary = {}  # Signal name: 0 or 1 at the moment being looked at; empty when none is.
	var ghost := false  # Draws the gold pipeline registers as empty outlines: the circuit without them.
	var unit := Vector2(80, 50)
	var origin := Vector2.ZERO
	var gate_size := Vector2(44, 34)
	var outs: Dictionary = {}  # Signal name: where its wire starts.

	func _init(spec: Dictionary, gate_notes: Dictionary = {}) -> void:
		circuit = spec
		notes = gate_notes
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rows := 0.0
		for item in spec.get("inputs", []) + spec.get("gates", []):
			rows = maxf(rows, float(item.at[1]))
		custom_minimum_size = Vector2(220, 46 + rows * 26 + (12 if not notes.is_empty() else 0))
		resized.connect(queue_redraw)

	func highlight(name: String) -> void:
		if lit != name:
			lit = name
			queue_redraw()

	func _place() -> void:
		var cols := 0.0
		var rows := 0.0
		for item in circuit.get("inputs", []) + circuit.get("gates", []):
			cols = maxf(cols, float(item.at[0]))
			rows = maxf(rows, float(item.at[1]))
		var has_inputs: bool = not circuit.get("inputs", []).is_empty()
		var has_outputs: bool = not circuit.get("outputs", []).is_empty()
		var top := 16.0 if circuit.get("labels", false) else 6.0
		var captioned: bool = circuit.get("gates", []).any(func(gate): return str(gate.op) in ["reg", "add", "mul"])
		var bottom := 16.0 if not notes.is_empty() or captioned else 6.0
		unit.y = clampf((size.y - top - bottom - 30.0) / maxf(rows, 1.0), 18.0, 58.0)
		gate_size.y = clampf(unit.y * 0.74, 22.0, 38.0) if rows > 0 else clampf(size.y - top - bottom, 22.0, 44.0)
		var left := 44.0 + PIN if has_inputs else 0.0
		var right := 58.0 if has_outputs else 0.0
		unit.x = clampf((size.x - left - right - 8.0) / (cols + 1.2), 24.0, 118.0)
		gate_size.x = clampf(unit.x * 0.5, 26.0, 46.0)
		var half := _size_of("box").x / 2.0 if not has_inputs else 0.0
		var used := Vector2(left + half + cols * unit.x + _size_of("box").x / 2.0 + right, top + rows * unit.y + gate_size.y + bottom)
		origin = Vector2(maxf((size.x - used.x) / 2.0, 0.0) + left + half,
			maxf((size.y - used.y) / 2.0, 0.0) + top + gate_size.y / 2.0)

	func _at(item: Dictionary) -> Vector2:
		return origin + Vector2(float(item.at[0]) * unit.x, float(item.at[1]) * unit.y)

	func _size_of(op: String) -> Vector2:
		match op:
			"dff":
				return Vector2(maxf(gate_size.x, 50.0), unit.y + 26.0)
			"reg":
				return Vector2(clampf(unit.x * 0.36, 18.0, 30.0), gate_size.y + 2.0)
			"box":
				return Vector2(minf(unit.x * 1.12, 86.0), gate_size.y)
			"add", "mul":
				return Vector2(clampf(unit.x * 0.42, 24.0, 34.0), gate_size.y + 2.0)
			"not":
				return gate_size * 0.8  # The lectures' inverter is a small triangle.
		return gate_size

	## Where a gate's input `k` lands on its left side.
	func _pin(gate: Dictionary, k: int) -> Vector2:
		var at := _at(gate)
		var box := _size_of(str(gate.op))
		if gate.op == "dff":
			return at + Vector2(-box.x / 2.0, -unit.y / 2.0 if k == 0 else unit.y / 2.0)
		var count: int = gate.in.size()
		var inset := box.x * 0.1 if str(gate.op) in ["or", "nor", "xor"] else 0.0
		return at + Vector2(-box.x / 2.0 + inset, (k - (count - 1) / 2.0) * box.y * 0.5)

	func _out(gate: Dictionary) -> Vector2:
		var at := _at(gate)
		var box := _size_of(str(gate.op))
		return at + Vector2(box.x / 2.0, -unit.y / 2.0 if gate.op == "dff" else 0.0)

	func _draw() -> void:
		_place()
		var font := get_theme_default_font()
		var labels: bool = circuit.get("labels", false)
		outs.clear()
		var clocks := {}
		for gate in circuit.get("gates", []):
			if gate.has("clk"):
				clocks[str(gate.clk)] = true
		for input in circuit.get("inputs", []):
			var at := _at(input)
			var name := str(input.name)
			outs[name] = at
			# The input's pin: a square with a circle in it, or a square wave for a clock.
			var pin := Rect2(at.x - PIN, at.y - PIN / 2.0, PIN, PIN)
			draw_rect(pin, BODY)
			draw_rect(pin, INK, false, 2.0)
			var middle := pin.get_center()
			if clocks.has(name):
				draw_polyline(PackedVector2Array([middle + Vector2(-5, 3), middle + Vector2(-2, 3), middle + Vector2(-2, -3),
					middle + Vector2(2, -3), middle + Vector2(2, 3), middle + Vector2(5, 3)]), INK, 1.5)
			else:
				draw_circle(middle, 4.5, _pin_fill(name))
				draw_arc(middle, 4.5, 0, TAU, 20, INK, 1.5, true)
			draw_string(MONO, Vector2(pin.position.x - 40, at.y + 5), name, HORIZONTAL_ALIGNMENT_RIGHT, 34, 14, _wire_color(name))
		for gate in circuit.get("gates", []):
			outs[str(gate.out)] = _out(gate)
		# Wires first, so each gate's body covers where they end.
		for gate in circuit.get("gates", []):
			var sources: Array = gate.in.duplicate()
			if gate.has("clk"):
				sources.append(gate.clk)
			for k in range(sources.size()):
				var from: Vector2 = outs[str(sources[k])]
				var to := _pin(gate, k)
				var color := _wire_color(str(sources[k]))
				var width := _wire_width(str(sources[k]))
				if absf(from.y - to.y) < 1.0:
					draw_line(from, to, color, width, true)
				else:
					var bend := maxf(to.x - 12.0 - 7.0 * k, from.x + 6.0)
					draw_polyline(PackedVector2Array([from, Vector2(bend, from.y), Vector2(bend, to.y), to]), color, width, true)
		for name in circuit.get("outputs", []):
			var from: Vector2 = outs[str(name)]
			var color := _wire_color(str(name))
			draw_line(from, from + Vector2(18, 0), color, _wire_width(str(name)), true)
			# The output's pin: a double circle.
			var middle := from + Vector2(27, 0)
			draw_circle(middle, 9.0, BODY)
			draw_arc(middle, 9.0, 0, TAU, 28, INK, 2.0, true)
			draw_circle(middle, 4.5, _pin_fill(str(name)))
			draw_arc(middle, 4.5, 0, TAU, 20, INK, 1.5, true)
			draw_string(MONO, from + Vector2(42, 5), str(name), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
		for gate in circuit.get("gates", []):
			_draw_gate(gate, font)
			var name := str(gate.out)
			if labels and name not in circuit.get("outputs", []):
				draw_string(MONO, outs[name] + Vector2(5, -6), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, _wire_color(name))
			if notes.has(name):
				var at := _at(gate)
				var box := _size_of(str(gate.op))
				draw_string(font, at + Vector2(-60, box.y / 2.0 + 13), str(notes[name]), HORIZONTAL_ALIGNMENT_CENTER, 120, 11,
					Color(TEXT, 0.6))

	## Shows every wire as it is at one moment: bright for 1, dim for 0. Empty shows plain wires.
	func show_levels(now: Dictionary) -> void:
		levels = now
		queue_redraw()

	func _wire_color(name: String) -> Color:
		var tint := GOLD if name == lit else CYAN
		if levels.has(name):
			return tint if int(levels[name]) == 1 else Color(tint, 0.28)
		return tint if name == lit else Color(CYAN, 0.75)

	## A pin's circle: filled while its signal is 1 (when the circuit is showing a moment).
	func _pin_fill(name: String) -> Color:
		return CYAN.darkened(0.15) if int(levels.get(name, 0)) == 1 else BODY

	func _wire_width(name: String) -> float:
		return 3.0 if int(levels.get(name, 0)) == 1 else 2.0

	func _draw_gate(gate: Dictionary, font: Font) -> void:
		var op := str(gate.op)
		var at := _at(gate)
		var box := _size_of(op)
		var rect := Rect2(at - box / 2.0, box)
		var gold: bool = gate.get("gold", false)
		if gold and ghost:
			draw_line(Vector2(rect.position.x, at.y), Vector2(rect.end.x, at.y), Color(CYAN, 0.75), 2.0, true)
			Style.dashed_box(self, rect, Color(GOLD, 0.45), 1.5, 4.0)
			return
		var edge := GOLD.darkened(0.25) if gold else INK
		var fill := Color("ffe7a3") if gold else BODY
		var caption := ""
		match op:
			"dff", "reg":
				draw_rect(rect, fill)
				draw_rect(rect, edge, false, 3.0)
				# The clock input's wedge, with the pins lettered as the lectures letter them.
				var clock := at + Vector2(-box.x / 2.0, unit.y / 2.0 if op == "dff" else box.y * 0.22)
				draw_polyline(PackedVector2Array([clock + Vector2(1, -5), clock + Vector2(7, 0), clock + Vector2(1, 5)]), INK, 1.5, true)
				if op == "dff":
					draw_string(MONO, Vector2(rect.position.x + 6, at.y - unit.y / 2.0 + 5), "D", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, LETTER)
					draw_string(MONO, Vector2(rect.position.x + 11, clock.y + 5), "C", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, LETTER)
					draw_string(MONO, Vector2(rect.end.x - 15, at.y - unit.y / 2.0 + 5), "Q", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, LETTER)
				else:
					caption = "Reg"
			"box":
				Style.rounded(self, rect, BODY, 3, INK, 2)
				var lines := str(gate.get("label", gate.out)).split("\n")
				for k in range(lines.size()):
					var small := k > 0
					draw_string(font, Vector2(rect.position.x, at.y + (k - (lines.size() - 1) / 2.0) * 13.0 + 4.0), lines[k],
						HORIZONTAL_ALIGNMENT_CENTER, box.x, 10 if small else 13, LETTER if small else INK)
			"add", "mul":
				draw_rect(rect, BODY)
				draw_rect(rect, INK, false, 3.0)
				var arm := minf(box.x, box.y) * 0.24
				var turn := 0.0 if op == "add" else PI / 4.0
				for angle in [turn, turn + PI / 2.0]:
					var reach := Vector2(arm, 0).rotated(angle)
					draw_line(at - reach, at + reach, INK, 2.5, true)
				caption = "Add" if op == "add" else "Mul"
			_:
				var bubble := op in ["not", "nand", "nor"]
				var dot := clampf(box.y * 0.2, 4.0, 5.5)
				var body := Rect2(rect.position, Vector2(box.x - (dot * 2.0 if bubble else 0.0), box.y))
				var shape := _outline(op, body)
				draw_colored_polygon(shape, BODY)
				shape.append(shape[0])
				draw_polyline(shape, INK, 2.5, true)
				if op == "xor":
					var back := PackedVector2Array()
					for k in range(13):
						var t := k / 12.0
						back.append(Vector2(body.position.x - 6.0 + sin(t * PI) * body.size.x * 0.18, body.position.y + t * body.size.y))
					draw_polyline(back, BODY, 2.0, true)
				if bubble:
					var center := Vector2(body.end.x + dot, at.y)
					draw_circle(center, dot, BODY)
					draw_arc(center, dot, 0, TAU, 20, INK, 1.5, true)
		if not caption.is_empty() and (unit.y - box.y >= 13.0 or float(gate.at[1]) != floorf(float(gate.at[1]))):  # Only where there is room under it.
			draw_string(font, Vector2(at.x - 30, rect.end.y + 11), caption, HORIZONTAL_ALIGNMENT_CENTER, 60, 10,
				GOLD if gold else Color(TEXT, 0.55))

	## A gate's body: a triangle (not), a flat back and round front (and), or a curved back and
	## pointed front (or).
	func _outline(op: String, body: Rect2) -> PackedVector2Array:
		var points := PackedVector2Array()
		var middle := body.position.y + body.size.y / 2.0
		if op == "not":
			return PackedVector2Array([body.position, Vector2(body.end.x, middle), Vector2(body.position.x, body.end.y)])
		if op in ["and", "nand"]:
			var radius := body.size.y / 2.0
			points.append(body.position)
			for k in range(17):
				var angle := -PI / 2.0 + PI * k / 16.0
				points.append(Vector2(body.end.x - radius, middle) + Vector2(cos(angle), sin(angle)) * radius)
			points.append(Vector2(body.position.x, body.end.y))
			return points
		for k in range(13):  # Along the top to the point.
			var t := k / 12.0
			points.append(_curve(body.position, Vector2(body.position.x + body.size.x * 0.62, body.position.y), Vector2(body.end.x, middle), t))
		for k in range(1, 13):  # Back along the bottom.
			var t := k / 12.0
			points.append(_curve(Vector2(body.end.x, middle), Vector2(body.position.x + body.size.x * 0.62, body.end.y),
				Vector2(body.position.x, body.end.y), t))
		for k in range(1, 12):  # Up the curved back.
			var t := 1.0 - k / 12.0
			points.append(Vector2(body.position.x + sin(t * PI) * body.size.x * 0.18, body.position.y + t * body.size.y))
		return points

	func _curve(a: Vector2, b: Vector2, c: Vector2, t: float) -> Vector2:
		return a.lerp(b, t).lerp(b.lerp(c, t), t)


## The timing grid of a wave room: one row per signal, one column per tick. Given signals (the
## inputs and the clock) are drawn already, and each row to draw starts as a flat line at the
## signal's first level. A click in a row to draw puts an edge at the nearest grid line: the signal
## flips from there to the end, so a click on an edge takes it away again. The grid also points at
## a moment (under the mouse, or swept along by a check), which the room shows on the circuit.
class WaveGrid extends Control:
	signal stroke  ## A click is about to change a row; emitted first, for Undo.
	signal changed(name: String)
	signal hovered(name: String)
	signal pointed(tick: int)  ## The moment under the mouse; -1 when it leaves.
	const LABEL := 50.0
	const AXIS := 20.0
	var rows: Array = []  # {"name", "wave": levels, "draw": bool, "clock": bool}
	var ticks := 0
	var tick_time := 1.0
	var unit := ""
	var rises: Array = []  # Ticks where the clock rises, marked down the whole grid.
	var editable := true
	var wrong: Dictionary = {}  # Names of drawn rows that don't match the circuit.
	var won := false
	var hover_row := -1
	var hover_edge := -1  # The grid line a click would put an edge on.
	var cursor := -1.0  # A moment to mark down the whole grid, in ticks; -1 for none.
	var flag := Vector2i(-1, -1)  # (tick, row) where a check first found the drawing wrong.

	## A time as the axis says it: 60, or 2.5.
	static func time_text(value: float) -> String:
		return str(int(round(value))) if is_equal_approx(value, round(value)) else str(snappedf(value, 0.01))

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_exited.connect(func():
			hover_row = -1
			hovered.emit("")
			pointed.emit(-1)
			queue_redraw())
		resized.connect(queue_redraw)

	func setup() -> void:
		custom_minimum_size = Vector2(LABEL + ticks * 8.0 + 12.0, AXIS + rows.size() * 24.0 + 4.0)
		queue_redraw()

	func _tick_width() -> float:
		return minf(56.0, (size.x - LABEL - 14.0) / maxi(ticks, 1))

	func _row_height() -> float:
		return minf(54.0, (size.y - AXIS - 4.0) / maxi(rows.size(), 1))

	func _gui_input(event: InputEvent) -> void:
		if not (event is InputEventMouse):
			return
		var tick_w := _tick_width()
		var row := int(floor((event.position.y - AXIS) / _row_height()))
		var inside: bool = row >= 0 and row < rows.size() and event.position.x >= LABEL - 4.0
		var edge := clampi(int(round((event.position.x - LABEL) / tick_w)), 1, ticks - 1)
		if event is InputEventMouseMotion:
			var shown := row if inside else -1
			pointed.emit(clampi(int(floor((event.position.x - LABEL) / tick_w)), 0, ticks - 1) if inside else -1)
			if shown != hover_row or edge != hover_edge:
				if shown != hover_row:
					hovered.emit(str(rows[shown].name) if shown >= 0 else "")
				hover_row = shown
				hover_edge = edge
				queue_redraw()
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed and editable and inside and rows[row].draw:
			stroke.emit()
			flip(row, edge)
			accept_event()

	## Puts an edge at a grid line of a row, or takes away the one there.
	func flip(row: int, edge: int) -> void:
		var wave: Array = rows[row].wave
		for tick in range(edge, ticks):
			wave[tick] = 1 - int(wave[tick])
		wrong.erase(rows[row].name)
		flag = Vector2i(-1, -1)
		Audio.play("press", -8.0, 0.15)
		changed.emit(str(rows[row].name))
		queue_redraw()

	func _draw() -> void:
		var font := get_theme_default_font()
		var row_h := _row_height()
		var tick_w := _tick_width()
		var right := LABEL + ticks * tick_w
		var foot := AXIS + rows.size() * row_h
		# The time axis: a label wherever there is room for one.
		var every := 1
		for candidate in [1, 2, 4, 5, 10, 20, 40]:
			every = candidate
			if candidate * tick_w >= 40.0:
				break
		draw_string(font, Vector2(0, 14), unit, HORIZONTAL_ALIGNMENT_RIGHT, LABEL - 10, 12, Color(TEXT, 0.55))
		for tick in range(ticks + 1):
			var x := LABEL + tick * tick_w
			var major := tick % every == 0
			draw_line(Vector2(x, AXIS), Vector2(x, foot), Color(TEXT, 0.16 if major else 0.06), 1.0)
			if major:
				draw_string(font, Vector2(x - 30, 14), time_text(tick * tick_time), HORIZONTAL_ALIGNMENT_CENTER, 60, 12,
					Color(TEXT, 0.6))
		for tick in rises:
			var x := LABEL + int(tick) * tick_w
			draw_dashed_line(Vector2(x, AXIS), Vector2(x, foot), Color(PURPLE, 0.55), 1.0, 4.0)
		for r in range(rows.size()):
			var row: Dictionary = rows[r]
			var top := AXIS + r * row_h
			var high := top + row_h * 0.2
			var low := top + row_h * 0.8
			var color := PURPLE if row.clock else CYAN
			if row.draw:
				color = GREEN if won else RED if wrong.has(row.name) else GOLD
				draw_rect(Rect2(LABEL, top + 1, right - LABEL, row_h - 2), Color(color, 0.07))
			draw_line(Vector2(0, top + row_h), Vector2(right, top + row_h), Color(TEXT, 0.08), 1.0)
			draw_string(MONO, Vector2(0, top + row_h / 2.0 + 6), str(row.name), HORIZONTAL_ALIGNMENT_RIGHT, LABEL - 10, 15, color)
			var wave: Array = row.wave
			var line := PackedVector2Array()
			for tick in range(ticks):
				var y := high if int(wave[tick]) == 1 else low
				line.append(Vector2(LABEL + tick * tick_w, y))
				line.append(Vector2(LABEL + (tick + 1) * tick_w, y))
			draw_polyline(line, color, 3.0 if won or row.draw else 2.5, true)
			if row.draw and r == hover_row and editable:
				# Where a click would put an edge (or the edge it would take away), and its time.
				var x := LABEL + hover_edge * tick_w
				var there: bool = int(wave[hover_edge]) != int(wave[hover_edge - 1])
				draw_dashed_line(Vector2(x, top + 2), Vector2(x, top + row_h - 2), Color.WHITE if there else Color(GOLD, 0.9), 2.0, 3.0)
				var words := "%s %s" % [time_text(hover_edge * tick_time), unit]
				var at := Vector2(x + 6, top + row_h / 2.0 + 4)
				if x + 70 > right:
					at.x = x - 66
				Style.rounded(self, Rect2(at.x - 3, at.y - 12, 62, 16), Color(BG, 0.9), 4)
				draw_string(font, at, words, HORIZONTAL_ALIGNMENT_LEFT, 58, 11, GOLD)
		if cursor >= 0.0:
			var x := LABEL + cursor * tick_w
			draw_line(Vector2(x, AXIS - 4), Vector2(x, foot), Color(TEXT, 0.85), 1.5)
			draw_colored_polygon(PackedVector2Array([Vector2(x - 5, AXIS - 9), Vector2(x + 5, AXIS - 9), Vector2(x, AXIS - 2)]), TEXT)
		if flag.x >= 0:
			var at := Vector2(LABEL + flag.x * tick_w, AXIS + (flag.y + 0.5) * row_h)
			draw_arc(at, row_h * 0.42, 0, TAU, 32, RED, 2.5, true)


## A pipeline diagram: a row per instruction, a column per clock cycle, and in each cell the stage
## the instruction is in. It is filled in one of two ways. With `starts`, a click sets the cycle a
## row's first stage is in and the rest follow. With `stalls`, every instruction is fetched as
## early as it can be, and - and + beside a row hold it in its second stage (decode) for more or
## fewer cycles, which repeats that stage and holds back every row behind it. After a run, a
## stalls diagram draws an arrow for each value a line reads from one of the two lines above it,
## green when it arrived in time and red when it was read too early.
class PipelineChart extends Control:
	signal changed
	var row_h := 24.0  # A row's height: shorter in a diagram with many rows, so it fits the room.
	const HEAD := 18.0
	const KEYS := 62.0  # The - and + of a row, and its count between them.
	var spec: Dictionary
	var stages: Array = []
	var cycles := 0
	var stalling := false
	var marks: Array = []  # Per row: its start cycle (-1 until placed), or its stall cycles.
	var editable := true
	var wrong: Dictionary = {}  # Rows whose mark is wrong.
	var won := false
	var label_width := 60.0
	var hover := Vector2i(-1, -1)
	var cursor := -1  # A cycle to light up, while a check plays the diagram.
	var forwarding := false  # Whether results are forwarded into X (else a read waits for W).
	var needs: Array = []  # Each read that could come too early: {"reader", "writer", "reg", "load"}.
	var revealed := false  # A run has played, so its arrows show (until the plan changes).

	func _init(chart: Dictionary) -> void:
		spec = chart
		forwarding = chart.get("forwarding", false)
		if chart.has("stalls"):
			needs = reads(chart.rows)
		stages = chart.stages
		cycles = int(chart.cycles)
		stalling = chart.has("stalls")
		for row in chart.rows:
			marks.append(0 if stalling else -1)
			label_width = maxf(label_width, MONO.get_string_size(str(row), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 12.0)
		row_h = 24.0 if chart.rows.size() <= 6 else 20.0
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(_left() + cycles * 22.0 + 2.0, HEAD + chart.rows.size() * row_h + 2.0)
		mouse_exited.connect(func():
			hover = Vector2i(-1, -1)
			queue_redraw())
		resized.connect(queue_redraw)

	func _left() -> float:
		return label_width + (KEYS if stalling else 0.0)

	func _cell_width() -> float:
		return minf(44.0, (size.x - _left() - 2.0) / cycles)

	func complete() -> bool:
		return stalling or not marks.has(-1)

	func clear() -> void:
		for r in range(marks.size()):
			marks[r] = 0 if stalling else -1
		revealed = false
		wrong.clear()
		changed.emit()
		queue_redraw()

	## Each row's cells: [cycle, stage index, whether it is a held repeat of the stage].
	func schedule(with: Array = marks) -> Array:
		var plan: Array = []
		var decode := 1  # The cycle the row is first in its second stage.
		for r in range(with.size()):
			var cells: Array = []
			if not stalling:
				if int(with[r]) >= 0:
					for k in range(stages.size()):
						cells.append([int(with[r]) + k, k, false])
				plan.append(cells)
				continue
			var fetch := decode - 1
			if r > 0:
				# Fetched when the row ahead moved into decode; decodes once that row has left it.
				var ahead: Array = plan[r - 1]
				fetch = decode
				for cell in ahead:
					if cell[1] == 2:
						decode = cell[0]
			for cycle in range(fetch, decode):
				cells.append([cycle, 0, cycle > fetch])
			for k in range(int(with[r]) + 1):
				cells.append([decode + k, 1, k > 0])
			for k in range(2, stages.size()):
				cells.append([decode + int(with[r]) + k - 1, k, false])
			plan.append(cells)
		return plan

	## The cycles the whole diagram takes.
	func length(with: Array = marks) -> int:
		var last := 0
		for cells in schedule(with):
			for cell in cells:
				last = maxi(last, cell[0] + 1)
		return last

	## A line's words, without its commas and parentheses.
	static func _words(line: String) -> PackedStringArray:
		return line.replace(",", " ").replace("(", " ").replace(")", " ").split(" ", false)

	## The registers a line reads, in mux order: rs1 (ForwardA), then rs2 (ForwardB). A line is
	## "op rd, rs1, rs2" or "op rd, rs1, imm", a load "lw rd, off(rs1)", a store
	## "sw rs2, off(rs1)", or a branch "beq rs1, rs2, label".
	static func operands(line: String) -> Array:
		var words := _words(line)
		if words[0] == "lw":
			return [words[3]]
		if words[0] == "sw":
			return [words[3], words[1]]
		var found: Array = []
		for k in range(1 if words[0].begins_with("b") else 2, words.size()):
			if words[k].begins_with("x") and words[k].substr(1).is_valid_int():
				found.append(words[k])
		return found

	## The register a line writes, or "" (stores and branches write none).
	static func target(line: String) -> String:
		var words := _words(line)
		return "" if words[0] == "sw" or words[0].begins_with("b") else words[1]

	## The nearest line above `reader` that writes `reg`, or -1.
	static func writer_of(lines: Array, reader: int, reg: String) -> int:
		for w in range(reader - 1, -1, -1):
			if target(str(lines[w])) == reg:
				return w
		return -1

	## The reads in a program that depend on one of the two lines above them (from further back,
	## the value is always written in time).
	static func reads(lines: Array) -> Array:
		var found: Array = []
		for r in range(lines.size()):
			var seen := {}
			for reg in operands(str(lines[r])):
				if reg == "x0" or seen.has(reg):
					continue
				seen[reg] = true
				var w := writer_of(lines, r, reg)
				if w >= 0 and w >= r - 2:
					found.append({"reader": r, "writer": w, "reg": reg, "load": str(lines[w]).begins_with("lw")})
		return found

	## Each read that depends on a line just above as an arrow: the cell the value comes from, the
	## cell that reads it, whether it is there in time, and (with forwarding) the mux setting that
	## brings it. Without forwarding a value is there once it is written (W) and is read in D. With
	## it, a result is ready at the end of X (a load's word, of M) and is read in X: from EX/MEM
	## ("10") while its writer is in M, from MEM/WB ("01") while it is in W. A writer that has
	## already finished left it in the register file ("00"), read in D like any other register.
	## A forwarded arrow runs from the end of one stage to the start of the other ("edge").
	func arrows(with: Array = marks) -> Array:
		var plan := schedule(with)
		var drawn: Array = []
		for need in needs:
			var writer: Array = plan[need.writer]
			var reader: Array = plan[need.reader]
			var arrow := {"text": str(need.reg), "code": "", "edge": false}
			if not forwarding:
				arrow.from = Vector2i(_cycle_of(writer, 4), need.writer)
				arrow.to = Vector2i(_cycle_of(reader, 1), need.reader)
				arrow.ok = arrow.to.x >= arrow.from.x
			else:
				var execute := _cycle_of(reader, 2)
				arrow.ok = execute > _cycle_of(writer, 3 if need.load else 2)
				var gap := execute - _cycle_of(writer, 2)
				arrow.code = "" if not arrow.ok else "10" if gap == 1 else "01" if gap == 2 else "00"
				var from_stage: int = {"10": 2, "01": 3, "00": 4}.get(arrow.code, 3 if need.load else 2)
				arrow.edge = arrow.code != "00"
				arrow.from = Vector2i(_cycle_of(writer, from_stage), need.writer)
				arrow.to = Vector2i(_cycle_of(reader, 1 if arrow.code == "00" else 2), need.reader)
			drawn.append(arrow)
		return drawn

	## The last cycle a row spends in a stage.
	func _cycle_of(cells: Array, stage: int) -> int:
		var last := -1
		for cell in cells:
			if cell[1] == stage:
				last = cell[0]
		return last

	## Whether every needed value arrives in time.
	func flows(with: Array = marks) -> bool:
		return arrows(with).all(func(arrow): return arrow.ok)

	## What is wrong with the plan, in words, or "" when nothing is found: two rows in one stage, the
	## first read that comes too early, or extra stalls. Cycles are named as the diagram numbers
	## them, from 1.
	func problem() -> String:
		if not stalling:
			if not clashes().is_empty():
				return "Two rows are in the same stage at once!"
			return "" if marks == spec.starts.map(func(start): return int(start)) \
				else "Nothing collides, but each row should start as soon as the row above lets it."
		var found := arrows()
		for k in range(needs.size()):
			if found[k].ok:
				continue
			var need: Dictionary = needs[k]
			var line := str(spec.rows[need.reader])
			var writer := str(spec.rows[need.writer])
			if not forwarding:
				return "%s reads %s in D in cycle %d, but %s only writes it in W in cycle %d." % [line, need.reg,
					found[k].to.x + 1, writer, found[k].from.x + 1]
			return "%s needs %s in X in cycle %d, but %s only has it at the end of %s, in cycle %d." % [line, need.reg,
				found[k].to.x + 1, writer, "M" if need.load else "X", found[k].from.x + 1]
		var best: Array = spec.stalls.map(func(count): return int(count))
		if marks != best:
			var took := length()
			var fastest := length(best)
			if took > fastest:
				return "Every value arrives in time, but the program takes %d cycles. It can finish in %d." % [took, fastest]
			return "Every value arrives in time, but the stalls are in the wrong places."
		return ""

	## Cells where two rows are in the same stage in the same cycle, as (cycle, row).
	func clashes() -> Dictionary:
		var seen := {}
		var bad := {}
		var plan := schedule()
		for r in range(plan.size()):
			for cell in plan[r]:
				var spot := Vector2i(cell[0], cell[1])
				if seen.has(spot):
					bad[Vector2i(cell[0], r)] = true
					bad[Vector2i(cell[0], seen[spot])] = true
				seen[spot] = r
		return bad

	func _can_add(row: int) -> bool:
		var more := marks.duplicate()
		more[row] += 1
		return length(more) <= cycles

	func _gui_input(event: InputEvent) -> void:
		var cell_w := _cell_width()
		if event is InputEventMouseMotion:
			var at := Vector2i(int(floor((event.position.x - _left()) / cell_w)), int(floor((event.position.y - HEAD) / row_h)))
			if event.position.x < _left():
				at.x = -2 if event.position.x < label_width + KEYS / 2.0 else -1  # Over - or +.
			if at != hover:
				hover = at
				queue_redraw()
		if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or not editable:
			return
		var row := int(floor((event.position.y - HEAD) / row_h))
		if row < 0 or row >= marks.size():
			return
		if stalling:
			var x: float = event.position.x - label_width
			if x < 0 or x > KEYS:
				return
			var step := -1 if x < KEYS / 2.0 else 1
			if (step < 0 and marks[row] == 0) or (step > 0 and not _can_add(row)):
				return
			marks[row] += step
		else:
			var cycle := int(floor((event.position.x - _left()) / cell_w))
			if cycle < 0 or cycle + stages.size() > cycles:
				return
			marks[row] = -1 if marks[row] == cycle else cycle
		wrong.erase(row)
		revealed = false
		Audio.play("press", -8.0, 0.1)
		changed.emit()
		queue_redraw()
		accept_event()

	## Where an arrow leaves a cell (or, `start` false, where it enters one).
	func _point(cell: Vector2i, start: bool, edge: bool) -> Vector2:
		var cell_w := _cell_width()
		var at := Vector2(_left() + (cell.x + 0.5) * cell_w, HEAD + (cell.y + 1) * row_h - 3.0 if start else HEAD + cell.y * row_h + 4.0)
		if edge:  # A forwarded value leaves the end of one stage and enters the start of another.
			at.x += cell_w * (0.38 if start else -0.38)
		return at

	func _draw() -> void:
		var font := get_theme_default_font()
		var cell_w := _cell_width()
		var left := _left()
		var palette := [CYAN, PURPLE, GREEN, ORANGE, GOLD]
		draw_string(font, Vector2(0, 13), "cycle", HORIZONTAL_ALIGNMENT_RIGHT, left - 8, 11, Color(TEXT, 0.5))
		for cycle in range(cycles):
			draw_string(font, Vector2(left + cycle * cell_w, 13), str(cycle + 1), HORIZONTAL_ALIGNMENT_CENTER, cell_w, 11, Color(TEXT, 0.55))
		var plan := schedule()
		var clash := {} if stalling else clashes()
		if cursor >= 0:
			draw_rect(Rect2(left + cursor * cell_w, 0, cell_w, HEAD + marks.size() * row_h), Color(TEXT, 0.12))
		for r in range(marks.size()):
			var top := HEAD + r * row_h
			var name_color := GREEN if won else RED if wrong.has(r) else TEXT
			draw_string(MONO, Vector2(0, top + row_h / 2.0 + 5.0), str(spec.rows[r]), HORIZONTAL_ALIGNMENT_LEFT, label_width, 13, name_color)
			for cycle in range(cycles):
				Style.rounded(self, Rect2(left + cycle * cell_w + 1, top + 1, cell_w - 2, row_h - 2), Color(SOCKET, 0.55), 3)
			if stalling:
				for side in [0, 1]:
					var can: bool = editable and (marks[r] > 0 if side == 0 else _can_add(r))
					var key := Rect2(label_width + side * (KEYS - 22.0), top + 2, 20, row_h - 4)
					var over: bool = hover.y == r and hover.x == side - 2 and can
					Style.rounded(self, key, Color(GOLD, 0.3 if over else 0.12) if can else Color(SOCKET, 0.5), 4,
						GOLD if can else DIM, 1)
					draw_string(font, Vector2(key.position.x, top + row_h / 2.0 + 5.0), "−" if side == 0 else "+", HORIZONTAL_ALIGNMENT_CENTER, 20, 14,
						GOLD if can else DIM)
				draw_string(MONO, Vector2(label_width + 20, top + row_h / 2.0 + 5.0), str(marks[r]), HORIZONTAL_ALIGNMENT_CENTER, KEYS - 42.0, 13,
					GOLD if marks[r] > 0 else Color(TEXT, 0.45))
			elif plan[r].is_empty() or (hover.y == r and editable):
				# A row not placed yet asks for a click; hovering shows where the stages would go.
				var from := hover.x if hover.y == r else -1
				if from >= 0 and from + stages.size() <= cycles and from != marks[r]:
					for k in range(stages.size()):
						Style.dashed_box(self, Rect2(left + (from + k) * cell_w + 2, top + 2, cell_w - 4, row_h - 4), Color(palette[k % 5], 0.7), 1.0, 3.0)
				elif plan[r].is_empty():
					draw_string(font, Vector2(left + 6, top + row_h / 2.0 + 4.0), "click a cycle", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(GOLD, 0.7))
			for cell in plan[r]:
				var color: Color = GREEN if won else RED if clash.has(Vector2i(cell[0], r)) else palette[int(cell[1]) % 5]
				var box := Rect2(left + cell[0] * cell_w + 1, top + 1, cell_w - 2, row_h - 2)
				Style.rounded(self, box, Color(color, 0.12 if cell[2] else 0.3), 3, Color(color, 0.5 if cell[2] else 1.0), 1)
				draw_string(MONO, Vector2(box.position.x, top + row_h / 2.0 + 5.0), str(stages[cell[1]]), HORIZONTAL_ALIGNMENT_CENTER, box.size.x,
					11 if str(stages[cell[1]]).length() > 2 else 12, Color(TEXT, 0.6 if cell[2] else 1.0))
		var shown: Array = []  # Each arrow to draw, once a run has played: its two cells, colour, and tag.
		if stalling and (revealed or won):
			for arrow in arrows():
				# Once the gate is open, a forwarded value's tag also says its mux setting.
				var words := str(arrow.text) if not arrow.ok else "%s  %s" % [arrow.text, arrow.code] if won and forwarding else str(arrow.text)
				shown.append({"from": arrow.from, "to": arrow.to, "edge": arrow.edge, "color": GREEN if arrow.ok else RED,
					"text": words if arrow.ok else "%s  too early" % arrow.text})
		var tags := {}  # How far along each row its tags have reached, after its last stage.
		var before := {}  # How far back they have reached, before its first, when there's no room after.
		for item in shown:
			var color: Color = item.color
			var from := _point(item.from, true, item.edge)
			var to := _point(item.to, false, item.edge)
			draw_line(from, to, Color(BG, 0.9), 5.0, true)
			draw_line(from, to, color, 2.0, true)
			var along := (to - from).normalized()
			var across := Vector2(-along.y, along.x)
			draw_colored_polygon(PackedVector2Array([to + along * 3.0, to - along * 7.0 + across * 4.5, to - along * 7.0 - across * 4.5]), color)
			var row: int = item.to.y
			var wide := font.get_string_size(str(item.text), HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 8.0
			var tag := Vector2(left + (_cycle_of(plan[row], stages.size() - 1) + 1) * cell_w + 6.0 + tags.get(row, 0.0), HEAD + row * row_h + (row_h - 15.0) / 2.0)
			if tag.x + wide <= size.x:
				tags[row] = tags.get(row, 0.0) + wide + 6.0
			else:
				tag.x = left + plan[row][0][0] * cell_w - 6.0 - wide - before.get(row, 0.0)
				before[row] = before.get(row, 0.0) + wide + 6.0
			Style.rounded(self, Rect2(tag, Vector2(wide, 15)), Color(color, 0.18), 4, Color(color, 0.8), 1)
			draw_string(font, tag + Vector2(4, 11), str(item.text), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color.lightened(0.3))


## A clock to tune, and the race that tests it. The player steps the clock's period down through
## a few settings. A race sends the signal along the trip it has to make between two ticks (a
## clk-to-q delay, then the logic on the longest path), drawn a segment at a time against the
## moment the clock ticks: late and the circuit breaks, early and the clock could tick faster.
## Either way the race was a try, so the trip is worth working out first.
class ClockRace extends Control:
	signal changed
	signal touched  ## The mouse is over this clock.
	const HEIGHT := 74.0
	var spec: Dictionary
	var options: Array = []
	var pick := 0  # Which setting the clock is on; it starts on the slowest.
	var editable := true
	var won := false
	var shown := -1.0  # How far the last race has played, 0 to 1; -1 before any race.
	var hover := 0  # -1 over the minus key, 1 over the plus key.

	func _init(clock: Dictionary) -> void:
		spec = clock
		for option in clock.choices:
			options.append(int(option))
		options.sort()
		pick = options.size() - 1
		custom_minimum_size = Vector2(320, HEIGHT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func(): touched.emit())
		mouse_exited.connect(func():
			hover = 0
			queue_redraw())
		resized.connect(queue_redraw)

	func period() -> int:
		return options[pick]

	## How long the signal's trip takes.
	func trip() -> int:
		var total := 0
		for part in spec.path:
			total += int(part[1])
		return total

	func reset() -> void:
		pick = options.size() - 1
		shown = -1.0
		queue_redraw()

	func _key(side: int) -> Rect2:
		return Rect2(size.x - (150.0 if side < 0 else 28.0), 0, 28, 24)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			var over := -1 if _key(-1).has_point(event.position) else 1 if _key(1).has_point(event.position) else 0
			if over != hover:
				hover = over
				queue_redraw()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and editable:
			var step := -1 if _key(-1).has_point(event.position) else 1 if _key(1).has_point(event.position) else 0
			if step == 0 or pick + step < 0 or pick + step >= options.size():
				return
			pick += step
			shown = -1.0
			Audio.play("press", -8.0, 0.1)
			changed.emit()
			queue_redraw()
			accept_event()

	func _draw() -> void:
		var font := get_theme_default_font()
		var unit := str(spec.get("unit", "ps"))
		draw_string(font, Vector2(0, 17), str(spec.name), HORIZONTAL_ALIGNMENT_LEFT, size.x - 160, 14, GREEN if won else TEXT)
		for side in [-1, 1]:
			var can: bool = editable and pick + side >= 0 and pick + side < options.size()
			var key := _key(side)
			Style.rounded(self, key, Color(GOLD, 0.3 if hover == side and can else 0.12) if can else Color(SOCKET, 0.5), 5, GOLD if can else DIM, 1)
			draw_string(font, Vector2(key.position.x, 18), "−" if side < 0 else "+", HORIZONTAL_ALIGNMENT_CENTER, key.size.x, 16, GOLD if can else DIM)
		draw_string(MONO, Vector2(size.x - 122, 18), "%d %s" % [period(), unit], HORIZONTAL_ALIGNMENT_CENTER, 94, 15, GREEN if won else GOLD)
		# The track. Until the clock is right it is not to scale: the tick sits at its end, and a race
		# only shows whether the signal got there before it, in time, or not at all. Nothing on it
		# says how long the trip is. Once the gate opens, the trip is drawn piece by piece.
		var track := Rect2(0, 32, size.x, 20)
		var tick := size.x * 0.92
		var total := trip()
		Style.rounded(self, track, Color(SOCKET, 0.7), 5)
		var verdict := "Set the clock, then Race. Every race is a try."
		var tone := Color(TEXT, 0.5)
		if won:
			var at := 0.0
			var tints := [PURPLE, CYAN, GREEN, ORANGE]
			for k in range(spec.path.size()):
				var time := float(spec.path[k][1])
				var piece := Rect2(at / total * tick, track.position.y, time / total * tick, track.size.y)
				Style.rounded(self, piece, Color(tints[k % 4], 0.45), 3, tints[k % 4], 1)
				var words := "%s %d" % [spec.path[k][0], int(time)]
				if font.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 6.0 < piece.size.x:
					draw_string(font, piece.position + Vector2(0, 14), words, HORIZONTAL_ALIGNMENT_CENTER, piece.size.x, 10, TEXT)
				at += time
			verdict = "Just in time: the trip takes %d %s." % [total, unit]
			tone = GREEN
		elif shown >= 0.0:
			var done := shown >= 0.999
			var early := period() > total
			var reach := (0.66 if early else 1.0) * tick * shown
			tone = CYAN
			if done:
				tone = GOLD if early else RED if period() < total else GREEN
				verdict = "It works, but the signal got there early. This clock can tick faster." if early \
					else "Too fast! The signal was still on its way when the clock ticked." if period() < total else "Just in time!"
			else:
				verdict = "Racing…"
			Style.rounded(self, Rect2(0, track.position.y, maxf(reach, 4.0), track.size.y), Color(tone, 0.45), 4, tone, 1)
			if done and period() < total:
				draw_string(font, Vector2(tick - 60, track.position.y + 14), "· · ·", HORIZONTAL_ALIGNMENT_RIGHT, 54, 12, TEXT)
		draw_line(Vector2(tick, 27), Vector2(tick, 57), GOLD, 2.0)
		draw_colored_polygon(PackedVector2Array([Vector2(tick - 5, 26), Vector2(tick + 5, 26), Vector2(tick, 32)]), GOLD)
		draw_string(font, Vector2(0, 70), verdict, HORIZONTAL_ALIGNMENT_LEFT, size.x, 11, tone)
