# Benchmark kernels for GrandPrix.asm, written for the finished CPU (no nops).
# Leaf routines: arguments in a0/a1, result in a0, may use a0-a3 and t0-t6, return with jalr zero, 0(ra).
# Only real instructions (no li / la / j / ret) so that pad.py can make the nop-padded copies.

KERNELS = '''# Bubble sort, ascending. a0 = array, a1 = number of words.
k_sort:
addi a1, a1, -1
ks_outer:
addi t0, zero, 0
addi t1, a0, 0
ks_inner:
lw t3, 0(t1)
lw t4, 4(t1)
bgeu t4, t3, ks_keep
sw t4, 0(t1)
sw t3, 4(t1)
ks_keep:
addi t1, t1, 4
addi t0, t0, 1
blt t0, a1, ks_inner
addi a1, a1, -1
blt zero, a1, ks_outer
jalr zero, 0(ra)

# CRC-32 (same as zlib.crc32) of a0[0 .. a1-1], each word taken as 4 bytes, low byte first.
k_crc:
addi t0, zero, -1
lui t6, 0xEDB88
addi t6, t6, 0x320
kc_word:
lw t1, 0(a0)
addi t2, zero, 4
kc_byte:
andi t3, t1, 0xFF
xor t0, t0, t3
srli t1, t1, 8
addi t4, zero, 8
kc_bit:
andi t5, t0, 1
srli t0, t0, 1
beq t5, zero, kc_skip
xor t0, t0, t6
kc_skip:
addi t4, t4, -1
bne t4, zero, kc_bit
addi t2, t2, -1
bne t2, zero, kc_byte
addi a0, a0, 4
addi a1, a1, -1
bne a1, zero, kc_word
xori a0, t0, -1
jalr zero, 0(ra)

# Sieve of Eratosthenes. a0 = N, a1 = flags. Returns a0 = number of primes <= N.
k_sieve:
addi t0, zero, 2
blt a0, t0, kq_zero
addi t0, zero, 0
addi t1, a1, 0
kq_clr:
sw zero, 0(t1)
addi t1, t1, 4
addi t0, t0, 1
bge a0, t0, kq_clr
addi t0, zero, 2
slli t6, a0, 2
addi a2, zero, 1
add t6, a1, t6
kq_outer:
mul t2, t0, t0
blt a0, t2, kq_count
slli t3, t0, 2
add t3, a1, t3
lw t4, 0(t3)
bne t4, zero, kq_next
slli t5, t0, 2
slli t3, t2, 2
add t3, a1, t3
kq_mark:
sw a2, 0(t3)
add t3, t3, t5
bgeu t6, t3, kq_mark
kq_next:
addi t0, t0, 1
jal zero, kq_outer
kq_count:
addi t1, a1, 8
addi a3, zero, 0
kq_cnt:
lw t4, 0(t1)
sltiu t4, t4, 1
add a3, a3, t4
addi t1, t1, 4
bgeu t6, t1, kq_cnt
addi a0, a3, 0
jalr zero, 0(ra)
kq_zero:
addi a0, zero, 0
jalr zero, 0(ra)
'''

PAD_RENAME = {'k_sort': 'k_sort_p', 'k_crc': 'k_crc_p', 'k_sieve': 'k_sieve_p', 'ks_': 'ksp_', 'kc_': 'kcp_', 'kq_': 'kqp_'}
