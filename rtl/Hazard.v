`timescale 1ns / 1ps
// Hazard unit for the 5-stage pipeline, following Chapter 5 (v2).

module Hazard(
	input [4:0] rs1D,
	input [4:0] rs2D,
	input [4:0] rs1E,
	input [4:0] rs2E,
	input [4:0] rdE,
	input [4:0] rdM,
	input [4:0] rdW,
	input RegWriteM,
	input RegWriteW,
	input MemtoRegE,
	input RedirectE, // E found that F fetched the wrong path (misprediction)
	input BusyE, // MCycle is busy
	output reg [1:0] ForwardAE, // 10: from M, 01: from W, 00: no forwarding
	output reg [1:0] ForwardBE,
	output Forward1D,
	output Forward2D,
	output StallF,
	output StallD,
	output StallE,
	output FlushD,
	output FlushE,
	output FlushM
);

	wire lwStall;

	// ================= M/W -> E forwarding =================
	always @(*) begin
		if ((rs1E == rdM) & RegWriteM & (rdM != 5'd0))
			ForwardAE = 2'b10;
		else if ((rs1E == rdW) & RegWriteW & (rdW != 5'd0))
			ForwardAE = 2'b01;
		else
			ForwardAE = 2'b00;
	end

	always @(*) begin
		if ((rs2E == rdM) & RegWriteM & (rdM != 5'd0))
			ForwardBE = 2'b10;
		else if ((rs2E == rdW) & RegWriteW & (rdW != 5'd0))
			ForwardBE = 2'b01;
		else
			ForwardBE = 2'b00;
	end

	// ================= W -> D forwarding =================
	assign Forward1D = (rs1D == rdW) & RegWriteW & (rdW != 5'd0);
	assign Forward2D = (rs2D == rdW) & RegWriteW & (rdW != 5'd0);

	// ================= stall / flush =================
	// load-use: hold F and D for one cycle and put a bubble into E
	assign lwStall = ((rs1D == rdE) | (rs2D == rdE)) & MemtoRegE & (rdE != 5'd0);

	assign StallF = lwStall | BusyE;
	assign StallD = lwStall | BusyE;
	assign StallE = BusyE;
	assign FlushD = RedirectE;
	assign FlushE = lwStall | RedirectE;
	assign FlushM = BusyE;

endmodule
