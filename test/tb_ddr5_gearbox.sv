// =============================================================================
// Testbench: tb_ddr5_gearbox
// Description: B-01 / TC-07 verification of the 256<->128 bit-width gearbox.
//   Confirms the 2:1 data-width ratio (2 DFI cycles per 1 user cycle) and the
//   phase split documented in docs/03_DDR5_PHY_Digital.md:
//     Write: PHASE_0 -> USER_DATA[127:0],  PHASE_1 -> USER_DATA[255:128]
//     Read : {DFI_beat1, DFI_beat0} -> USER_DATA[255:0]
//   Also checks back-pressure data stability and lossless 4-word streaming.
//
// 时序约定 (重要, 首版跑测失败后修正):
//   1) 时钟周期 2.0ns -> posedge 落在奇数 ns。检查点一律用 `#TCHK`(0.4ns)
//      而非 `#1`, 否则 `@(posedge clk); #1;` 会停在下一个 posedge 的同一时刻,
//      与 always_ff 产生竞争 (读到的是相位更新前的旧值)。
//   2) 握手/吞吐计数必须在 negedge 采样 (反映"下一个 posedge 将发生的握手");
//      在 posedge 之后采样会读到相位更新后的状态, 导致漏计/错序。
// =============================================================================
`timescale 1ns/1ps

module tb_ddr5_gearbox();

    localparam int  USER_W = 256;
    localparam int  DFI_W  = 128;
    localparam real CLK_PERIOD = 2.0;   // DFI domain 1.2 GHz scaled
    localparam real TCHK = 0.4;         // 检查点偏移, 远离 posedge 避免竞争

    // 128-bit patterns (fully filled, no truncation)
    localparam logic [DFI_W-1:0]  PAT_LO  = {4{32'h5555_5555}};
    localparam logic [DFI_W-1:0]  PAT_HI  = {4{32'hAAAA_AAAA}};
    localparam logic [USER_W-1:0] PAT_256 = {PAT_HI, PAT_LO};

    logic clk = 0, rst_n;

    logic              wr_user_valid, wr_user_ready;
    logic [USER_W-1:0] wr_user_data;
    logic              wr_dfi_valid, wr_dfi_ready;
    logic [DFI_W-1:0]  wr_dfi_data;

    logic              rd_dfi_valid, rd_dfi_ready;
    logic [DFI_W-1:0]  rd_dfi_data;
    logic              rd_user_valid, rd_user_ready;
    logic [USER_W-1:0] rd_user_data;

    // ---- 检查点/计数变量 (模块级声明: 禁止在 initial 内声明) --------------
    logic [USER_W-1:0] exp_q [0:3];     // expected user words
    logic [DFI_W-1:0]  cap_q [0:7];     // captured DFI beats
    int  dfi_beats, user_beats;         // T9 counters
    int  uc, ec, li;                    // T10 counters / loop index
    int  ci;                            // T10 采集线程迭代上限计数
    bit  wdone;                         // T10 per-word done flag

    ddr5_gearbox #(.USER_W(USER_W), .DFI_W(DFI_W)) dut (
        .clk(clk), .rst_n(rst_n),
        .wr_user_valid(wr_user_valid), .wr_user_data(wr_user_data),
        .wr_user_ready(wr_user_ready),
        .wr_dfi_valid(wr_dfi_valid), .wr_dfi_data(wr_dfi_data),
        .wr_dfi_ready(wr_dfi_ready),
        .rd_dfi_valid(rd_dfi_valid), .rd_dfi_data(rd_dfi_data),
        .rd_dfi_ready(rd_dfi_ready),
        .rd_user_valid(rd_user_valid), .rd_user_data(rd_user_data),
        .rd_user_ready(rd_user_ready)
    );

    initial forever #(CLK_PERIOD/2) clk = ~clk;

    int pass_cnt = 0, fail_cnt = 0;
    task automatic chk(string name, bit cond);
        if (cond) begin $display("[PASS] %s", name); pass_cnt++; end
        else      begin $display("[FAIL] %s", name); fail_cnt++; end
    endtask

    initial begin
        rst_n=0;
        wr_user_valid=0; wr_user_data='0; wr_dfi_ready=1;
        rd_dfi_valid=0;  rd_dfi_data='0;  rd_user_ready=1;
        dfi_beats=0; user_beats=0; uc=0; ec=0; li=0; wdone=0;
        repeat(3) @(posedge clk); rst_n=1; @(posedge clk); #TCHK;

        // ---- T1: reset state ----
        chk("T1 reset: user ready (PHASE_0)",  wr_user_ready === 1'b1);
        chk("T1 reset: dfi not valid",         wr_dfi_valid  === 1'b0);
        chk("T1 reset: rd dfi ready",          rd_dfi_ready  === 1'b1);
        chk("T1 reset: rd user not valid",     rd_user_valid === 1'b0);

        // ---- T2: write PHASE_0 presents LOW half on DFI ----
        wr_user_valid = 1'b1;
        wr_user_data  = PAT_256;
        #TCHK;
        chk("T2 PHASE_0: dfi valid",           wr_dfi_valid  === 1'b1);
        chk("T2 PHASE_0: dfi_data == LO",      wr_dfi_data   === PAT_LO);
        chk("T2 PHASE_0: user ready",          wr_user_ready === 1'b1);

        // ---- T3: after user handshake -> PHASE_1 presents HIGH half ----
        @(posedge clk); #TCHK;
        chk("T3 PHASE_1: dfi valid",           wr_dfi_valid  === 1'b1);
        chk("T3 PHASE_1: dfi_data == HI",      wr_dfi_data   === PAT_HI);
        chk("T3 PHASE_1: user back-pressured", wr_user_ready === 1'b0);

        // ---- T4: DFI back-pressure holds data stable ----
        wr_dfi_ready = 1'b0;
        repeat(4) @(posedge clk); #TCHK;
        chk("T4 stall: dfi_data stable (HI)",  wr_dfi_data  === PAT_HI);
        chk("T4 stall: dfi_valid held",        wr_dfi_valid === 1'b1);

        // ---- T5: accept PHASE_1 -> return to PHASE_0 ----
        wr_dfi_ready = 1'b1;
        @(posedge clk); #TCHK;
        chk("T5 done: back to PHASE_0",        wr_user_ready === 1'b1);
        wr_user_valid = 1'b0;
        @(posedge clk); #TCHK;

        // ---- T6: read PHASE_0 captures beat0, then back-pressures DFI ----
        rd_dfi_valid = 1'b1;
        rd_dfi_data  = PAT_LO;
        @(posedge clk); #TCHK;                // beat0 consumed -> PHASE_1
        chk("T6 rd PHASE_1: dfi back-pressured", rd_dfi_ready === 1'b0);

        // ---- T7: read PHASE_1 presents the full 256-bit word ----
        rd_dfi_data = PAT_HI;                 // beat1, valid held
        #TCHK;
        chk("T7 rd: user valid",                rd_user_valid === 1'b1);
        chk("T7 rd: user_data == {HI,LO}",      rd_user_data  === PAT_256);

        // ---- T8: accept -> back to PHASE_0 ----
        @(posedge clk); #TCHK;
        chk("T8 rd: back to PHASE_0",           rd_dfi_ready === 1'b1);
        rd_dfi_valid = 1'b0;
        @(posedge clk); #TCHK;

        // ---- T9: throughput ratio = 2 DFI beats per 1 user beat ----
        //  negedge 采样: 反映下一个 posedge 将发生的握手
        wr_user_valid = 1'b1; wr_user_data = PAT_256; wr_dfi_ready = 1'b1;
        dfi_beats = 0; user_beats = 0;
        for (li = 0; li < 8; li++) begin
            @(negedge clk);
            if (wr_dfi_valid  && wr_dfi_ready)  dfi_beats  = dfi_beats  + 1;
            if (wr_user_valid && wr_user_ready) user_beats = user_beats + 1;
        end
        $display("     T9 detail: dfi_beats=%0d user_beats=%0d", dfi_beats, user_beats);
        chk("T9 ratio 2:1 (dfi == 2*user)", (dfi_beats == 2*user_beats)
                                            && (user_beats >= 2));
        wr_user_valid = 1'b0;
        @(posedge clk); #TCHK;

        // ---- T10: lossless 4-word stream -> 8 DFI beats, correct order ----
        //  驱动线程与采集线程解耦 (fork): 上一版把采集写在驱动 while 内部,
        //  第 4 个 word 的 HIGH 半拍在驱动退出后才出现在总线上, 导致只采到 7 拍。
        exp_q[0] = {64'h0000_0000_0000_0000, 64'h1111_2222_3333_4444};
        exp_q[1] = {64'hFEDC_BA98_7654_3210, 64'h0123_4567_89AB_CDEF};
        exp_q[2] = PAT_256;
        exp_q[3] = {PAT_LO, PAT_HI};
        uc = 0; ec = 0;
        wr_dfi_ready = 1'b1;
        // 确认写通道已回到 PHASE_0 (user_ready=1 等价 PHASE_0)
        li = 0;
        while (!wr_user_ready && li < 6) begin @(posedge clk); li = li + 1; end

        fork
            // 采集线程: 独立抓满 8 个 DFI beat (带迭代上限, 防死等)
            begin
                ci = 0;
                while (ec < 8 && ci < 40) begin
                    @(negedge clk);
                    ci = ci + 1;
                    if (wr_dfi_valid && wr_dfi_ready) begin
                        cap_q[ec] = wr_dfi_data;
                        ec = ec + 1;
                    end
                end
            end
            // 驱动线程: 连续灌 4 个 256-bit word
            //  注意: user 握手后必须再推迟一个 negedge 才能换 wr_user_data,
            //  否则与采集线程在同一 negedge 上竞争 (采集线程会读到下一 word 的 LO)。
            //  推迟到 PHASE_1 的 negedge 换数是安全的: 此时 dfi_data 来自寄存器
            //  wr_data_hi, 不受 wr_user_data 影响。
            begin
                for (li = 0; li < 4; li++) begin
                    wr_user_valid = 1'b1;
                    wr_user_data  = exp_q[li];
                    wdone = 0;
                    while (!wdone) begin
                        @(negedge clk);
                        if (wr_user_valid && wr_user_ready) begin
                            uc = uc + 1;
                            wdone = 1;
                        end
                    end
                    @(negedge clk);   // 等过 PHASE_1 的采集拍再换数据
                end
                wr_user_valid = 1'b0;
            end
        join
        @(posedge clk); #TCHK;
        $display("     T10 detail: user_beats=%0d dfi_beats=%0d", uc, ec);
        chk("T10 4 words -> 8 DFI beats", (uc == 4) && (ec == 8));
        chk("T10 word0 lo/hi", (cap_q[0] === exp_q[0][DFI_W-1:0])
                            && (cap_q[1] === exp_q[0][USER_W-1:DFI_W]));
        chk("T10 word1 lo/hi", (cap_q[2] === exp_q[1][DFI_W-1:0])
                            && (cap_q[3] === exp_q[1][USER_W-1:DFI_W]));
        chk("T10 word2 lo/hi", (cap_q[4] === exp_q[2][DFI_W-1:0])
                            && (cap_q[5] === exp_q[2][USER_W-1:DFI_W]));
        chk("T10 word3 lo/hi", (cap_q[6] === exp_q[3][DFI_W-1:0])
                            && (cap_q[7] === exp_q[3][USER_W-1:DFI_W]));

        $display("\n=== tb_ddr5_gearbox: %0d PASS, %0d FAIL ===", pass_cnt, fail_cnt);
        if (fail_cnt != 0) $display("SOME TESTS FAILED");
        $finish;
    end

    initial begin #(CLK_PERIOD*5000); $display("[ERROR] watchdog timeout"); $finish; end
endmodule
