# GrandPrix.asm - CG3207 Asst 4 demo program: "CPU Grand Prix".
# Three benchmark kernels run on data that the audience makes by shaking the board:
#   sort  (bubble sort of 48 bytes)    - load-use hazards, data-dependent branches
#   crc   (CRC-32 of 48 words)         - long dependency chains, a 50/50 branch per bit
#   sieve (primes up to 500)           - tight, predictable loops
# Every kernel exists twice: k_* (no nops, needs the hazard unit) and k_*_p (nop-padded: 3 nops between
# dependent instructions, 2 after every branch / jump - what our pipeline needed before the hazard unit).
# Both builds are timed with the cycle counter and must give the same checksum. Three "eras":
#   classic   = padded build, predictor off       (the previous CPU)
#   + hazard  = no nops, predictor off
#   + predict = no nops, predictor on (flip DIP[15]: the program reruns everything when it changes)
#
# Inputs:  accelerometer (shake to make the data), BTNL = skip shaking (seed from the cycle counter)
#          BTNR = next OLED screen, BTNL = replay the race, BTNC = new data (shake again)
#          DIP[15] = branch predictor on/off
#          DIP[11:10] = kernel shown on the 7-seg (0 sort, 1 crc, 2 sieve, 3 total)
#          DIP[14:13] = 7-seg: cycles of era 0 / 1 / 2, or 3 = speedup x100 (classic / fastest)
#          DIP[12] = 1: 7-seg shows the kernel's checksum in hex instead (kernel 3: the seed)
# Outputs: OLED screens: 0 race replay (red classic, yellow + hazard, green + predictor; grey = not yet measured),
#          1 sorted bars, 2 CRC identicon, 3 prime map
#          LED[2:0] = both builds agree (sort, crc, sieve), LED[3] = all three eras measured,
#          LED[5:4] = screen number, LED[7] = predictor switch
# Needs DMEM_DEPTH_BITS >= 12 in Wrapper.v.

.eqv OLED_COL_OFF 0x20
.eqv OLED_ROW_OFF 0x24
.eqv OLED_DATA_OFF 0x28
.eqv OLED_CTRL_OFF 0x2C
.eqv ACCEL_OFF 0x40
.eqv LED_OFF 0x60
.eqv DIP_OFF 0x64
.eqv PB_OFF 0x68
.eqv SEVENSEG_OFF 0x80
.eqv CYCLE_OFF 0xA0
.eqv N_WORDS 48
.eqv SIEVE_N 500
.eqv THRESH 1500
.eqv RACE_LEN 82
.eqv RACE_F 50
.eqv DEBOUNCE 20000
.eqv RED 0xE0
.eqv YELLOW 0xFC
.eqv GREEN 0x1C
.eqv GREY 0x49
.eqv WHITE 0xFF
.eqv ORANGE 0xF0

# OLED: start a row-major raster at (0, %row). The col write in mode 1 clears the Wrapper's autoadvance flag.
.macro OLED_AT (%row)
sw %row, OLED_ROW_OFF(s0)
addi t6, zero, 1
sw t6, OLED_CTRL_OFF(s0)
sw zero, OLED_COL_OFF(s0)
addi t6, zero, 4
sw t6, OLED_CTRL_OFF(s0)
.end_macro

.macro PUSH_RA
addi sp, sp, -4
sw ra, 0(sp)
.end_macro

.macro POP_RA_RET
lw ra, 0(sp)
addi sp, sp, 4
jalr zero, 0(ra)
.end_macro

# s0 = MMIO, s1 = input data, s2 = sort work array, s3 = sieve flags, s4 = results (see below)
# s5 / s6 / s7 = scratch in run_all, s8 = last PB, s9 = OLED screen, s10 = race frame, s11 = predictor bit
# res[4k + e]  = cycles of kernel k (0 sort, 1 crc, 2 sieve, 3 total), era e (0 classic, 1 + hazard,
#                2 + predictor, 3 padded with the predictor on)
# res[16 + 2k] / res[17 + 2k] = checksum of the fast / padded build, res[24..26] = race car positions,
# res[31] = seed

