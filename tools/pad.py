"""Insert nops so a RISC-V routine runs on a 5-stage pipeline with NO hazard hardware:
a producer and its consumer must be at least 4 instructions apart (3 nops), and every
branch / jump is followed by 2 nops. Labels are kept; rename with prefix maps."""
import re

R3 = {'add', 'sub', 'and', 'or', 'xor', 'sll', 'srl', 'sra', 'slt', 'sltu', 'mul', 'div', 'divu'}
I2 = {'addi', 'andi', 'ori', 'xori', 'slli', 'srli', 'srai', 'slti', 'sltiu'}
BR = {'beq', 'bne', 'blt', 'bge', 'bltu', 'bgeu'}


def regs_of(line):
	"""(dst, srcs, is_control) for one instruction line (no label, no comment)."""
	op, _, rest = line.partition(' ')
	args = [a.strip() for a in rest.split(',')] if rest.strip() else []
	if op == 'nop':
		return None, [], False
	if op in R3:
		return args[0], [args[1], args[2]], False
	if op in I2:
		return args[0], [args[1]], False
	if op == 'lw':
		base = re.search(r'\((\w+)\)', args[1]).group(1)
		return args[0], [base], False
	if op == 'sw':
		base = re.search(r'\((\w+)\)', args[1]).group(1)
		return None, [args[0], base], False
	if op in BR:
		return None, [args[0], args[1]], True
	if op == 'jal':
		return args[0], [], True
	if op == 'jalr':
		base = re.search(r'\((\w+)\)', args[1]).group(1)
		return args[0], [base], True
	if op in ('lui', 'auipc'):
		return args[0], [], False
	raise ValueError('unknown op: ' + line)


def pad(src, rename):
	out, hist = [], []  # hist: dst of each emitted instruction (None for nop)

	def emit(text, dst):
		out.append(text)
		hist.append(dst)

	for raw in src.splitlines():
		code, hashmark, comment = raw.partition('#')
		code = code.strip()
		for a, b in rename.items():
			code = re.sub(r'\b' + a, b, code)
		if not code:
			if raw.strip():
				out.append(raw)  # comment line
			continue
		if code.endswith(':'):
			out.append(code)
			continue
		dst, srcs, ctrl = regs_of(code)
		srcs = [s for s in srcs if s not in ('zero', 'x0')]
		need = 0
		for i in range(1, 4):
			if len(hist) >= i and hist[-i] is not None and hist[-i] in srcs:
				need = max(need, 4 - i)
		for _ in range(need):
			emit('nop', None)
		emit(code + ((' #' + comment) if hashmark else ''), dst if dst not in ('zero', 'x0') else None)
		if ctrl:
			emit('nop', None)
			emit('nop', None)
	return '\n'.join(out)
