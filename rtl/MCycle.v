`timescale 1ns / 1ps
/* 
----------------------------------------------------------------------------------
--	(c) Shahzor Ahmad, Rajesh C Panicker
--	License terms :
--	You are free to use this code as long as you
--		(i) DO NOT post it on any public repository;
--		(ii) use it only for educational purposes;
--		(iii) accept that the program is provided "as is" without warranty of any kind or assurance regarding its suitability for any particular purpose;
--		(iv) send an email to rajesh.panicker@ieee.org briefly mentioning its use (except when used for the course CG3207 at the National University of Singapore);
--		(v) retain this notice in this file or any files derived from this.
----------------------------------------------------------------------------------
*/

// Multi-cycle unit: radix-4 Booth multiplication, restoring division.
module MCycle #(parameter width = 32)(
	input CLK,
	input RESET,
	input Start,
	input [1:0] MCycleOp,
	input [width-1:0] Operand1,
	input [width-1:0] Operand2,
	output reg [width-1:0] Result1,
	output reg [width-1:0] Result2,
	output reg Busy
	);

	localparam IDLE = 1'b0;
	localparam COMPUTING = 1'b1;
	// acc/mcand need 3 extra bits so acc +/- 2M cannot overflow; mq needs 2 for unsigned.
	localparam AW = width + 3;
	localparam QW = width + 2;
	// count value of the last iteration: signed mul, unsigned mul, divide.
	localparam LAST_S = width/2 - 1;
	localparam LAST_U = width/2;
	localparam LAST_D = width - 1;

	reg state = IDLE;
	reg n_state = IDLE;

	reg done = 1'b0;
	reg [7:0] count = 0;
	// Booth: acc = high part of the product, mq = multiplier (low product bits shift in at the top),
	// q_1 = bit shifted out of mq last cycle, mcand = multiplicand.
	reg [AW-1:0] acc = 0;
	reg [QW-1:0] mq = 0;
	reg q_1 = 1'b0;
	reg [AW-1:0] mcand = 0;
	reg [2*width-1:0] temp_sum = 0; // division: {remainder, quotient}

	reg [7:0] n_count;
	reg n_done;
	reg [AW-1:0] n_acc;
	reg [QW-1:0] n_mq;
	reg n_q_1;
	reg [AW-1:0] n_mcand;
	reg [2*width-1:0] n_temp_sum;
	reg [width-1:0] n_Result1;
	reg [width-1:0] n_Result2;

	reg [2:0] booth;
	reg [AW-1:0] pp;
	reg [AW-1:0] sum;

	reg div_neg1;
	reg div_neg2;
	reg [width-1:0] div_mag1;
	reg [width-1:0] div_mag2;
	reg [width:0] div_rem;

	// Busy rises in the same cycle as Start and falls once the last iteration is done.
	always @(*) begin : IDLE_PROCESS
	Busy = 1'b0;
	n_state = IDLE;
	if (~RESET)
		case (state)
			IDLE: begin
				if (Start) begin
					n_state = COMPUTING;
					Busy = 1'b1;
				end
			end
			COMPUTING: begin
				if (~done) begin
					n_state = COMPUTING;
					Busy = 1'b1;
				end
			end
		endcase
	end

	always @(*) begin : COMPUTING_PROCESS
	n_count = count;
	n_acc = acc;
	n_mq = mq;
	n_q_1 = q_1;
	n_mcand = mcand;
	n_temp_sum = temp_sum;
	n_Result1 = Result1;
	n_Result2 = Result2;
	n_done = 1'b0;
	booth = 3'b000;
	pp = 0;
	sum = 0;

	// First cycle: latch the operands (sign-extended for signed ops, zero-extended otherwise).
	if (RESET | (n_state == COMPUTING & state == IDLE)) begin
		n_count = 0;
		n_acc = 0;
		n_q_1 = 1'b0;
		n_mq = {{2{~MCycleOp[0] & Operand2[width-1]}}, Operand2};
		n_mcand = {{3{~MCycleOp[0] & Operand1[width-1]}}, Operand1};
		n_temp_sum = 0;
	end

	// Division works on magnitudes; the signs are fixed in the last cycle.
	div_neg1 = n_mcand[AW-1];
	div_neg2 = n_mq[QW-1];
	div_mag1 = div_neg1 ? -n_mcand[width-1:0] : n_mcand[width-1:0];
	div_mag2 = div_neg2 ? -n_mq[width-1:0] : n_mq[width-1:0];
	div_rem = 0;

	if (n_state == COMPUTING) begin
		if (~MCycleOp[1]) begin
			// Recode 3 bits into 0, +-M or +-2M.
			booth = {n_mq[1:0], n_q_1};
			if (booth == 3'b000 | booth == 3'b111)
				pp = 0;
			else if (booth == 3'b011 | booth == 3'b100)
				pp = {n_mcand[AW-2:0], 1'b0};
			else
				pp = n_mcand;

			// booth[2] = 1 means subtract: invert pp and add 1 through the carry-in.
			sum = n_acc + (pp ^ {AW{booth[2]}}) + booth[2];

			// Arithmetic shift {acc, mq, q_1} right by 2.
			n_q_1 = n_mq[1];
			n_mq = {sum[1:0], n_mq[QW-1:2]};
			n_acc = {{2{sum[AW-1]}}, sum[AW-1:2]};

			if ((MCycleOp[0] & n_count == LAST_U[7:0]) | (~MCycleOp[0] & n_count == LAST_S[7:0]))
				n_done = 1'b1;

			n_count = n_count + 1;

			// Take the 2*width-bit product out of {acc, mq}.
			if (MCycleOp[0]) begin
				n_Result2 = {n_acc[width-3:0], n_mq[QW-1:QW-2]};
				n_Result1 = n_mq[width-1:0];
			end
			else begin
				n_Result2 = n_acc[width-1:0];
				n_Result1 = n_mq[QW-1:2];
			end
		end
		else begin
			if (n_count == 0)
				n_temp_sum = {{width{1'b0}}, div_mag1};

			// Shift one dividend bit into the remainder; subtract the divisor if it fits.
			div_rem = n_temp_sum[2*width-1:width-1];
			if (div_rem >= {1'b0, div_mag2}) begin
				div_rem = div_rem - {1'b0, div_mag2};
				n_temp_sum = {div_rem[width-1:0], n_temp_sum[width-2:0], 1'b1};
			end
			else
				n_temp_sum = {n_temp_sum[2*width-2:0], 1'b0};

			// Quotient is negative if the signs differ; remainder takes the sign of the dividend.
			if (n_count == LAST_D[7:0]) begin
				if (div_neg1 ^ div_neg2)
					n_temp_sum[width-1:0] = -n_temp_sum[width-1:0];
				if (div_neg1)
					n_temp_sum[2*width-1:width] = -n_temp_sum[2*width-1:width];
				n_done = 1'b1;
			end

			n_count = n_count + 1;

			n_Result2 = n_temp_sum[2*width-1:width];
			n_Result1 = n_temp_sum[width-1:0];
		end
	end
	end

	always @(posedge CLK) begin : STATE_UPDATE_PROCESS
	state <= n_state;
	count <= n_count;
	done <= n_done;
	acc <= n_acc;
	mq <= n_mq;
	q_1 <= n_q_1;
	mcand <= n_mcand;
	temp_sum <= n_temp_sum;
	Result1 <= n_Result1;
	Result2 <= n_Result2;
	end

endmodule