.text
main:
lui s0, 0xFFFF0
la s1, in_data
la s2, work
la s3, flags
la s4, res
la sp, stack_top
addi s8, zero, 0
new_data:
jal ra, shake
jal ra, gen_data
addi t0, s4, 0
addi t1, zero, 16
clr_res:
sw zero, 0(t0)
addi t0, t0, 4
addi t1, t1, -1
bne t1, zero, clr_res
addi s11, zero, -1 # forces a run

loop:
lw t0, DIP_OFF(s0)
srli t1, t0, 15
beq t1, s11, buttons
addi s11, t1, 0 # predictor switched (or first pass): rerun everything, restart the race
jal ra, run_all
addi s9, zero, 0
addi s10, zero, 0
jal ra, draw_screen
buttons:
lw t0, PB_OFF(s0)
xor t1, t0, s8
and t1, t1, t0
addi s8, t0, 0
andi t2, t1, 2
beq t2, zero, no_btnc
jal ra, wait_release
jal zero, new_data
no_btnc:
andi t2, t1, 1
beq t2, zero, no_btnr
addi s9, s9, 1 # BTNR: next screen
andi s9, s9, 3
addi s10, zero, 0
jal ra, draw_screen
jal ra, wait_release
no_btnr:
andi t2, t1, 4
beq t2, zero, animate
addi s9, zero, 0 # BTNL: replay the race
addi s10, zero, 0
jal ra, draw_screen
jal ra, wait_release
animate:
bne s9, zero, display
jal ra, race_frame
display:
jal ra, show
jal zero, loop

# ---------------- shake to seed ----------------
# Sums |dX| + |dY| + |dZ| between accelerometer readings until it reaches THRESH, mixing every new reading
# and the cycle counter into the seed. BTNL skips. Returns a0 = seed.
shake:
PUSH_RA
addi t0, zero, 0
addi s9, zero, 0 # bar width drawn so far
OLED_AT (t0)
li t1, 6144
sh_clear:
sw zero, OLED_DATA_OFF(s0)
addi t1, t1, -1
bne t1, zero, sh_clear
addi s5, zero, 0 # energy
lw s6, ACCEL_OFF(s0) # last reading
li s7, 0x2545F491 # seed
sh_loop:
lw t0, ACCEL_OFF(s0)
beq t0, s6, sh_input
addi t5, zero, 0
slli t1, t0, 8
srai t1, t1, 24
slli t2, s6, 8
srai t2, t2, 24
sub t1, t1, t2
srai t2, t1, 31
xor t1, t1, t2
sub t1, t1, t2
add t5, t5, t1 # |dX|
slli t1, t0, 16
srai t1, t1, 24
slli t2, s6, 16
srai t2, t2, 24
sub t1, t1, t2
srai t2, t1, 31
xor t1, t1, t2
sub t1, t1, t2
add t5, t5, t1 # |dY|
slli t1, t0, 24
srai t1, t1, 24
slli t2, s6, 24
srai t2, t2, 24
sub t1, t1, t2
srai t2, t1, 31
xor t1, t1, t2
sub t1, t1, t2
add t5, t5, t1 # |dZ|
add s5, s5, t5
addi s6, t0, 0
xor s7, s7, t0
lw t1, CYCLE_OFF(s0)
xor s7, s7, t1
slli t1, s7, 13
xor s7, s7, t1
srli t1, s7, 17
xor s7, s7, t1
slli t1, s7, 5
xor s7, s7, t1
jal ra, draw_shake
sh_input:
sw s7, SEVENSEG_OFF(s0)
addi t1, zero, 0x40
sw t1, LED_OFF(s0)
li t1, THRESH
bgeu s5, t1, sh_done
lw t1, PB_OFF(s0)
andi t1, t1, 4
beq t1, zero, sh_loop
lw t1, CYCLE_OFF(s0) # BTNL: seed from the cycle counter
xor s7, s7, t1
jal ra, wait_release
sh_done:
addi a0, s7, 0
POP_RA_RET

