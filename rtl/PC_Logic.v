`timescale 1ns / 1ps
/*
----------------------------------------------------------------------------------
-- Company: NUS	
-- Engineer: (c) Rajesh Panicker  
-- 
-- Create Date: 09/22/2020 06:49:10 PM
-- Module Name: CondLogic
-- Project Name: CG3207 Project
-- Target Devices: Nexys 4 / Basys 3
-- Tool Versions: Vivado 2019.2
-- Description: RISC-V Processor Conditional Logic Module
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

module PC_Logic( // This is a combinational module, unlike ARM. See the note below.
	input [1:0] PCS,	// 00 for non-control, 01 for conditional branch, 10 for jal, 11 for jalr
	input [2:0] Funct3,	// condition specified in the instruction (eq / ne / lt / ge / ltu / geu)
	input [2:0] ALUFlags, 	// {eq, lt, ltu}
	// output reg PCSRC selects where the next PC comes from:
	// 00 = normal PC + 4
	// 01 = branch/JAL target (PC + immediate)
	// 10 = JALR target (rs1 + immediate)
	output reg [1:0] PCSrc	// expanded to 2 bits to support jalr
    );
    
    /* 
    	Important Note : ALUFlags are not *stored* in flag registers in RISC-V, unlike ARM and most other processors.
    	In RISC-V, the flags are produced and consumed in the same branch instruction. 
    	The effect of CMP R1, R2 and BEQ LABEL in ARM is beq x1, x2, LABEL in RISC-V.
    */
    
    
	// conditional logic goes here
	always @(*) begin
		// default: execute the next sequential instruction
		// PCSrc = 00 will eventually select PC + 4
		PCSrc = 2'b00;

		case (PCS)
			// normal instruction. not a branch or jump
			// continue to next sequential instruction PC + 4
			2'b00: begin
				PCSrc = 2'b00;
			end
			
			// conditional branch: Funct3 determines which branch condition is being tested
			// ALUFlags:
			// ALUFlags[2] = eq
			// ALUFlags[1] = signed lt
	 		// ALUFlags[0] = unsigned ltu
       		 2'b01: begin

			 case (Funct3)
			 	// BEQ: branch if equal
				// if eq = 1, choose the branch target, otherwise continue with PC + 4
				// branch when A == B
				3'b000:
					if (ALUFlags[2])
						PCSrc = 2'b01;
					else
						PCSrc = 2'b00;
				
				// BNE: branch if not equal
				3'b001:
					if (!ALUFlags[2])
						PCSrc = 2'b01;
					else
						PCSrc = 2'b00;
				
				// BLT: signed branch if less than
				// ALUFlags[1] contains the signed A < B
				3'b100:
					if(ALUFlags[1])
						PCSrc = 2'b01;
					else
						PCSrc = 2'b00;
				
				// BGE: signed branch if greater than or equal
				// if A is not less than B, then A >= B
				3'b101:
					if(!ALUFlags[1])
						PCSrc = 2'b01;
					else
						PCSrc = 2'b00;
				
				// BLTU: unsigned branch if less than
				// ALUFlags[0] contains unsigned A < B
				3'b110:
					if(ALUFlags[0])
						PCSrc = 2'b01;
					else	
						PCSrc = 2'b00;
				
				// BGEU: unsigned branch if greater than or equal
				3'b111:
					if (!ALUFlags[0])
						PCSrc = 2'b01;
					else
						PCSrc = 2'b00;
				
				// unsupported branch Funct3: remain on normal PC + 4 path
				default:
					PCSrc = 2'b00;
			 endcase
			end	
		
		// JAL: always jumps
		// its target is PC + immediate 
		2'b10: begin
			PCSrc = 2'b01;
		end

		// JALR: also unconditional, but target is rs1 + immediate rather than PC + immediate
		// meaning different PC source
		2'b11: begin
			PCSrc = 2'b10;
		end

		// default/safety case
		default: begin
			PCSrc = 2'b00;
		end
	endcase
end


endmodule













