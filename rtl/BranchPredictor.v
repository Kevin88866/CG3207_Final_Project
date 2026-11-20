`timescale 1ns / 1ps
/*
----------------------------------------------------------------------------------
-- Module Name: BranchPredictor
-- Project Name: CG3207 Project, Assignment 4 enhancement
-- Description: Dynamic branch predictor: a direct-mapped, tagged branch target
--              buffer (BTB), each entry with a 2-bit saturating counter.
--
--   F stage: the BTB is read with PC_F. On a hit whose counter says taken
--            (counter[1] = 1), F fetches the stored target next instead of PC_F + 4.
--   E stage: the branch / jump is resolved. The prediction made in F (carried
--            through F/D and D/E) is checked against the real outcome, and the
--            entry is updated.
--
--   Mispredict_E = 1 means that the two instructions fetched after the one in E
--   (now in F and D) are on the wrong path: flush D and E and load PCNext_E into PC.
--
--   Entry   = {valid, tag = PC[31:IDX_BITS+2], target[31:2], counter[1:0]}
--   Counter : 00 strongly not taken, 01 weakly not taken, 10 weakly taken, 11 strongly taken
--   Only taken branches / jumps allocate an entry (new entries start at 10, weakly taken).
--   A not-taken branch that misses the BTB is predicted correctly (not taken), so it
--   does not need an entry.
--
--   Enable = 0 turns prediction off: F always fetches PC + 4, so every taken branch
--   costs a 2-cycle flush (the same as plain "predict not taken" hazard hardware).
--   The table keeps training, so turning it on mid-run starts from a warm table.
----------------------------------------------------------------------------------
*/

module BranchPredictor #(
    parameter IDX_BITS = 4              // 2^IDX_BITS entries. 4 = 16 entries.
)(
    input CLK,
    input RESET,
    input Enable,

    // ---------- F stage: lookup ----------
    input  [31:0] PC_F,
    output        PrTaken_F,            // predict taken: fetch PrBTA_F next
    output [31:0] PrBTA_F,              // predicted branch target address

    // ---------- E stage: resolve and update ----------
    input         Stall_E,              // E is held (MCycle busy): do not update
    input  [31:0] PC_E,
    input         IsBranch_E,           // conditional branch, jal or jalr in E
    input         Taken_E,              // the instruction in E really changes the PC
    input  [31:0] Target_E,             // its real target (used when Taken_E)
    input         PrTaken_E,            // what F predicted for this instruction
    input  [31:0] PrBTA_E,
    output        Mispredict_E
);

    localparam N     = 1 << IDX_BITS ;
    localparam TAG_W = 30 - IDX_BITS ;  // PC[31:IDX_BITS+2]

    reg  [N-1:0]     valid ;
    reg  [TAG_W-1:0] tag    [0:N-1] ;
    reg  [29:0]      target [0:N-1] ;   // target[31:2]; instructions are word aligned
    reg  [1:0]       ctr    [0:N-1] ;

    integer k ;
    initial begin
        valid = {N{1'b0}} ;
        for (k = 0; k < N; k = k + 1) begin
            tag[k]    = {TAG_W{1'b0}} ;
            target[k] = 30'd0 ;
            ctr[k]    = 2'b00 ;
        end
    end

    // ================= F: lookup =================
    wire [IDX_BITS-1:0] idx_F = PC_F[IDX_BITS+1:2] ;
    wire                hit_F = valid[idx_F] && (tag[idx_F] == PC_F[31:IDX_BITS+2]) ;

    assign PrTaken_F = Enable && hit_F && ctr[idx_F][1] ;
    assign PrBTA_F   = {target[idx_F], 2'b00} ;

    // ================= E: check =================
    // Predicted taken:     F fetched PrBTA_E. Wrong if the branch was not taken, or went elsewhere
    //                      (e.g. a jalr returning to a different caller).
    // Predicted not taken: F fetched PC_E + 4. Wrong if the branch was taken.
    assign Mispredict_E = PrTaken_E ? (~Taken_E | (PrBTA_E != Target_E)) : Taken_E ;

    // ================= E: update =================
    // Second read port at PC_E, so the update uses the entry as it is now
    // (an older instance of the same branch may have changed it since F read it).
    wire [IDX_BITS-1:0] idx_E = PC_E[IDX_BITS+1:2] ;
    wire                hit_E = valid[idx_E] && (tag[idx_E] == PC_E[31:IDX_BITS+2]) ;

    always @(posedge CLK) begin
        if (RESET)
            valid <= {N{1'b0}} ;
        else if (~Stall_E) begin
            if (IsBranch_E) begin
                if (hit_E) begin
                    // saturating counter
                    if (Taken_E && ctr[idx_E] != 2'b11)
                        ctr[idx_E] <= ctr[idx_E] + 2'b01 ;
                    else if (~Taken_E && ctr[idx_E] != 2'b00)
                        ctr[idx_E] <= ctr[idx_E] - 2'b01 ;
                    if (Taken_E)
                        target[idx_E] <= Target_E[31:2] ;
                end
                else if (Taken_E) begin
                    // allocate (replaces whatever was at this index)
                    valid[idx_E]  <= 1'b1 ;
                    tag[idx_E]    <= PC_E[31:IDX_BITS+2] ;
                    target[idx_E] <= Target_E[31:2] ;
                    ctr[idx_E]    <= 2'b10 ;
                end
            end
            else if (PrTaken_E && hit_E)
                // A non-branch was predicted taken. Cannot happen with a fixed program
                // and full tags, but drop the entry if it ever does.
                valid[idx_E] <= 1'b0 ;
        end
    end

endmodule
