# bp_test.asm - branch-heavy test program for the branch predictor (CG3207 Asst 4).
# Not the demo program: it computes a signature in s1, writes it to the 7-seg,
# then writes 0xA5 to the LEDs and spins on "end: j end".
# test_Wrapper_BP.v runs it with the predictor off and on, checks the signature
# (the same value RARS gets) and reports cycles and mispredictions.
#
# There is no forwarding hardware yet, so every producer/consumer pair is at
# least 3 instructions apart on every path. No nops are needed after branches
# any more: the branch flush (part of the predictor) cancels wrong-path instructions.

.text
main:
    lui  s0, 0xFFFF0            # MMIO base
    addi s1, zero, 0            # signature

# ---- test 1: counted loop, t1 = 20 + 19 + ... + 1 = 210 ----
    addi t0, zero, 20
    addi t1, zero, 0
    nop
    nop
    nop
loop1:
    add  t1, t1, t0
    addi t0, t0, -1
    nop
    nop
    nop
    bne  t0, zero, loop1
    nop
    nop
    add  s1, s1, t1             # s1 = 210

# ---- test 2: nested loop, 6 x 5, inner if/else on the parity of j ----
    addi t2, zero, 6
outer:
    addi t3, zero, 5
    nop
    nop
    nop
inner:
    andi t4, t3, 1
    addi t3, t3, -1
    nop
    nop
    beq  t4, zero, even
    addi s1, s1, 3              # odd j (5, 3, 1)
    jal  zero, next
even:
    addi s1, s1, 5              # even j (4, 2)
next:
    bne  t3, zero, inner
    addi t2, t2, -1
    nop
    nop
    nop
    bne  t2, zero, outer        # s1 += 6 * (3*3 + 2*5) = 114

# ---- test 3: one function called from two places (the return target alternates) ----
    addi t5, zero, 8
    nop
    nop
    nop
loop3:
    addi a0, t5, 0
    nop
    nop
    nop
    jal  ra, func               # call site 1: s1 += 2 * t5
    addi a0, zero, 7
    nop
    nop
    nop
    jal  ra, func               # call site 2: s1 += 14
    addi t5, t5, -1
    nop
    nop
    nop
    bne  t5, zero, loop3        # s1 += 2*(8+7+...+1) + 8*14 = 72 + 112 = 184
    jal  zero, test4

func:
    slli t6, a0, 1
    nop
    nop
    nop
    add  s1, s1, t6
    jalr zero, ra, 0

# ---- test 4: every branch type, both ways, 4 times. t0 = -5, t1 = 3 ----
test4:
    addi t0, zero, -5
    addi t1, zero, 3
    addi t2, zero, 4
    nop
    nop
    nop
loop4:
    blt  t0, t1, L1             # taken (signed -5 < 3)
    addi s1, s1, 1000
    nop
    nop
    nop
L1: bltu t0, t1, L2             # not taken (unsigned 0xFFFFFFFB > 3)
    addi s1, s1, 1
    nop
    nop
    nop
L2: bge  t0, t1, L3             # not taken
    addi s1, s1, 2
    nop
    nop
    nop
L3: bgeu t0, t1, L4             # taken
    addi s1, s1, 1000
    nop
    nop
    nop
L4: beq  t0, t0, L5             # taken
    addi s1, s1, 1000
    nop
    nop
    nop
L5: bne  t0, t0, L6             # not taken
    addi s1, s1, 4
    nop
    nop
    nop
L6: beq  t0, t1, L7             # not taken
    addi s1, s1, 8
    nop
    nop
    nop
L7: bne  t0, t1, L8             # taken
    addi s1, s1, 1000
    nop
    nop
    nop
L8: addi t2, t2, -1
    nop
    nop
    nop
    bne  t2, zero, loop4        # s1 += 4 * (1 + 2 + 4 + 8) = 60

# ---- done: signature 210 + 114 + 184 + 60 = 568 = 0x238 ----
    sw   s1, 0x80(s0)           # 7-seg
    addi t0, zero, 0xA5
    nop
    nop
    nop
    sw   t0, 0x60(s0)           # LEDs = A5 marks the end
end:
    jal  zero, end