# progress bar: rows 28..35, orange up to energy * 96 / THRESH, grey after that
draw_shake:
addi t0, zero, 96
mul t1, s5, t0
li t0, THRESH
divu t1, t1, t0
addi t0, zero, 96
bltu t1, t0, ds_w
addi t1, zero, 96
ds_w:
beq t1, s9, ds_done # width unchanged
addi s9, t1, 0
addi t0, zero, 28
OLED_AT (t0)
addi t2, zero, 0 # row
ds_row:
addi t3, zero, 0 # x
ds_px:
addi t4, zero, ORANGE
blt t3, t1, ds_put
addi t4, zero, GREY
ds_put:
sw t4, OLED_DATA_OFF(s0)
addi t3, t3, 1
addi t5, zero, 96
blt t3, t5, ds_px
addi t2, t2, 1
addi t5, zero, 8
blt t2, t5, ds_row
ds_done:
jalr zero, 0(ra)

# ---------------- data ----------------
# in_data[0..47] = xorshift32 stream from a0 (0 -> fixed seed). res[31] = seed.
gen_data:
bne a0, zero, gd_seed
li a0, 0x2545F491
gd_seed:
sw a0, 124(s4)
addi t0, s1, 0
addi t1, zero, N_WORDS
gd_loop:
slli t2, a0, 13
xor a0, a0, t2
srli t2, a0, 17
xor a0, a0, t2
slli t2, a0, 5
xor a0, a0, t2
sw a0, 0(t0)
addi t0, t0, 4
addi t1, t1, -1
bne t1, zero, gd_loop
jalr zero, 0(ra)

# work[i] = in_data[i] & 0xFF
copy_in:
addi t0, s1, 0
addi t1, s2, 0
addi t2, zero, N_WORDS
ci_loop:
lw t3, 0(t0)
andi t3, t3, 0xFF
sw t3, 0(t1)
addi t0, t0, 4
addi t1, t1, 4
addi t2, t2, -1
bne t2, zero, ci_loop
jalr zero, 0(ra)

# a0 = rotate-xor hash of work[0..47]
hash_work:
addi a0, zero, 0
addi t0, s2, 0
addi t1, zero, N_WORDS
hw_loop:
slli t2, a0, 5
srli t3, a0, 27
or a0, t2, t3
lw t2, 0(t0)
xor a0, a0, t2
addi t0, t0, 4
addi t1, t1, -1
bne t1, zero, hw_loop
jalr zero, 0(ra)

# ---------------- measurement ----------------
# Runs every kernel, padded build first, then the fast build, and records cycles and checksums.
run_all:
PUSH_RA
jal ra, copy_in # sort
lw s5, CYCLE_OFF(s0)
addi a0, s2, 0
addi a1, zero, N_WORDS
jal ra, k_sort_p
lw t1, CYCLE_OFF(s0)
sub s6, t1, s5
jal ra, hash_work
addi s7, a0, 0
jal ra, copy_in
lw s5, CYCLE_OFF(s0)
addi a0, s2, 0
addi a1, zero, N_WORDS
jal ra, k_sort
lw t1, CYCLE_OFF(s0)
sub s5, t1, s5
jal ra, hash_work
addi a3, a0, 0
addi a0, zero, 0
jal ra, record
lw s5, CYCLE_OFF(s0) # crc
addi a0, s1, 0
addi a1, zero, N_WORDS
jal ra, k_crc_p
lw t1, CYCLE_OFF(s0)
sub s6, t1, s5
addi s7, a0, 0
lw s5, CYCLE_OFF(s0)
addi a0, s1, 0
addi a1, zero, N_WORDS
jal ra, k_crc
lw t1, CYCLE_OFF(s0)
sub s5, t1, s5
addi a3, a0, 0
addi a0, zero, 1
jal ra, record
lw s5, CYCLE_OFF(s0) # sieve
addi a0, zero, SIEVE_N
addi a1, s3, 0
jal ra, k_sieve_p
lw t1, CYCLE_OFF(s0)
sub s6, t1, s5
addi s7, a0, 0
lw s5, CYCLE_OFF(s0)
addi a0, zero, SIEVE_N
addi a1, s3, 0
jal ra, k_sieve
lw t1, CYCLE_OFF(s0)
sub s5, t1, s5
addi a3, a0, 0
addi a0, zero, 2
jal ra, record
addi t0, zero, 0 # totals: res[12 + e] = sum over the kernels
ra_total:
slli t1, t0, 2
add t1, s4, t1
lw t2, 0(t1)
lw t3, 16(t1)
add t2, t2, t3
lw t3, 32(t1)
add t2, t2, t3
sw t2, 48(t1)
addi t0, t0, 1
addi t1, zero, 4
blt t0, t1, ra_total
POP_RA_RET

