// =============================================================================
// Testbench: tb_ddr5_exclusive_monitor
// Description: B-02 verification of the AXI4 exclusive-access monitor
//   - exclusive read establishes a reservation
//   - matching exclusive write is granted (ex_aw_ok=1 -> EXOKAY)
//   - exclusive write without reservation is denied (OKAY)
//   - cross-port snoop clears the reservation
// =============================================================================
`timescale 1ns/1ps

module tb_ddr5_exclusive_monitor();

    parameter int ADDR_W = 34;
    parameter real CLK_PERIOD = 5.0;

    logic clk = 0;
    logic rst_n;
    logic [ADDR_W-1:0] awaddr;
    logic              awlock;
    logic              awvalid;
    logic              awready;
    logic [ADDR_W-1:0] araddr;
    logic              arlock;
    logic              arvalid;
    logic              arready;
    logic              ex_aw_ok;
    logic [ADDR_W-1:0] res_addr;
    logic              res_valid;
    logic              snoop_hit;

    ddr5_exclusive_monitor #(.ADDR_W(ADDR_W)) dut (
        .clk(clk), .rst_n(rst_n),
        .awaddr(awaddr), .awlock(awlock), .awvalid(awvalid), .awready(awready),
        .araddr(araddr), .arlock(arlock), .arvalid(arvalid), .arready(arready),
        .ex_aw_ok(ex_aw_ok), .res_addr(res_addr), .res_valid(res_valid),
        .snoop_hit(snoop_hit)
    );

    initial forever #(CLK_PERIOD/2) clk = ~clk;

    int pass_cnt = 0, fail_cnt = 0;
    task automatic chk(string name, bit cond);
        if (cond) begin $display("[PASS] %s", name); pass_cnt++; end
        else      begin $display("[FAIL] %s", name); fail_cnt++; end
    endtask

    initial begin
        rst_n=0; awaddr='0; awlock=0; awvalid=0; araddr='0; arlock=0; arvalid=0;
        awready=1; arready=1; snoop_hit=0;
        repeat(3) @(posedge clk); rst_n=1; @(posedge clk);

        // ---- Test 1: exclusive read establishes reservation ----
        araddr=34'h1000; arlock=1; arvalid=1; @(posedge clk); arvalid=0; @(posedge clk);
        chk("T1 reservation set after excl read", res_valid && (res_addr==34'h1000));

        // ---- Test 2: matching exclusive write is granted ----
        awaddr=34'h1000; awlock=1; awvalid=1; @(posedge clk);
        chk("T2 excl write granted (EXOKAY)", ex_aw_ok);
        awvalid=0; @(posedge clk);
        chk("T2 reservation cleared after write", !res_valid);

        // ---- Test 3: exclusive write with no reservation is denied ----
        awaddr=34'h2000; awlock=1; awvalid=1; @(posedge clk);
        chk("T3 excl write denied (no reservation)", !ex_aw_ok);
        awvalid=0; @(posedge clk);

        // ---- Test 4: address mismatch is denied ----
        araddr=34'h3000; arlock=1; arvalid=1; @(posedge clk); arvalid=0; @(posedge clk);
        awaddr=34'h3008; awlock=1; awvalid=1; @(posedge clk);
        chk("T4 excl write denied (addr mismatch)", !ex_aw_ok);
        awvalid=0; @(posedge clk);

        // ---- Test 5: snoop from another master clears reservation ----
        araddr=34'h4000; arlock=1; arvalid=1; @(posedge clk); arvalid=0; @(posedge clk);
        chk("T5a reservation set before snoop", res_valid);
        snoop_hit=1; @(posedge clk); snoop_hit=0; @(posedge clk);
        chk("T5b reservation cleared by snoop", !res_valid);

        // ---- Test 6: normal (non-lock) read does NOT establish reservation ----
        araddr=34'h5000; arlock=0; arvalid=1; @(posedge clk); arvalid=0; @(posedge clk);
        chk("T6 normal read does not reserve", !res_valid);

        $display("\n=== tb_ddr5_exclusive_monitor: %0d PASS, %0d FAIL ===", pass_cnt, fail_cnt);
        $finish;
    end

    initial begin #(CLK_PERIOD*500); $display("[ERROR] timeout"); $finish; end
endmodule
