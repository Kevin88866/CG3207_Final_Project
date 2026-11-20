# Directed test for the hazard unit (CG3207 Asst 4). No nops anywhere: every case relies on the hardware.
# Pass: LED = 0xFF, 7-seg = 0x600D600D. Fail: 7-seg = 0xBAD0000N, LED = N (N = failed case).
.eqv LED_OFF 0x60
.eqv SEVENSEG_OFF 0x80

.text
main:
lui s0, 0xFFFF0
la s1, data
addi s11, zero, 0

# 1: M -> E forwarding (consecutive dependent ALU instructions)
addi s11, s11, 1
addi t0, zero, 5
addi t1, t0, 3
add t2, t1, t1
addi t6, zero, 16
bne t2, t6, fail

# 2: W -> E forwarding (one instruction in between)
addi s11, s11, 1
addi t3, zero, 7
addi a1, zero, 1
add t4, t3, t3
addi t6, zero, 14
bne t4, t6, fail

# 3: W -> D forwarding (two instructions in between, RegFile written on the same edge)
addi s11, s11, 1
addi t5, zero, 9
addi a1, zero, 1
addi a2, zero, 2
add t6, t5, t5
addi a3, zero, 18
bne t6, a3, fail

# 4: M and W both write the same register: the newer value (M) must win
addi s11, s11, 1
addi t0, zero, 1
addi t0, zero, 2
add t1, t0, zero
addi t6, zero, 2
bne t1, t6, fail

# 5: load-use stall
addi s11, s11, 1
lw t0, 0(s1)
addi t1, t0, 1
lw t6, 4(s1)
bne t1, t6, fail

# 6: load then store of the loaded value, then load it back
addi s11, s11, 1
lw t0, 0(s1)
sw t0, 8(s1)
lw t2, 8(s1)
bne t2, t0, fail

# 7: store data forwarded from the previous instruction
addi s11, s11, 1
addi t0, zero, 77
sw t0, 8(s1)
lw t1, 8(s1)
addi t6, zero, 77
bne t1, t6, fail

# 8: branch flush: the two instructions after a taken branch / jump must not run
addi s11, s11, 1
addi s10, zero, 0
beq zero, zero, b1
addi s10, s10, 1
addi s10, s10, 1
b1:
jal zero, b2
addi s10, s10, 1
addi s10, s10, 1
b2:
bne s10, zero, fail

# 9: branch on a value from the previous instruction (forwarded compare), not taken then taken
addi s11, s11, 1
addi t0, zero, 3
beq t0, zero, fail
addi t1, zero, 3
bne t0, t1, fail

# 10: load then branch on the loaded value (stall + forward into the compare)
addi s11, s11, 1
lw t0, 0(s1)
beq t0, zero, fail

# 11: jalr with rs1 just loaded, jal link used at the target
addi s11, s11, 1
lw t3, 12(s1)
jalr ra, 0(t3)
jal zero, fail
back:
la t6, back
addi t6, t6, -8
bne a0, t6, fail

# 12: mul / div operands from the previous instruction, results used immediately
addi s11, s11, 1
addi t0, zero, 6
mul t1, t0, t0
addi t2, t1, 1
addi t6, zero, 37
bne t2, t6, fail
div t3, t2, t0
addi t6, zero, 6
bne t3, t6, fail

# 13: x0 is never forwarded
addi s11, s11, 1
addi zero, zero, 5
add t0, zero, zero
bne t0, zero, fail

# all passed
lui t0, 0x600D6
addi t0, t0, 0x00D
sw t0, SEVENSEG_OFF(s0)
addi t0, zero, 0xFF
sw t0, LED_OFF(s0)
halt:
jal zero, halt

# jalr target for case 11: a0 = ra - 4 (address of the jalr), return to ra + 4
target:
addi a0, ra, -4
jalr zero, 4(ra)

fail:
lui t0, 0xBAD00
add t0, t0, s11
sw t0, SEVENSEG_OFF(s0)
sw s11, LED_OFF(s0)
fail_loop:
jal zero, fail_loop

.data
data: .word 0x1234, 0x1235, 0, target