# a0 = kernel, s5 = fast cycles, s6 = padded cycles, a3 = fast checksum, s7 = padded checksum
record:
slli t0, a0, 4
add t0, s4, t0
bne s11, zero, rec_bp
sw s6, 0(t0) # classic
sw s5, 4(t0) # + hazard unit
jal zero, rec_ck
rec_bp:
sw s5, 8(t0) # + predictor
sw s6, 12(t0)
rec_ck:
slli t0, a0, 3
add t0, s4, t0
sw a3, 64(t0)
sw s7, 68(t0)
jalr zero, 0(ra)

# ---------------- 7-seg and LEDs ----------------
show:
PUSH_RA
lw t0, DIP_OFF(s0)
srli t1, t0, 10
andi t1, t1, 3 # kernel
slli s5, t1, 4
add s5, s4, s5 # &res[4k]
srli t2, t0, 12
andi t2, t2, 1
beq t2, zero, sw_cycles
addi t2, zero, 3 # checksum view
beq t1, t2, sw_seed
slli t2, t1, 3
add t2, s4, t2
lw a0, 64(t2)
jal zero, sw_out
sw_seed:
lw a0, 124(s4)
jal zero, sw_out
sw_cycles:
srli t2, t0, 13
andi t2, t2, 3
addi t3, zero, 3
beq t2, t3, sw_speed
slli t2, t2, 2
add t2, s5, t2
lw a0, 0(t2)
jal ra, to_bcd
jal zero, sw_out
sw_speed:
lw t2, 0(s5) # classic / fastest measured
lw t3, 8(s5)
bne t3, zero, sw_div
lw t3, 4(s5)
sw_div:
addi a0, zero, 0
beq t3, zero, sw_bcd
addi t4, zero, 100
mul a0, t2, t4
divu a0, a0, t3
sw_bcd:
jal ra, to_bcd
sw_out:
sw a0, SEVENSEG_OFF(s0)
addi t0, zero, 0 # LEDs
addi t1, zero, 0
addi t2, s4, 64
sw_agree:
lw t3, 0(t2)
lw t4, 4(t2)
bne t3, t4, sw_next
addi t5, zero, 1
sll t5, t5, t1
or t0, t0, t5
sw_next:
addi t2, t2, 8
addi t1, t1, 1
addi t3, zero, 3
blt t1, t3, sw_agree
lw t3, 0(s4)
lw t4, 4(s4)
lw t5, 8(s4)
beq t3, zero, sw_leds
beq t4, zero, sw_leds
beq t5, zero, sw_leds
ori t0, t0, 8
sw_leds:
slli t1, s9, 4
or t0, t0, t1
slli t1, s11, 7
or t0, t0, t1
sw t0, LED_OFF(s0)
POP_RA_RET

