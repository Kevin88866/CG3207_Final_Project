`timescale 1ns / 1ps
// Testbench for test_Hazard.asm (CG3207 Asst 4). Module name test_Hazard; set it as the simulation top.
// Load mem_test_Hazard/AA_IROM.mem and AA_DMEM.mem. The program has no nops, so every case relies on the hazard unit.
// Pass: LED = FF, 7-seg = 600D600D. Fail: LED = N, 7-seg = BAD0000N (N = failed case).

module test_Hazard #(
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
reg [31:0] ACCEL_Data = 0;
wire ACCEL_DReady;
reg RESET = 0;
reg CLK = 0;

integer cycles = 0;
integer n_fwd_M = 0;
integer n_fwd_W = 0;
integer n_fwd_D = 0;
integer n_lw_stall = 0;
integer n_flush = 0;
reg [8*40-1:0] case_name [1:13];

Wrapper dut(DIP, PB, LED_OUT, LED_PC, SEVENSEGHEX, UART_TX, UART_TX_ready, UART_TX_valid, UART_RX, UART_RX_valid, UART_RX_ack, OLED_Write, OLED_Col, OLED_Row, OLED_Data, ACCEL_Data, ACCEL_DReady, RESET, CLK);

// count how often each hazard mechanism fires while the program runs
always @(posedge CLK) begin
	if (!RESET && LED_OUT == 0) begin
		cycles = cycles + 1;
		if (dut.RV1.ForwardAE == 2'b10 || dut.RV1.ForwardBE == 2'b10) n_fwd_M = n_fwd_M + 1;
		if (dut.RV1.ForwardAE == 2'b01 || dut.RV1.ForwardBE == 2'b01) n_fwd_W = n_fwd_W + 1;
		if (dut.RV1.Forward1D || dut.RV1.Forward2D) n_fwd_D = n_fwd_D + 1;
		if (dut.RV1.StallD && !dut.RV1.Busy_E) n_lw_stall = n_lw_stall + 1;
		if (dut.RV1.FlushD) n_flush = n_flush + 1;
	end
end

initial begin
case_name[1] = "M -> E forwarding";
case_name[2] = "W -> E forwarding";
case_name[3] = "W -> D forwarding";
case_name[4] = "M and W write same reg (M wins)";
case_name[5] = "load-use stall";
case_name[6] = "load then store the loaded value";
case_name[7] = "store data forwarding";
case_name[8] = "flush after taken branch / jal";
case_name[9] = "branch on forwarded value";
case_name[10] = "load then branch";
case_name[11] = "jalr on loaded rs1, link at target";
case_name[12] = "mul/div operand and result forwarding";
case_name[13] = "x0 is never forwarded";

RESET = 1; #10;
RESET = 0;

// wait() does not re-check $time, so the timeout runs in its own branch
fork : wait_done
	begin wait (LED_OUT != 0); disable wait_done; end
	begin #100000; disable wait_done; end
join
#1;

$display("Hazard events in %0d cycles:", cycles);
$display("    M -> E forwarding : %0d", n_fwd_M);
$display("    W -> E forwarding : %0d", n_fwd_W);
$display("    W -> D forwarding : %0d", n_fwd_D);
$display("    load-use stalls   : %0d", n_lw_stall);
$display("    flushes           : %0d", n_flush);

if (LED_OUT === 8'hFF && SEVENSEGHEX === 32'h600D600D)
	$display("*** ALL 13 CASES PASSED! ***");
else if (LED_OUT >= 1 && LED_OUT <= 13)
	$display("*** FAIL case %0d: %0s (7-seg = %h) ***", LED_OUT, case_name[LED_OUT], SEVENSEGHEX);
else
	$display("*** FAIL: program did not finish (LED = %h, 7-seg = %h) ***", LED_OUT, SEVENSEGHEX);
$finish;
end

always begin
	#5 CLK = ~CLK;
end

endmodule
