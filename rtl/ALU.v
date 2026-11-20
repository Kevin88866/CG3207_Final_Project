`timescale 1ns / 1ps
/*
----------------------------------------------------------------------------------
-- Company: NUS	
-- Engineer: (c) Rajesh Panicker  
-- 
-- Create Date: 09/22/2020 06:49:10 PM
-- Module Name: ALU
-- Project Name: CG3207 Project
-- Target Devices: Nexys 4 / Basys 3
-- Tool Versions: Vivado 2019.2
-- Description: RISC-V Processor ALU Module
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

module ALU(
	input [31:0] Src_A,
	input [31:0] Src_B,
	input [3:0] ALUControl, // 0000 for add, 0001 for sub, 1110 for and, 1100 for or, 1000 for xor, 0100 for slt, 0110 for sltu 0010 for sll, 1010 for srl, 1011 for sra.
	output reg [31:0] ALUResult,
	output [2:0] ALUFlags //{eq, lt, ltu}
);
    
	// Shifter signals
	wire [1:0] Sh ;
	wire [4:0] Shamt5 ;	// 5 bit shift amount
	wire [31:0] ShIn ;	//	number to shift
	wire [31:0] ShOut ;	//	result after shifting
	
	// Other signals
	wire [32:0] S_wider ; // 33 bits (bit 32 = extra carry, 31:0 = normal 32-bit result)
	reg [32:0] Src_A_comp ;
	reg [32:0] Src_B_comp ;
	reg [32:0] C_0 ;
	wire SubOp;
	// N = Negative, Z = zero, C = carry, V = signed overflow
	wire N, Z, C, V; 	// optional intermediate values to derive eq, lt, ltu
				// Hint: We need to care about V only for subtraction
	
	assign S_wider = Src_A_comp + Src_B_comp + C_0 ;

	// SUB, SLT and SLTU all use A - B internally
	assign SubOp = (ALUControl == 4'b0001) || (ALUControl == 4'b0100) || (ALUControl == 4'b0110);

	// N: bit 31 is the sign bit of a 32 bit twos complement value
	// If it is 1, the 32 bit result appears negative
	assign N = S_wider[31];

	// C: S_wider is 33 bits instead of 32 bits specficially so that
	// any carry out of bit 31 is preserved in bit 32
	assign C = S_wider[32];
    
	// V: overflow matters for signed comparison

	// during subtraction, signed overflow occurs when:
	//	Src_A and Src_B have different signs and the subtraction
	//	result has a different sign from Src_A

	// signed overflow is relevant whenever aLU uses subtraction for a signed comparison
	assign V = SubOp & (Src_A[31] ^ Src_B[31]) & (S_wider[31] ^ Src_A[31]);

	// Z: for branch comparisons, the ALU performs Src_A - Src_B
	// If the subtraction result is zero, A and B are equal

	// Reduction OR (|) ORs every bit together
	// ~| therefore produces 1 only when every result bit is zero.
	assign Z = ~|S_wider[31:0];



	always@(*) begin
        // default values; help avoid latches
		C_0 = 0 ; 
		Src_A_comp = {1'b0, Src_A} ;
		Src_B_comp = {1'b0, Src_B} ;

		// sub, slt and sltu compare Src_A and Src_B using subtraction
		// subtraction is performed using twos complement:
		// A - B = A + (~B) + 1
		if (SubOp) begin
			C_0[0] = 1'b1;
			Src_B_comp = {1'b0, ~Src_B};
		end
    
		case(ALUControl)
			// ADD
			4'b0000: ALUResult = S_wider[31:0] ;	//add 
			// SUB: SubOp causes S_wider to contain A - B      
	        4'b0001: ALUResult = S_wider[31:0]	;	//sub
			// AND
			4'b1110: ALUResult = Src_A & Src_B ;	// and
			// OR
			4'b1100: ALUResult = Src_A | Src_B ; 	// or
			// XOR: each result bit is 1 when the corresponding bits of Src_A and Src_B are different
			4'b1000: ALUResult = Src_A ^ Src_B;		// xor
			// SLT: signed set lessthan
			// N ^ V gives the correct signal A < B comparison
			// ALUResult must contain 32 bit 1 if A < B otherwise contains 32 bit 0
			4'b0100: ALUResult = {31'b0, (N^V)};	// slt
			// SLTU: unsigned set less than
			// no carry out from A - Bmeans a borrow occured which means unsigned A < B
			4'b0110: ALUResult = {31'b0, ~C};
	            
			// include cases for shifts
			// shifts operations

			// the shifter module performs the actual shifting
			// ALUControl determines what kind of shift the shifter performs through the Sh signal

			// ShOut contains the result produced by Shifter.v
			4'b0010: ALUResult = ShOut;	// SLL
			4'b1010: ALUResult = ShOut;	// SRL
			4'b1011: ALUResult = ShOut;	// SRA

			// if ALUControl is something we have not implemented
			// drive X so an unsupported operation is obvious in simulation
			default: ALUResult = 32'bx;
	        endcase
	    end
      
    
	// ALUFlags = {eq, lt, ltu}
	// eq: A==B when A-B = 0
	// lt: signed less than; N alone is not sufficient if signed overflow occurred, so signed less than is N XOR V
	// ltu: unsigned less than; during A-B, no carry out means a borrow occurred, which means A<B for unsigned numbers
	assign ALUFlags = {Z, (N^V), ~C};     
    
	// shifter connections here
	// Sh signals can be derived directly from the appropriate ALUControl bits
    
	// select which type of shift the shifter performs
	// Shifter.v:
	// 2'b00 = SLL (shift left logical)
	// 2'b10 = SRL (shift right logical)
	// 2'b11 = SRA (shift right arithmetic)

	// the required 2 bits already exist inside ALUControl
	// meaning combine ALUControl[3] and ALUControl[0]

	assign Sh = {ALUControl[3], ALUControl[0]};

	// RISC-V RV32 instructions operate on 32-bit values
	// therefore the shift amount can only be from 0 - 31

	// 5 bits can represent exactly 0-31
	// so only lowest 5 bits of Src_B are sent to the Shifter
	assign Shamt5 = Src_B[4:0];

	// Src_A is the actual 32-bit number that we want to shift
	assign ShIn = Src_A;

    
	// Instantiate Shifter        
	Shifter Shifter1(
            Sh,
        	Shamt5,
        	ShIn,
        	ShOut
        );
     
endmodule