# a0 = value (< 10^8). Returns a0 = the value as 8 BCD digits.
to_bcd:
addi t0, zero, 0
addi t1, zero, 0
addi t2, zero, 10
bcd_loop:
divu t3, a0, t2
mul t4, t3, t2
sub t4, a0, t4
sll t4, t4, t1
or t0, t0, t4
addi t1, t1, 4
addi a0, t3, 0
bne a0, zero, bcd_loop
addi a0, t0, 0
jalr zero, 0(ra)

wait_release:
lw t0, PB_OFF(s0)
bne t0, zero, wait_release
li t0, DEBOUNCE
wr_loop:
addi t0, t0, -1
bne t0, zero, wr_loop
addi s8, zero, 0
jalr zero, 0(ra)

# ---------------- OLED screens ----------------
# screen 0 is drawn by race_frame
draw_screen:
bne s9, zero, ds_other
jalr zero, 0(ra)
ds_other:
addi t0, zero, 1
beq s9, t0, draw_bars
addi t0, zero, 2
beq s9, t0, draw_crc
jal zero, draw_primes

# One race frame: car e moves frame * fastest / cycles_e, so speed is proportional to 1 / cycles.
# s10 = -1 once the last frame (every car at the line) has been drawn.
race_frame:
bge s10, zero, rf_go
jalr zero, 0(ra)
rf_go:
PUSH_RA
li t0, 0x7FFFFFFF # fastest measured total
addi t1, zero, 0
rf_min:
slli t2, t1, 2
add t2, s4, t2
lw t3, 48(t2)
beq t3, zero, rf_min_next
bgeu t3, t0, rf_min_next
addi t0, t3, 0
rf_min_next:
addi t1, t1, 1
addi t2, zero, 3
blt t1, t2, rf_min
addi t1, zero, 0
addi t5, zero, 0 # cars still running
rf_pos:
slli t2, t1, 2
add t2, s4, t2
lw t3, 48(t2)
addi t4, zero, 0
beq t3, zero, rf_store
mul t4, s10, t0
divu t4, t4, t3 # frames this car has done
addi t6, zero, RACE_LEN
mul t4, t4, t6
addi t6, zero, RACE_F
divu t4, t4, t6
addi t6, zero, RACE_LEN
bltu t4, t6, rf_running
addi t4, zero, RACE_LEN
jal zero, rf_store
rf_running:
addi t5, t5, 1
rf_store:
sw t4, 96(t2)
addi t1, t1, 1
addi t6, zero, 3
blt t1, t6, rf_pos
beq t5, zero, rf_last
addi s10, s10, 1
jal ra, draw_race
jal zero, rf_done
rf_last:
addi s10, zero, -1 # everybody is at the line: draw it once more and stop
jal ra, draw_race
rf_done:
POP_RA_RET

# race screen: lanes at rows 6, 26, 46 (12 rows), car = 10 x 8 pixels, finish line at x = 93..94
draw_race:
addi t0, zero, 0
OLED_AT (t0)
addi t1, zero, 0 # y
dr_y:
addi a4, zero, -100 # car x on this row (none)
addi a5, zero, 0
addi t2, zero, 0 # lane
addi t3, zero, 8 # first car row of lane 0
dr_lane:
sub t4, t1, t3
sltiu t4, t4, 8
beq t4, zero, dr_lane_next
slli t4, t2, 2
add t4, s4, t4
lw a4, 96(t4)
lw t5, 48(t4)
addi a5, zero, GREY
beq t5, zero, dr_lane_next
addi a5, zero, RED
beq t2, zero, dr_lane_next
addi a5, zero, YELLOW
addi t4, zero, 1
beq t2, t4, dr_lane_next
addi a5, zero, GREEN
dr_lane_next:
addi t3, t3, 20
addi t2, t2, 1
addi t4, zero, 3
blt t2, t4, dr_lane
addi t2, zero, 0 # x
dr_x:
addi t0, zero, 0
sub t4, t2, a4
sltiu t4, t4, 10
beq t4, zero, dr_line
addi t0, a5, 0
jal zero, dr_put
dr_line:
addi t4, t2, -93
sltiu t4, t4, 2
beq t4, zero, dr_put
addi t0, zero, WHITE
dr_put:
sw t0, OLED_DATA_OFF(s0)
addi t2, t2, 1
addi t4, zero, 96
blt t2, t4, dr_x
addi t1, t1, 1
addi t4, zero, 64
blt t1, t4, dr_y
jalr zero, 0(ra)

