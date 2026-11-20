`timescale 1ns / 1ps
// Unit testbench for BranchPredictor.v. Self-checking: prints FAIL lines and a summary.
// Uses a 4-entry table (IDX_BITS = 2) so aliasing is easy to test.
// Each step drives one resolved instruction into the E-side ports, checks Mispredict_E,
// clocks the update in, then checks what F would predict for some PC.

module test_BranchPredictor();

    reg CLK = 0, RESET = 1, Enable = 1 ;
    reg  [31:0] PC_F = 0 ;
    wire        PrTaken_F ;
    wire [31:0] PrBTA_F ;
    reg         Stall_E = 0 ;
    reg  [31:0] PC_E = 0 ;
    reg         IsBranch_E = 0, Taken_E = 0, PrTaken_E = 0 ;
    reg  [31:0] Target_E = 0, PrBTA_E = 0 ;
    wire        Mispredict_E ;

    BranchPredictor #(.IDX_BITS(2)) dut(
        .CLK(CLK), .RESET(RESET), .Enable(Enable),
        .PC_F(PC_F), .PrTaken_F(PrTaken_F), .PrBTA_F(PrBTA_F),
        .Stall_E(Stall_E), .PC_E(PC_E), .IsBranch_E(IsBranch_E), .Taken_E(Taken_E),
        .Target_E(Target_E), .PrTaken_E(PrTaken_E), .PrBTA_E(PrBTA_E),
        .Mispredict_E(Mispredict_E)
    );

    always #5 CLK = ~CLK ;

    integer errors = 0, checks = 0 ;

    localparam A = 32'h0040_0010 ;   // index 0
    localparam B = 32'h0040_0020 ;   // index 0 too (4 entries): aliases with A, different tag
    localparam C = 32'h0040_0014 ;   // index 1
    localparam X = 32'h0040_0100 ;
    localparam Y = 32'h0040_0200 ;

    // Drive one instruction in E, check Mispredict_E, then clock the update in.
    task resolve ;
        input [31:0] pc ;
        input        isbr, taken ;
        input [31:0] tgt ;
        input        prt ;
        input [31:0] prbta ;
        input        exp_mis ;
        begin
            @(negedge CLK) ;
            PC_E = pc ; IsBranch_E = isbr ; Taken_E = taken ; Target_E = tgt ;
            PrTaken_E = prt ; PrBTA_E = prbta ;
            #1 ;
            checks = checks + 1 ;
            if (Mispredict_E !== exp_mis) begin
                $display("FAIL [%0t] resolve pc=%h taken=%b pr=%b: Mispredict=%b, expected %b", $time, pc, taken, prt, Mispredict_E, exp_mis) ;
                errors = errors + 1 ;
            end
            @(posedge CLK) ; #1 ;
            IsBranch_E = 0 ; Taken_E = 0 ; PrTaken_E = 0 ;
        end
    endtask

    // Check the F-side prediction for pc.
    task lookup ;
        input [31:0] pc ;
        input        exp_taken ;
        input [31:0] exp_bta ;     // checked only when exp_taken
        begin
            PC_F = pc ; #1 ;
            checks = checks + 1 ;
            if (PrTaken_F !== exp_taken || (exp_taken && PrBTA_F !== exp_bta)) begin
                $display("FAIL [%0t] lookup pc=%h: PrTaken=%b PrBTA=%h, expected %b %h", $time, pc, PrTaken_F, PrBTA_F, exp_taken, exp_bta) ;
                errors = errors + 1 ;
            end
        end
    endtask

    initial begin
        #12 RESET = 0 ;

        // 1. empty table: nothing predicted
        lookup(A, 0, 0) ;

        // 2. not-taken branch that misses: predicted right, no entry made
        resolve(A, 1, 0, X, 0, 0, 0) ;
        lookup(A, 0, 0) ;

        // 3. taken branch that misses: mispredict, allocate as weakly taken (10)
        resolve(A, 1, 1, X, 0, 0, 1) ;
        lookup(A, 1, X) ;

        // 4. predicted taken but not taken: mispredict, 10 -> 01, now predicts not taken
        resolve(A, 1, 0, X, 1, X, 1) ;
        lookup(A, 0, 0) ;

        // 5. taken again: 01 -> 10 (taken); taken: 10 -> 11
        resolve(A, 1, 1, X, 0, 0, 1) ;
        lookup(A, 1, X) ;
        resolve(A, 1, 1, X, 1, X, 0) ;     // correct prediction
        lookup(A, 1, X) ;

        // 6. hysteresis: one not-taken from 11 -> 10, still predicts taken
        resolve(A, 1, 0, X, 1, X, 1) ;
        lookup(A, 1, X) ;
        resolve(A, 1, 1, X, 1, X, 0) ;     // back to 11

        // 7. same branch, new target (like jalr returning elsewhere): target mismatch is a mispredict
        resolve(A, 1, 1, Y, 1, X, 1) ;
        lookup(A, 1, Y) ;
        resolve(A, 1, 1, Y, 1, Y, 0) ;

        // 8. an unrelated PC is not predicted (index 1 is empty)
        lookup(C, 0, 0) ;

        // 9. aliasing: B has A's index but a different tag, so it does not hit A's entry
        lookup(B, 0, 0) ;
        resolve(B, 1, 1, X, 0, 0, 1) ;     // B replaces A
        lookup(B, 1, X) ;
        lookup(A, 0, 0) ;

        // 10. Enable = 0: never predicts, every taken branch is a mispredict
        Enable = 0 ;
        lookup(B, 0, 0) ;
        resolve(B, 1, 1, X, 0, 0, 1) ;
        resolve(B, 1, 0, X, 0, 0, 0) ;
        Enable = 1 ;
        lookup(B, 1, X) ;                  // kept training while off: 10 -> 11 -> 10, still taken

        // 11. stall: no update while E is held
        Stall_E = 1 ;
        resolve(C, 1, 1, Y, 0, 0, 1) ;
        Stall_E = 0 ;
        lookup(C, 0, 0) ;

        // 12. counter saturates at 00: from 10 -> 01 -> 00 -> 00, then one taken -> 01 (still not taken)
        resolve(B, 1, 0, X, 1, X, 1) ;     // 10 -> 01
        resolve(B, 1, 0, X, 0, 0, 0) ;     // 01 -> 00
        resolve(B, 1, 0, X, 0, 0, 0) ;     // stays 00
        resolve(B, 1, 1, X, 0, 0, 1) ;     // 00 -> 01
        lookup(B, 0, 0) ;
        resolve(B, 1, 1, X, 0, 0, 1) ;     // 01 -> 10
        lookup(B, 1, X) ;

        // 13. a non-branch predicted taken: mispredict, and its entry is dropped
        resolve(B, 0, 0, 0, 1, X, 1) ;
        lookup(B, 0, 0) ;

        // 14. reset clears the table
        resolve(C, 1, 1, Y, 0, 0, 1) ;
        lookup(C, 1, Y) ;
        RESET = 1 ; @(posedge CLK) ; #1 RESET = 0 ;
        lookup(C, 0, 0) ;

        $display("test_BranchPredictor: %0d checks, %0d errors", checks, errors) ;
        if (errors == 0) $display("*** ALL TESTS PASSED! ***") ;
        $finish ;
    end

endmodule
