`timescale 1ns / 1ps
// Testbench for GrandPrix.asm (CG3207 Asst 4). Module name test_Wrapper_GP; set it as the simulation top.
// Load mem_GrandPrix/AA_IROM.mem and AA_DMEM.mem. Only board outputs are checked (works post-synthesis).
// The accelerometer is driven to "shake" the board; expected checksums are computed here from the seed
// the program shows on the 7-seg. Run time: about 215 ms (set xsim.simulate.runtime to 220ms, or -all).

module test_Wrapper_GP #(
	parameter N_LEDs_OUT = 8,
	parameter N_DIPs = 16,
	parameter N_PBs = 3
)();

reg [N_DIPs-1:0] DIP = 0;
reg [N_PBs-1:0] PB = 0;
wire [N_LEDs_OUT-1:0] LED_OUT;
wire [6:0] LED_PC;
wire [31:0] SEVENSEGHEX;
wire [7:0] UART_TX;
reg UART_TX_ready = 0;
wire UART_TX_valid;
reg [7:0] UART_RX = 0;
reg UART_RX_valid = 0;
wire UART_RX_ack;
wire OLED_Write;
wire [6:0] OLED_Col;
wire [5:0] OLED_Row;
wire [23:0] OLED_Data;
reg [31:0] ACCEL_Data = 32'h18000040;
wire ACCEL_DReady;
reg RESET = 0;
reg CLK = 0;

integer pass_count = 0;
integer fail_count = 0;
integer k, e, run, xr, xy, xg;
integer cyc [0:3][0:2];
reg [31:0] seed, x, crc, h;
reg [31:0] data [0:47];
reg [31:0] sorted [0:47];
reg [31:0] expect_ck [0:2];
reg shaking = 0;
reg [23:0] frame [0:96*64-1];

Wrapper dut(DIP, PB, LED_OUT, LED_PC, SEVENSEGHEX, UART_TX, UART_TX_ready, UART_TX_valid, UART_RX, UART_RX_valid, UART_RX_ack, OLED_Write, OLED_Col, OLED_Row, OLED_Data, ACCEL_Data, ACCEL_DReady, RESET, CLK);

always @(posedge CLK)
	if (OLED_Write) frame[OLED_Row * 96 + OLED_Col] <= OLED_Data;

// shaking: new X/Y/Z readings every 3000 cycles while 'shaking' is set
always begin
	repeat (3000) @(posedge CLK);
	if (shaking) ACCEL_Data = {8'h18, $random} & 32'hFF7F7F7F;
end

function [23:0] rgb;
	input [7:0] c;
	rgb = {c[7:5], 5'd0, c[4:2], 5'd0, c[1:0], 6'd0};
endfunction

function integer from_bcd;
	input [31:0] b;
	integer j;
	begin
		from_bcd = 0;
		for (j = 7; j >= 0; j = j - 1)
			from_bcd = from_bcd * 10 + b[4*j +: 4];
	end
endfunction

// expected checksums for the data the program made from 'seed'
task model;
	integer i, j, b;
	reg [31:0] t;
	begin
		x = seed;
		for (i = 0; i < 48; i = i + 1) begin
			x = x ^ (x << 13);
			x = x ^ (x >> 17);
			x = x ^ (x << 5);
			data[i] = x;
			sorted[i] = x & 32'hFF;
		end
		for (i = 0; i < 47; i = i + 1)
			for (j = 0; j < 47 - i; j = j + 1)
				if (sorted[j] > sorted[j + 1]) begin
					t = sorted[j]; sorted[j] = sorted[j + 1]; sorted[j + 1] = t;
				end
		h = 0;
		for (i = 0; i < 48; i = i + 1) h = {h[26:0], h[31:27]} ^ sorted[i];
		crc = 32'hFFFFFFFF;
		for (i = 0; i < 48; i = i + 1)
			for (b = 0; b < 32; b = b + 1)
				crc = (crc[0] ^ data[i][b]) ? ((crc >> 1) ^ 32'hEDB88320) : (crc >> 1);
		expect_ck[0] = h;
		expect_ck[1] = ~crc;
		expect_ck[2] = 95; // primes <= 500
	end
endtask

task wait_led;
	input [7:0] value;
	input [8*60-1:0] what;
	integer t;
	begin
		t = 0;
		while (LED_OUT !== value && t < 2000000) begin
			@(posedge CLK); t = t + 1;
		end
		if (LED_OUT === value) begin
			$display("[%0t] PASS %0s (LED = %h)", $time, what, LED_OUT);
			pass_count = pass_count + 1;
		end
		else begin
			$display("[%0t] FAIL %0s: LED = %h, expected %h", $time, what, LED_OUT, value);
			fail_count = fail_count + 1;
		end
	end
endtask

// set the DIPs and give the main loop time to show it (one race frame can take ~70k cycles)
task set_dip;
	input [15:0] value;
	begin
		DIP = value;
		repeat (200000) @(posedge CLK);
	end
endtask

// hold a button until the program has seen it (the race frame between polls is long), then release
task press;
	input [2:0] button;
	begin
		PB = button;
		repeat (200000) @(posedge CLK);
		PB = 0;
		repeat (100000) @(posedge CLK);
	end
endtask

task check;
	input ok;
	input [8*60-1:0] what;
	begin
		if (ok) begin
			$display("[%0t] PASS %0s", $time, what);
			pass_count = pass_count + 1;
		end
		else begin
			$display("[%0t] FAIL %0s", $time, what);
			fail_count = fail_count + 1;
		end
	end
endtask

// left edge of the car in a lane (row y), or -1
function integer car_x;
	input integer y;
	integer j;
	begin
		car_x = -1;
		for (j = 91; j >= 0; j = j - 1)
			if (frame[y * 96 + j] !== 24'd0) car_x = j;
	end
endfunction

task check_checksums;
	begin
		set_dip(16'h1C00); // checksum view, kernel 3 = seed
		seed = SEVENSEGHEX;
		model;
		$display("seed = %h, expected sort hash %h, crc %h, primes %0d", seed, expect_ck[0], expect_ck[1], expect_ck[2]);
		for (k = 0; k < 3; k = k + 1) begin
			set_dip(16'h1000 | (k << 10));
			check(SEVENSEGHEX === expect_ck[k], k == 0 ? "sort checksum" : k == 1 ? "crc checksum (= zlib.crc32)" : "sieve checksum (95 primes)");
		end
	end
endtask

initial begin
RESET = 1; #10;
RESET = 0;

// 1. shake until the bar is full, then both builds run (predictor off)
repeat (20000) @(posedge CLK);
shaking = 1;
wait_led(8'h07, "shaken: all kernels ran, both builds agree");
shaking = 0;
check_checksums;

// 2. cycles of the classic and + hazard eras
for (k = 0; k < 4; k = k + 1)
	for (e = 0; e < 2; e = e + 1) begin
		set_dip((k << 10) | (e << 13));
		cyc[k][e] = from_bcd(SEVENSEGHEX);
	end
for (k = 0; k < 4; k = k + 1)
	check(cyc[k][1] > 0 && cyc[k][1] < cyc[k][0], "hazard unit is faster than the padded build");

// 3. race replay (BTNL): after a while the yellow car is ahead of the red one, grey car (not measured) at the start
DIP = 0;
press(3'b100);
repeat (1200000) @(posedge CLK);
xr = car_x(10); xy = car_x(30); xg = car_x(50);
$display("race, predictor off: red at %0d, yellow at %0d, grey at %0d", xr, xy, xg);
check(xy > xr && xr >= 0 && xg == 0 && frame[50 * 96 + xg] === rgb(8'h49), "race positions (predictor off)");

// 4. flip the predictor on: everything reruns and the third era appears
DIP = 16'h8000;
wait_led(8'h8F, "predictor on: rerun, all three eras measured");
for (k = 0; k < 4; k = k + 1) begin
	set_dip(16'h8000 | (k << 10) | (2 << 13));
	cyc[k][2] = from_bcd(SEVENSEGHEX);
end
$display("cycles        classic   +hazard  +predictor");
for (k = 0; k < 4; k = k + 1)
	$display("%s %9d %9d %9d", k == 0 ? "sort  " : k == 1 ? "crc   " : k == 2 ? "sieve " : "total ", cyc[k][0], cyc[k][1], cyc[k][2]);
check(cyc[3][2] < cyc[3][1], "predictor reduces the total");
set_dip(16'h8000 | (3 << 10) | (3 << 13));
check(from_bcd(SEVENSEGHEX) == cyc[3][0] * 100 / cyc[3][2], "speedup x100 on the 7-seg");
check_checksums;

// 5. race replay with three cars: green ahead of yellow ahead of red
DIP = 16'h8000;
press(3'b100);
repeat (1200000) @(posedge CLK);
xr = car_x(10); xy = car_x(30); xg = car_x(50);
$display("race, three eras: red at %0d, yellow at %0d, green at %0d", xr, xy, xg);
check(xg > xy && xy > xr && frame[50 * 96 + xg] === rgb(8'h1C), "race positions (three eras)");
repeat (11000000) @(posedge CLK);
xr = car_x(10); xy = car_x(30); xg = car_x(50);
$display("race finished: red at %0d, yellow at %0d, green at %0d", xr, xy, xg);
check(xr == 82 && xy == 82 && xg == 82, "race end: every car drawn at the finish line");

// 6. the other screens
press(3'b001);
e = 0;
for (k = 0; k < 48; k = k + 1)
	if (frame[63 * 96 + 2 * k] !== ((sorted[k] >> 2) > 0 ? rgb((sorted[k] & 8'hE0) | 8'h1C) : 24'd0)) e = -1;
check(e != -1 && frame[(63 - (sorted[47] >> 2)) * 96 + 94] === 24'd0, "screen 1: sorted bars");
press(3'b001);
e = 0;
for (k = 0; k < 32; k = k + 1)
	if ((frame[(8 * (k / 4) + 3) * 96 + 16 + 8 * (k % 4) + 3] !== 24'd0) != expect_ck[1][k]) e = -1;
check(e == 0, "screen 2: CRC identicon matches the CRC bits");
press(3'b001);
check(frame[16 * 96 + 14] === rgb(8'h1C) && frame[16 * 96 + 18] === rgb(8'h49) && frame[47 * 96 + 62] === 24'd0, "screen 3: prime map (7 prime, 9 not, 511 > N)");

// 7. BTNC: new data, this time skip shaking with BTNL
press(3'b010);
DIP = 16'h0000;
press(3'b100);
wait_led(8'h07, "BTNL seed: rerun with the predictor off, builds agree");
check_checksums;

$display("Passed: %0d, Failed: %0d", pass_count, fail_count);
if (fail_count == 0) $display("*** ALL TESTS PASSED! ***");
else $display("*** %0d TESTS FAILED ***", fail_count);
$finish;
end

always begin
	#5 CLK = ~CLK;
end

endmodule
