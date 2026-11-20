`timescale 1ns / 1ps
// System testbench for the branch predictor. Program: bp_test.asm (assemble with RARS,
// dump .text as HexText to AA_IROM.mem). Set test_Wrapper_BP as the simulation top.
//
// The program is run twice from reset: predictor off (DIP[15] = 0), then on (DIP[15] = 1).
// Each run must end with 7-seg = EXPECTED (the value RARS computes) and LEDs = A5.
// It reports cycles, branches, taken branches and mispredictions for each run.

module test_Wrapper_BP #(
    parameter [31:0] EXPECTED = 32'h0000_0238,
    parameter integer TIMEOUT_CYCLES = 20000
)();

reg  [15:0] DIP = 0;
reg  [2:0]  PB = 0;
wire [7:0]  LED_OUT;
wire [6:0]  LED_PC;
wire [31:0] SEVENSEGHEX;
wire [7:0]  UART_TX;
reg         UART_TX_ready = 0;
wire        UART_TX_valid;
reg  [7:0]  UART_RX = 0;
reg         UART_RX_valid = 0;
wire        UART_RX_ack;
wire        OLED_Write;
wire [6:0]  OLED_Col;
wire [5:0]  OLED_Row;
wire [23:0] OLED_Data;
reg  [31:0] ACCEL_Data = 0;
wire        ACCEL_DReady;
reg         RESET = 0;
reg         CLK = 0;

Wrapper dut(DIP, PB, LED_OUT, LED_PC, SEVENSEGHEX, UART_TX, UART_TX_ready, UART_TX_valid, UART_RX, UART_RX_valid, UART_RX_ack, OLED_Write, OLED_Col, OLED_Row, OLED_Data, ACCEL_Data, ACCEL_DReady, RESET, CLK);

always #5 CLK = ~CLK;

// event counters, from the E stage of the core
integer n_branch = 0, n_taken = 0, n_mispredict = 0;
always @(posedge CLK) begin
    if (RESET) begin
        n_branch = 0; n_taken = 0; n_mispredict = 0;
    end
    else if (~dut.RV1.Busy_E) begin
        if (dut.RV1.IsBranch_E)    n_branch = n_branch + 1;
        if (dut.RV1.Taken_E)       n_taken = n_taken + 1;
        if (dut.RV1.Mispredict_E)  n_mispredict = n_mispredict + 1;
    end
end

integer fails = 0;
integer cycles_off = 0, cycles_on = 0;

task run;
    input bp_on;
    output integer cycles;
    integer t;
    begin
        DIP = bp_on ? 16'h8000 : 16'h0000;
        RESET = 1;
        repeat (4) @(posedge CLK);     // also lets the 2-flip-flop DIP synchroniser settle
        #1 RESET = 0;
        t = 0;
        while (LED_OUT !== 8'hA5 && t < TIMEOUT_CYCLES) begin
            @(posedge CLK); t = t + 1;
        end
        #1;
        cycles = dut.cycle_count;
        if (LED_OUT !== 8'hA5) begin
            $display("FAIL BP %s: timed out (LED = %h, 7-seg = %h)", bp_on ? "on " : "off", LED_OUT, SEVENSEGHEX);
            fails = fails + 1;
        end
        else if (SEVENSEGHEX !== EXPECTED) begin
            $display("FAIL BP %s: 7-seg = %h, expected %h", bp_on ? "on " : "off", SEVENSEGHEX, EXPECTED);
            fails = fails + 1;
        end
        else
            $display("PASS BP %s: 7-seg = %h, %0d cycles, %0d branches/jumps, %0d taken, %0d mispredicted",
                     bp_on ? "on " : "off", SEVENSEGHEX, cycles, n_branch, n_taken, n_mispredict);
    end
endtask

initial begin
    run(1'b0, cycles_off);
    run(1'b1, cycles_on);
    if (fails == 0)
        $display("Speedup with the predictor: %0d -> %0d cycles (%0d%% fewer)",
                 cycles_off, cycles_on, (100 * (cycles_off - cycles_on)) / cycles_off);
    if (fails == 0) $display("*** ALL TESTS PASSED! ***");
    else            $display("*** %0d TESTS FAILED ***", fails);
    $finish;
end

endmodule
