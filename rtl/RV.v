`timescale 1ns / 1ps
/*
----------------------------------------------------------------------------------
-- Company: NUS
-- Engineer: (c) Rajesh Panicker
--
-- Create Date: 09/22/2020 06:49:10 PM
-- Module Name: RV
-- Project Name: CG3207 Project
-- Target Devices: Nexys 4 / Basys 3
-- Tool Versions: Vivado 2019.2
-- Description: RISC-V Processor Module
--
-- Dependencies: NIL
--
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments: The interface SHOULD NOT be modified (except making output reg) unless you modify Wrapper.v/vhd too.
						The implementation can be modified.
--
----------------------------------------------------------------------------------

----------------------------------------------------------------------------------
-- License terms :
-- You are free to use this code as long as you
-- (i) DO NOT post it on any public repository;
-- (ii) use it only for educational purposes;
-- (iii) accept the responsibility to ensure that your implementation does not violate anyone's intellectual property.
-- (iv) accept that the program is provided "as is" without warranty of any kind or assurance regarding its suitability for any particular purpose;
-- (v) send an email to rajesh<dot>panicker<at>ieee.org briefly mentioning its use (except when used for the course CG3207 at the National University of Singapore);
-- (vi) retain this notice in this file as well as any files derived from this.
----------------------------------------------------------------------------------
*/

// assignment 4: 5-stage pipeline (F, D, E, M, W). No hazard hardware: the program needs nops.
// The only stall is for MCycle: while Busy_E = 1, PC, F/D and D/E hold, and a bubble goes into E/M.

module RV #(
	parameter PC_INIT = 32'h00400000
)(
	input CLK,
	input RESET,
	input BP_Enable, // branch predictor on/off (DIP[15])
	//input Interrupt, // for optional future use.
	input [31:0] Instr,
	input [31:0] ReadData_in, // Name mangled to support lb/lbu/lh/lhu
	output MemRead,
	output [3:0] MemWrite_out, // Column-wise write enable to support sb/sw. Each column is a byte.
	output [31:0] PC,
	output [31:0] ALUResult,
	output [31:0] WriteData_out // Name mangled to support sb/sw
);

	// ================= F (fetch) =================
	wire [31:0] PC_F;
	wire [31:0] Instr_F;
	wire WE_PC;
	wire [31:0] PC_IN;
	wire [31:0] PC_Plus4_F;
	wire PrTaken_F;
	wire [31:0] PrBTA_F;

	// ================= D (decode) =================
	reg [31:0] Instr_D;
	reg [31:0] PC_D;
	reg PrTaken_D;
	reg [31:0] PrBTA_D;
	wire [6:0] Opcode_D;
	wire [2:0] Funct3_D;
	wire [6:0] Funct7_D;
	wire [4:0] rs1_D, rs2_D, rd_D;
	wire [24:0] InstrImm_D;
	wire [1:0] PCS_D;
	wire RegWrite_D, MemWrite_D, MemtoReg_D;
	wire [1:0] ALUSrcA_D, ALUSrcB_D;
	wire [2:0] ImmSrc_D;
	wire [3:0] ALUControl_D;
	wire Start_D;
	wire [1:0] MCycleOp_D;
	wire MCycleSel_D;
	wire [31:0] RD1_RF_D, RD2_RF_D;
	wire [31:0] RD1_D, RD2_D; // after W -> D forwarding
	wire [31:0] ExtImm_D;

	// ================= E (execute) =================
	reg [31:0] PC_E, RD1_E, RD2_E, ExtImm_E;
	reg [4:0] rd_E, rs1_E, rs2_E;
	reg [31:0] RD1_Fwd_E, RD2_Fwd_E; // after M/W -> E forwarding
	reg [2:0] Funct3_E;
	reg [1:0] PCS_E;
	reg RegWrite_E, MemWrite_E, MemtoReg_E;
	reg [1:0] ALUSrcA_E, ALUSrcB_E;
	reg [3:0] ALUControl_E;
	reg Start_E;
	reg [1:0] MCycleOp_E;
	reg MCycleSel_E;
	reg [31:0] Src_A_E, Src_B_E;
	wire [31:0] ALUResult_E;
	wire [2:0] ALUFlags_E;
	wire [1:0] PCSrc_E;
	wire Busy_E;
	wire [31:0] MCycleResult_E, MCycleResult2_E;
	wire [31:0] ExecResult_E;
	reg PrTaken_E;
	reg [31:0] PrBTA_E;
	wire [31:0] PC_Base_E, PC_Offset_E, PC_Sum_E;
	wire [31:0] PCNext_E; // where the instruction after the one in E really is
	wire IsBranch_E, Taken_E, Mispredict_E;

	// ================= M (memory) =================
	reg RegWrite_M, MemWrite_M, MemtoReg_M;
	reg [31:0] ExecResult_M, WriteData_M;
	reg [4:0] rd_M;
	wire [31:0] ReadData_M;

	// ================= W (writeback) =================
	reg RegWrite_W, MemtoReg_W;
	reg [31:0] ReadData_W, ExecResult_W;
	reg [4:0] rd_W;
	wire [31:0] Result_W;

	// ================= Hazard unit =================
	wire [1:0] ForwardAE, ForwardBE;
	wire Forward1D, Forward2D;
	wire StallF, StallD, StallE, FlushD, FlushE, FlushM;
	wire Redirect_E;

	// ---------------- connections to the Wrapper ----------------
	assign PC = PC_F;
	assign Instr_F = Instr;
	assign ALUResult = ExecResult_M; // data memory / MMIO address
	assign WriteData_out = WriteData_M;
	assign MemWrite_out = {4{MemWrite_M}};
	assign MemRead = MemtoReg_M;
	assign ReadData_M = ReadData_in;

	// ================= F stage logic =================
	// Fetch the predicted target if the BTB says taken, else PC_F + 4.
	// A misprediction found in E overrides both.
	assign PC_Plus4_F = PC_F + 32'd4;
	assign PC_IN = Mispredict_E ? PCNext_E : (PrTaken_F ? PrBTA_F : PC_Plus4_F);
	assign WE_PC = ~StallF;

	ProgramCounter #(.PC_INIT(PC_INIT)) ProgramCounter1(
		CLK,
		RESET,
		WE_PC,
		PC_IN,
		PC_F
	);

	// ================= F/D pipeline register =================
	// flush: all 0s decodes as a NOP in our Decoder
	always @(posedge CLK) begin
		if (RESET | FlushD) begin
			Instr_D <= 32'd0;
			PC_D <= 32'd0;
			PrTaken_D <= 1'b0;
			PrBTA_D <= 32'd0;
		end
		else if (~StallD) begin
			Instr_D <= Instr_F;
			PC_D <= PC_F;
			PrTaken_D <= PrTaken_F;
			PrBTA_D <= PrBTA_F;
		end
	end
	// ================= D stage logic =================
	assign Opcode_D = Instr_D[6:0];
	assign rd_D = Instr_D[11:7];
	assign Funct3_D = Instr_D[14:12];
	assign rs1_D = Instr_D[19:15];
	assign rs2_D = Instr_D[24:20];
	assign Funct7_D = Instr_D[31:25];
	assign InstrImm_D = Instr_D[31:7];

	Decoder Decoder1(
		Opcode_D,
		Funct3_D,
		Funct7_D,
		PCS_D,
		RegWrite_D,
		MemWrite_D,
		MemtoReg_D,
		ALUSrcA_D,
		ALUSrcB_D,
		ImmSrc_D,
		ALUControl_D,
		Start_D,
		MCycleOp_D,
		MCycleSel_D
	);

	// Read in D, write in W, both on the same rising edge.
	RegFile RegFile1(
		CLK,
		RegWrite_W,
		rs1_D,
		rs2_D,
		rd_W,
		Result_W,
		RD1_RF_D,
		RD2_RF_D
	);

	// W -> D forwarding (RegFile is written on the same edge)
	assign RD1_D = Forward1D ? Result_W : RD1_RF_D;
	assign RD2_D = Forward2D ? Result_W : RD2_RF_D;

	Extend Extend1(
		ImmSrc_D,
		InstrImm_D,
		ExtImm_D
	);

	// ================= D/E pipeline register =================
	always @(posedge CLK) begin
		if (RESET | FlushE) begin
			PC_E <= 32'd0; RD1_E <= 32'd0; RD2_E <= 32'd0; ExtImm_E <= 32'd0;
			rd_E <= 5'd0; rs1_E <= 5'd0; rs2_E <= 5'd0;
			Funct3_E <= 3'd0; PCS_E <= 2'd0;
			PrTaken_E <= 1'b0; PrBTA_E <= 32'd0;
			RegWrite_E <= 1'b0; MemWrite_E <= 1'b0; MemtoReg_E <= 1'b0;
			ALUSrcA_E <= 2'd0; ALUSrcB_E <= 2'd0; ALUControl_E <= 4'd0;
			Start_E <= 1'b0; MCycleOp_E <= 2'd0; MCycleSel_E <= 1'b0;
		end
		else if (~StallE) begin
			PC_E <= PC_D; RD1_E <= RD1_D; RD2_E <= RD2_D; ExtImm_E <= ExtImm_D;
			rd_E <= rd_D; rs1_E <= rs1_D; rs2_E <= rs2_D;
			Funct3_E <= Funct3_D; PCS_E <= PCS_D;
			PrTaken_E <= PrTaken_D; PrBTA_E <= PrBTA_D;
			RegWrite_E <= RegWrite_D; MemWrite_E <= MemWrite_D; MemtoReg_E <= MemtoReg_D;
			ALUSrcA_E <= ALUSrcA_D; ALUSrcB_E <= ALUSrcB_D; ALUControl_E <= ALUControl_D;
			Start_E <= Start_D; MCycleOp_E <= MCycleOp_D; MCycleSel_E <= MCycleSel_D;
		end
	end

	// ================= E stage logic =================
	// M/W -> E forwarding
	always @(*) begin
		case (ForwardAE)
			2'b10: RD1_Fwd_E = ExecResult_M;
			2'b01: RD1_Fwd_E = Result_W;
			default: RD1_Fwd_E = RD1_E;
		endcase
	end

	always @(*) begin
		case (ForwardBE)
			2'b10: RD2_Fwd_E = ExecResult_M;
			2'b01: RD2_Fwd_E = Result_W;
			default: RD2_Fwd_E = RD2_E;
		endcase
	end

	always @(*) begin
		case (ALUSrcA_E)
			2'b01: Src_A_E = 32'd0;
			2'b11: Src_A_E = PC_E;
			default: Src_A_E = RD1_Fwd_E;
		endcase
	end

	always @(*) begin
		case (ALUSrcB_E)
			2'b01: Src_B_E = 32'd4;
			2'b11: Src_B_E = ExtImm_E;
			default: Src_B_E = RD2_Fwd_E;
		endcase
	end

	ALU ALU1(
		Src_A_E,
		Src_B_E,
		ALUControl_E,
		ALUResult_E,
		ALUFlags_E
	);

	PC_Logic PC_Logic1(
		PCS_E,
		Funct3_E,
		ALUFlags_E,
		PCSrc_E
	);

	MCycle #(.width(32)) MCycle1(
		.CLK(CLK),
		.RESET(RESET),
		.Start(Start_E),
		.MCycleOp(MCycleOp_E),
		.Operand1(RD1_Fwd_E),
		.Operand2(RD2_Fwd_E),
		.Result1(MCycleResult_E),
		.Result2(MCycleResult2_E),
		.Busy(Busy_E)
	);

	assign ExecResult_E = MCycleSel_E ? MCycleResult_E : ALUResult_E;

	// ================= branch resolution + predictor =================
	// Real next PC of the instruction in E: target if taken (rs1 + imm for jalr), else PC_E + 4
	assign PC_Base_E = (PCSrc_E == 2'b10) ? RD1_Fwd_E : PC_E;
	assign PC_Offset_E = (PCSrc_E == 2'b00) ? 32'd4 : ExtImm_E;
	assign PC_Sum_E = PC_Base_E + PC_Offset_E;
	assign PCNext_E = {PC_Sum_E[31:1], 1'b0};

	assign IsBranch_E = (PCS_E != 2'b00);
	assign Taken_E = (PCSrc_E != 2'b00);
	assign Redirect_E = Mispredict_E; // flush only when F fetched the wrong path

	BranchPredictor #(.IDX_BITS(4)) BranchPredictor1(
		.CLK(CLK),
		.RESET(RESET),
		.Enable(BP_Enable),
		.PC_F(PC_F),
		.PrTaken_F(PrTaken_F),
		.PrBTA_F(PrBTA_F),
		.Stall_E(StallE),
		.PC_E(PC_E),
		.IsBranch_E(IsBranch_E),
		.Taken_E(Taken_E),
		.Target_E(PCNext_E),
		.PrTaken_E(PrTaken_E),
		.PrBTA_E(PrBTA_E),
		.Mispredict_E(Mispredict_E)
	);

	Hazard Hazard1(
		.rs1D(rs1_D),
		.rs2D(rs2_D),
		.rs1E(rs1_E),
		.rs2E(rs2_E),
		.rdE(rd_E),
		.rdM(rd_M),
		.rdW(rd_W),
		.RegWriteM(RegWrite_M),
		.RegWriteW(RegWrite_W),
		.MemtoRegE(MemtoReg_E),
		.RedirectE(Redirect_E),
		.BusyE(Busy_E),
		.ForwardAE(ForwardAE),
		.ForwardBE(ForwardBE),
		.Forward1D(Forward1D),
		.Forward2D(Forward2D),
		.StallF(StallF),
		.StallD(StallD),
		.StallE(StallE),
		.FlushD(FlushD),
		.FlushE(FlushE),
		.FlushM(FlushM)
	);

	// ================= E/M pipeline register =================
	always @(posedge CLK) begin
		if (RESET | FlushM) begin
			RegWrite_M <= 1'b0; MemWrite_M <= 1'b0; MemtoReg_M <= 1'b0;
			ExecResult_M <= 32'd0; WriteData_M <= 32'd0; rd_M <= 5'd0;
		end
		else begin
			RegWrite_M <= RegWrite_E; MemWrite_M <= MemWrite_E; MemtoReg_M <= MemtoReg_E;
			ExecResult_M <= ExecResult_E; WriteData_M <= RD2_Fwd_E; rd_M <= rd_E;
		end
	end
	// ================= M/W pipeline register =================
	always @(posedge CLK) begin
		if (RESET) begin
			RegWrite_W <= 1'b0; MemtoReg_W <= 1'b0;
			ReadData_W <= 32'd0; ExecResult_W <= 32'd0; rd_W <= 5'd0;
		end
		else begin
			RegWrite_W <= RegWrite_M; MemtoReg_W <= MemtoReg_M;
			ReadData_W <= ReadData_M; ExecResult_W <= ExecResult_M; rd_W <= rd_M;
		end
	end

	// ================= W stage logic =================
	assign Result_W = MemtoReg_W ? ReadData_W : ExecResult_W;

endmodule
