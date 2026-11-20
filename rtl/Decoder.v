`timescale 1ns / 1ps
/*
----------------------------------------------------------------------------------
-- Company: NUS	
-- Engineer: (c) Rajesh Panicker  
-- 
-- Create Date: 09/22/2020 06:49:10 PM
-- Module Name: Decoder
-- Project Name: CG3207 Project
-- Target Devices: Nexys 4 / Basys 3
-- Tool Versions: Vivado 2019.2
-- Description: RISC-V Processor Decoder Module
-- 
-- Dependencies: NIL
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments: Interface and implementation can be modified.
-- 
----------------------------------------------------------------------------------

----------------------------------------------------------------------------------
--	License terms :
--	You are free to use this code as long as you
--		(i) DO NOT post it on any public repository;
--		(ii) use it only for educational purposes;
--		(iii) accept the responsibility to ensure that your implementation does not violate anyone's intellectual property.
--		(iv) accept that the program is provided "as is" without warranty of any kind or assurance regarding its suitability for any particular purpose;
--		(v) send an email to rajesh<dot>panicker<at>ieee.org briefly mentioning its use (except when used for the course CG3207 at the National University of Singapore);
--		(vi) retain this notice in this file as well as any files derived from this.
----------------------------------------------------------------------------------
*/

module Decoder(
    input [6:0] Opcode ,
    input [2:0] Funct3 ,
    input [6:0] Funct7 ,
    output reg [1:0] PCS,		// 00 for non-control, 01 for conditional branch, 10 for jal, 11 for jalr
    output reg RegWrite,		// Asserted only by instructions which write to register file (load, auipc, lui, DPImm, DPReg);
    output reg MemWrite,		// Asserted only by store (sw)
    output reg MemtoReg,		// Asserted only by load (lw)
    output reg [1:0] ALUSrcA, 	// Needed for lui, auipic. Refer to the microarchitecture for its use. Uncomment wire and port map in RV.v as well
    output reg [1:0] ALUSrcB,		// Asserted by all instructions which use an immediate (load, store, lui, auipc, DPImm). Needs to be expanded to a 2-bit signal to support link functionality for jal, jalr. Change wire width in RV.v as well
    output reg [2:0] ImmSrc, 	// 000 for U, 010 for UJ, 011 for I, 110 for S, 111 for SB.
    output reg [3:0] ALUControl,	// 0000 for add, 0001 for sub, 1110 for and, 1100 for or, 0010 for sll, 1010 for srl, 1011 for sra, 0001 for branch, 0000 for all others.
    					// Note that the most significant 3 bits are Funct3 for all DP instrns. LSB is the same as Funct[5] for DPReg type and DPImm_shifts. For other DPImms, Funct[5] is 0.
    					// It is the same as sub for branches, and add for all others not mentioned in the line above.
    // assignment 3 additions:
    output reg Start,           // 1 for mul, div, divu. Starts the MCycle unit
    output reg [1:0] MCycleOp,  // 00 signed mul, 01 unsigned mul, 10 signed div, 11 unsigned div
    output reg MCycleSel        // 1 = write back the MCycle result instead of the ALU result
    ); 
// Change wire to reg if assigned inside a procedural (always) block. However, where it is easy enough, use assign instead of always.
// A 2-1 multiplexing can be done easily using an assign with a ternary operator
// For multiplexing with number of inputs > 2, a case construct within an always block is a natural fit. DO NOT to use nested ternary assignment operator as it hampers the readability of your code.
    
    	// todo: Implement Decoder here

    localparam DP = 7'b0110011; // add, sub, and, or, sll, srl, sra
    localparam DP_IMM = 7'b0010011; // addi, andi, ori
    localparam LOAD = 7'b0000011; // lw
    localparam STORE = 7'b0100011; // sw
    localparam BRANCH = 7'b1100011; // beq, bne
    localparam LUI = 7'b0110111;
    localparam AUIPC = 7'b0010111;
    localparam JAL = 7'b1101111;
    localparam JALR = 7'h67;

    always @(*) begin
        // Defaults. Every output is written on every path, so this cannot infer a latch.
        // PCS, RegWrite and MemWrite stay 0 unless an arm below sets them.
        PCS = 2'b00;
        RegWrite = 1'b0;
        MemWrite = 1'b0;
        MemtoReg = 1'b0;
        ALUSrcA = 2'b00;
        ALUSrcB = 2'b00;
        ImmSrc = 3'b000;
        ALUControl = 4'b0000;
        // assignment 3 defaults:
        Start = 1'b0;
        MCycleOp = 2'b00;
        MCycleSel = 1'b0;

        case (Opcode)
            DP: begin   // assignment 3 addition
                if (Funct7 == 7'b0000001) begin
                    // M extension (same opcode as add/sub, Funct7 = 0000001).
                    // Only mul (000), div (100), divu (101); other M instructions write nothing.
                    if (Funct3 == 3'b000 || Funct3 == 3'b100 || Funct3 == 3'b101) begin
                        RegWrite = 1'b1;
                        Start = 1'b1;
                        MCycleOp = {Funct3[2], Funct3[0]};   // mul 00, div 10, divu 11
                        MCycleSel = 1'b1;
                    end
                end
                else begin
                    RegWrite = 1'b1;
                    ALUControl = {Funct3, Funct7[5]};
                end
            end

            DP_IMM: begin
                RegWrite = 1'b1;
                ALUSrcB = 2'b11;
                ALUControl = {Funct3, (Funct3 == 3'h5) ? Funct7[5] : 1'b0} ; // imm[10] is the same bit as funct7[5], pg 18
                ImmSrc = 3'b011;
            end

            LOAD: begin
                MemtoReg = 1'b1;
                RegWrite = 1'b1;
                ALUSrcB = 2'b11;
                ImmSrc = 3'b011;
            end

            STORE: begin
                MemWrite = 1'b1;
                ALUSrcB = 2'b11;
                ImmSrc = 3'b110;
            end

            BRANCH: begin
                PCS = 2'b01;
                ImmSrc = 3'b111;
                ALUControl = 4'b0001;
            end

            LUI: begin
                RegWrite = 1'b1;
                ALUSrcA = 2'b01;
                ALUSrcB = 2'b11;
            end

            AUIPC: begin
                RegWrite = 1'b1;
                ALUSrcA = 2'b11;
                ALUSrcB = 2'b11;
            end

            JAL: begin
                PCS = 2'b10;
                RegWrite = 1'b1;
                ALUSrcA = 2'b11;
                ALUSrcB = 2'b01;
                ImmSrc = 3'b010;
            end
            
            JALR: begin
                PCS = 2'b11;
                RegWrite = 1'b1;
                ALUSrcA = 2'b11;
                ALUSrcB = 2'b01;
                ImmSrc = 3'b011;
            end

        endcase
    end
	
	    
endmodule