# sorted data as 48 bars, 2 pixels wide, height = value / 4
draw_bars:
addi t0, zero, 0
OLED_AT (t0)
addi t1, zero, 0
db_y:
addi a7, zero, 63
sub a7, a7, t1
addi t2, zero, 0
db_x:
srli t3, t2, 1
slli t3, t3, 2
add t3, s2, t3
lw t3, 0(t3)
srli t4, t3, 2
addi t0, zero, 0
bgeu a7, t4, db_put
andi t0, t3, 0xE0
ori t0, t0, GREEN
db_put:
sw t0, OLED_DATA_OFF(s0)
addi t2, t2, 1
addi t4, zero, 96
blt t2, t4, db_x
addi t1, t1, 1
addi t4, zero, 64
blt t1, t4, db_y
jalr zero, 0(ra)

# CRC identicon: 8 x 8 blocks of 8 x 8 pixels at x = 16..79, left half = CRC bits, right half mirrored
draw_crc:
addi t0, zero, 0
OLED_AT (t0)
lw a4, 72(s4) # CRC of the fast build
srli a5, a4, 24
ori a5, a5, 0x49 # colour from the top byte, never too dark
addi t1, zero, 0
dc_y:
srli a6, t1, 3 # block row
addi t2, zero, 0
dc_x:
addi t0, zero, 0
addi t3, t2, -16
sltiu t4, t3, 64
beq t4, zero, dc_put
srli t3, t3, 3 # block column 0..7
sltiu t4, t3, 4
bne t4, zero, dc_half
addi t4, zero, 7
sub t3, t4, t3
dc_half:
slli t4, a6, 2
add t4, t4, t3 # bit number
srl t4, a4, t4
andi t4, t4, 1
beq t4, zero, dc_put
addi t0, a5, 0
dc_put:
sw t0, OLED_DATA_OFF(s0)
addi t2, t2, 1
addi t4, zero, 96
blt t2, t4, dc_x
addi t1, t1, 1
addi t4, zero, 64
blt t1, t4, dc_y
jalr zero, 0(ra)

# prime map of 0..500: 32 cells per row, 2 x 2 pixels, rows 16..47
draw_primes:
addi t0, zero, 0
OLED_AT (t0)
addi t1, zero, 0
dp_y:
addi t2, zero, 0
dp_x:
addi t0, zero, 0
addi t3, t1, -16
sltiu t4, t3, 32
beq t4, zero, dp_put
addi t4, zero, 64
bge t2, t4, dp_put
srli t3, t3, 1
slli t3, t3, 5
srli t4, t2, 1
add t3, t3, t4 # number i
addi t4, zero, SIEVE_N
blt t4, t3, dp_put
addi t0, zero, GREY
addi t4, zero, 2
blt t3, t4, dp_put
slli t4, t3, 2
add t4, s3, t4
lw t4, 0(t4)
bne t4, zero, dp_put
addi t0, zero, GREEN
dp_put:
sw t0, OLED_DATA_OFF(s0)
addi t2, t2, 1
addi t4, zero, 96
blt t2, t4, dp_x
addi t1, t1, 1
addi t4, zero, 64
blt t1, t4, dp_y
jalr zero, 0(ra)

# ---------------- kernels ----------------
# Bubble sort, ascending. a0 = array, a1 = number of words.
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

# ---------------- nop-padded copies (generated by pad.py: 3 nops between dependent instructions,
# 2 after every branch / jump). This is the code our pipeline needed before the hazard unit. ----------------
# Bubble sort, ascending. a0 = array, a1 = number of words.
k_sort_p:
addi a1, a1, -1
ksp_outer:
addi t0, zero, 0
addi t1, a0, 0
ksp_inner:
nop
nop
nop
lw t3, 0(t1)
lw t4, 4(t1)
nop
nop
nop
bgeu t4, t3, ksp_keep
nop
nop
sw t4, 0(t1)
sw t3, 4(t1)
ksp_keep:
addi t1, t1, 4
addi t0, t0, 1
nop
nop
nop
blt t0, a1, ksp_inner
nop
nop
addi a1, a1, -1
nop
nop
nop
blt zero, a1, ksp_outer
nop
nop
jalr zero, 0(ra)
nop
nop
# CRC-32 (same as zlib.crc32) of a0[0 .. a1-1], each word taken as 4 bytes, low byte first.
k_crc_p:
addi t0, zero, -1
lui t6, 0xEDB88
nop
nop
nop
addi t6, t6, 0x320
kcp_word:
lw t1, 0(a0)
addi t2, zero, 4
kcp_byte:
nop
nop
andi t3, t1, 0xFF
nop
nop
nop
xor t0, t0, t3
srli t1, t1, 8
addi t4, zero, 8
kcp_bit:
nop
andi t5, t0, 1
srli t0, t0, 1
nop
nop
beq t5, zero, kcp_skip
nop
nop
xor t0, t0, t6
kcp_skip:
addi t4, t4, -1
nop
nop
nop
bne t4, zero, kcp_bit
nop
nop
addi t2, t2, -1
nop
nop
nop
bne t2, zero, kcp_byte
nop
nop
addi a0, a0, 4
addi a1, a1, -1
nop
nop
nop
bne a1, zero, kcp_word
nop
nop
xori a0, t0, -1
jalr zero, 0(ra)
nop
nop
# Sieve of Eratosthenes. a0 = N, a1 = flags. Returns a0 = number of primes <= N.
k_sieve_p:
addi t0, zero, 2
nop
nop
nop
blt a0, t0, kqp_zero
nop
nop
addi t0, zero, 0
addi t1, a1, 0
kqp_clr:
nop
nop
nop
sw zero, 0(t1)
addi t1, t1, 4
addi t0, t0, 1
nop
nop
nop
bge a0, t0, kqp_clr
nop
nop
addi t0, zero, 2
slli t6, a0, 2
addi a2, zero, 1
nop
nop
add t6, a1, t6
kqp_outer:
mul t2, t0, t0
nop
nop
nop
blt a0, t2, kqp_count
nop
nop
slli t3, t0, 2
nop
nop
nop
add t3, a1, t3
nop
nop
nop
lw t4, 0(t3)
nop
nop
nop
bne t4, zero, kqp_next
nop
nop
slli t5, t0, 2
slli t3, t2, 2
nop
nop
nop
add t3, a1, t3
kqp_mark:
nop
nop
nop
sw a2, 0(t3)
add t3, t3, t5
nop
nop
nop
bgeu t6, t3, kqp_mark
nop
nop
kqp_next:
addi t0, t0, 1
jal zero, kqp_outer
nop
nop
kqp_count:
addi t1, a1, 8
addi a3, zero, 0
kqp_cnt:
nop
nop
lw t4, 0(t1)
nop
nop
nop
sltiu t4, t4, 1
nop
nop
nop
add a3, a3, t4
addi t1, t1, 4
nop
nop
nop
bgeu t6, t1, kqp_cnt
nop
nop
addi a0, a3, 0
jalr zero, 0(ra)
nop
nop
kqp_zero:
addi a0, zero, 0
jalr zero, 0(ra)
nop
nop

.data
in_data: .space 192
work: .space 192
res: .space 128
flags: .space 2048
stack: .space 256
stack_top: .word 0
