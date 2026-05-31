`timescale 1ns/1ps

module tb_cycle_accurate;
    import params_pkg::*;

    // =========================================================================
    //  CLOCK, RESET & DUT SIGNALS
    // =========================================================================
    logic aclk = 0;
    logic aresetn;
    always #5 aclk = ~aclk; // 100 MHz -> 10 ns period

    // AXI-Lite
    logic [31:0] s_axi_awaddr;  logic s_axi_awvalid; logic s_axi_awready;
    logic [31:0] s_axi_wdata;   logic s_axi_wvalid;  logic s_axi_wready;
    logic        s_axi_bvalid;  logic s_axi_bready;
    logic [31:0] s_axi_araddr;  logic s_axi_arvalid; logic s_axi_arready;
    logic [31:0] s_axi_rdata;   logic s_axi_rvalid;  logic s_axi_rready;

    // AXI-Stream In
    logic [31:0] s_axis_tdata;  logic s_axis_tvalid;  logic s_axis_tready;

    // AXI-Stream Out
    logic [31:0] m_axis_tdata;  logic m_axis_tvalid;  logic m_axis_tlast;  logic m_axis_tready;

    // =========================================================================
    //  DUT
    // =========================================================================
    ml_accel_top dut (.*);

    // =========================================================================
    //  GLOBAL CYCLE COUNTER  (Starts counting from reset release)
    // =========================================================================
    int unsigned global_cycle;
    logic        counting_en;

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            global_cycle <= 0;
            counting_en  <= 0;
        end else begin
            counting_en <= 1;
            if (counting_en)
                global_cycle <= global_cycle + 1;
        end
    end

    // =========================================================================
    //  INTERNAL DUT PROBES  (White-box -- exactly what FPGA ILA would capture)
    // =========================================================================
    wire [2:0] ctrl_state     = dut.u_ctrl.state;
    wire [2:0] ctrl_next      = dut.u_ctrl.next_state;
    wire [2:0] ctrl_tile_idx  = dut.u_ctrl.tile_idx;
    wire [4:0] ctrl_w_cnt     = dut.u_ctrl.w_cnt;
    wire       ctrl_start     = dut.u_ctrl.start;

    wire       sa_compute_en  = dut.u_sa.compute_en;
    wire       sa_load_pulse  = dut.u_sa.load_pulse;
    wire       sa_output_valid= dut.u_sa.output_valid;

    // State name decoder for display
    function string state_name(input [2:0] s);
        case (s)
            3'd0: return "IDLE";
            3'd1: return "LOAD_L1";
            3'd2: return "COMP_L1";
            3'd3: return "RELU";
            3'd4: return "LOAD_L2";
            3'd5: return "COMP_L2";
            3'd6: return "DONE";
            default: return "???";
        endcase
    endfunction

    // Track whether inference is active (suppress stray prints after DONE)
    logic inference_active;
    always_ff @(posedge aclk) begin
        if (!aresetn)
            inference_active <= 0;
        else if (ctrl_start)
            inference_active <= 1;
        else if (ctrl_state == 3'd6) // DONE
            inference_active <= 0;
    end

    // =========================================================================
    //  BIAS ROM SHADOW  (TB reads the same .mem file for verification)
    // =========================================================================
    logic signed [7:0] tb_bias_rom [0:19];
    initial $readmemh("biases.mem", tb_bias_rom);

    // =========================================================================
    //  STATE TRANSITION MONITOR
    // =========================================================================
    logic [2:0] prev_state;
    int unsigned state_entry_cycle;
    int unsigned phase_cycles;

    // Per-phase accumulators
    int unsigned cyc_axis_in;
    int unsigned cyc_axil_start;
    int unsigned cyc_load_l1_total;
    int unsigned cyc_comp_l1_total;
    int unsigned cyc_relu;
    int unsigned cyc_load_l2_total;
    int unsigned cyc_comp_l2_total;
    int unsigned cyc_done;
    int unsigned cyc_axis_out;

    // Tile-level tracking
    int unsigned load_l1_tiles [0:3];
    int unsigned comp_l1_tiles [0:3];
    int unsigned load_l2_tiles [0:3];
    int unsigned comp_l2_tiles [0:3];
    int unsigned l1_tile_count;
    int unsigned l2_tile_count;

    // AXI overhead markers
    int unsigned cycle_axis_in_start, cycle_axis_in_end;
    int unsigned cycle_axil_start, cycle_axil_end;
    int unsigned cycle_infer_done;
    int unsigned cycle_axis_out_start, cycle_axis_out_end;

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            prev_state <= 3'd0;
            state_entry_cycle <= 0;
            l1_tile_count <= 0;
            l2_tile_count <= 0;
            cyc_load_l1_total <= 0;
            cyc_comp_l1_total <= 0;
            cyc_relu          <= 0;
            cyc_load_l2_total <= 0;
            cyc_comp_l2_total <= 0;
            cyc_done          <= 0;
        end else begin
            prev_state <= ctrl_state;

            if (ctrl_state != prev_state) begin
                phase_cycles = global_cycle - state_entry_cycle;

                if (counting_en) begin
                    case (prev_state)
                        3'd1: begin
                            cyc_load_l1_total <= cyc_load_l1_total + phase_cycles;
                            load_l1_tiles[l1_tile_count] <= phase_cycles;
                            $display("  [Cycle %4d] LOAD_L1  tile %0d complete  -- %0d cycles", global_cycle, l1_tile_count, phase_cycles);
                        end
                        3'd2: begin
                            cyc_comp_l1_total <= cyc_comp_l1_total + phase_cycles;
                            comp_l1_tiles[l1_tile_count] <= phase_cycles;
                            $display("  [Cycle %4d] COMP_L1  tile %0d complete  -- %0d cycles  (output_valid + bias add)", global_cycle, l1_tile_count, phase_cycles);
                            l1_tile_count <= l1_tile_count + 1;
                        end
                        3'd3: begin
                            cyc_relu <= phase_cycles;
                            $display("  [Cycle %4d] RELU     complete           -- %0d cycle(s)", global_cycle, phase_cycles);
                        end
                        3'd4: begin
                            cyc_load_l2_total <= cyc_load_l2_total + phase_cycles;
                            load_l2_tiles[l2_tile_count] <= phase_cycles;
                            $display("  [Cycle %4d] LOAD_L2  tile %0d complete  -- %0d cycles", global_cycle, l2_tile_count, phase_cycles);
                        end
                        3'd5: begin
                            cyc_comp_l2_total <= cyc_comp_l2_total + phase_cycles;
                            comp_l2_tiles[l2_tile_count] <= phase_cycles;
                            $display("  [Cycle %4d] COMP_L2  tile %0d complete  -- %0d cycles  (output_valid + accumulate)", global_cycle, l2_tile_count, phase_cycles);
                            l2_tile_count <= l2_tile_count + 1;
                        end
                        3'd6: begin
                            cyc_done <= phase_cycles;
                            $display("  [Cycle %4d] DONE     complete           -- %0d cycle(s)", global_cycle, phase_cycles);
                        end
                    endcase
                end

                $display("  [Cycle %4d] >>> Entering %s", global_cycle, state_name(ctrl_state));
                state_entry_cycle <= global_cycle;
            end
        end
    end

    // =========================================================================
    //  KEY SIGNAL EVENT MONITORS  (only active during inference)
    // =========================================================================
    always_ff @(posedge aclk) begin
        if (ctrl_start && aresetn)
            $display("  [Cycle %4d] *** start PULSE asserted by AXI-Lite ***", global_cycle);
    end

    always_ff @(posedge aclk) begin
        if (sa_output_valid && aresetn && inference_active)
            $display("  [Cycle %4d]     output_valid HIGH -- psum_out captured (tile %0d)", global_cycle, ctrl_tile_idx);
    end

    // Weight load pulse counter
    int unsigned load_pulse_count;
    always_ff @(posedge aclk) begin
        if (!aresetn)
            load_pulse_count <= 0;
        else if (sa_load_pulse)
            load_pulse_count <= load_pulse_count + 1;
    end

    // =========================================================================
    //  BIAS VALUE MONITOR  (print biases the DUT controller loaded)
    // =========================================================================
    // After COMP_L1 output_valid fires, the DUT adds bias to hid_psum.
    // We print the bias values from TB's shadow copy at start of inference.

    // =========================================================================
    //  AXI TRANSACTION TASKS  (Minimal overhead, protocol-correct)
    // =========================================================================
    task automatic axis_send(input [31:0] data);
        @(posedge aclk);
        s_axis_tdata  <= data;
        s_axis_tvalid <= 1'b1;
        @(posedge aclk);
        s_axis_tvalid <= 1'b0;
        s_axis_tdata  <= 32'h0;
    endtask

    task automatic axil_write(input [31:0] addr, input [31:0] data);
        @(posedge aclk);
        s_axi_awaddr  <= addr;
        s_axi_awvalid <= 1'b1;
        s_axi_wdata   <= data;
        s_axi_wvalid  <= 1'b1;
        s_axi_bready  <= 1'b1;
        @(posedge aclk);
        s_axi_awvalid <= 1'b0;
        s_axi_wvalid  <= 1'b0;
        @(posedge aclk);
        wait (s_axi_bvalid);
        @(posedge aclk);
        s_axi_bready  <= 1'b0;
    endtask

    // =========================================================================
    //  GOLDEN MODEL  (Compute expected result using same int8 math as HW)
    // =========================================================================
    // Test vectors (from train_and_export_fpga.py output)
    //   input[0] = 0xE4 (-28)   input[1] = 0xFE (-2)
    //   input[2] = 0xEA (-22)   input[3] = 0xEB (-21)
    //   Expected class: 0
    localparam logic [31:0] TEST_INPUT_WORD = 32'hEBEAFEE4;
    localparam int          EXPECTED_CLASS  = 0;

    // =========================================================================
    //  MAIN STIMULUS
    // =========================================================================
    logic signed [31:0] captured_logits [0:2];
    int unsigned        axis_out_count;

    initial begin
        aresetn       = 0;
        s_axi_awaddr  = 0;  s_axi_awvalid = 0;
        s_axi_wdata   = 0;  s_axi_wvalid  = 0;  s_axi_bready = 0;
        s_axi_araddr  = 0;  s_axi_arvalid = 0;  s_axi_rready = 0;
        s_axis_tdata  = 0;  s_axis_tvalid = 0;
        m_axis_tready = 0;

        repeat (5) @(posedge aclk);
        aresetn = 1;
        repeat (2) @(posedge aclk);

        $display("");
        $display("============================================================");
        $display("   CYCLE-ACCURATE INFERENCE TESTBENCH  (WITH BIAS)");
        $display("   Clock: 100 MHz (10 ns period)");
        $display("   Systolic Array: %0d x %0d", SA_ROWS, SA_COLS);
        $display("   SA Compute Latency: %0d pipeline stages (ROWS+COLS)", SA_ROWS + SA_COLS);
        $display("   SA FSM COMP Duration: %0d cycles (latency + 1)", SA_ROWS + SA_COLS + 1);
        $display("============================================================");

        // ==================================================================
        //  Print bias values loaded from biases.mem
        // ==================================================================
        $display("");
        $display("--- Bias Values Loaded from biases.mem ---");
        $display("  Layer 1 biases (16 neurons):");
        for (int i = 0; i < 16; i++)
            $display("    bias_L1[%2d] = %4d (0x%02X)", i, tb_bias_rom[i], tb_bias_rom[i][7:0]);
        $display("  Layer 2 biases (3 output classes):");
        for (int i = 0; i < 3; i++)
            $display("    bias_L2[%2d] = %4d (0x%02X)", i, tb_bias_rom[16+i], tb_bias_rom[16+i][7:0]);
        $display("");
        $display("  Bias application method:");
        $display("    L1: psum + sign_extend(bias) added at COMP_L1 output_valid");
        $display("    L2: logit_acc pre-loaded with sign_extend(bias) at start,");
        $display("        then accumulated across 4 tiles during COMP_L2");
        $display("------------------------------------------------------------");

        // ==================================================================
        //  PHASE 1: Send input activations via AXI-Stream
        // ==================================================================
        $display("");
        $display("--- PHASE 1: AXI-Stream Input ---");
        cycle_axis_in_start = global_cycle;
        $display("  [Cycle %4d] Driving AXI-Stream input: 0x%08X", global_cycle, TEST_INPUT_WORD);
        $display("              a0=0x%02X(%0d)  a1=0x%02X(%0d)  a2=0x%02X(%0d)  a3=0x%02X(%0d)",
                 TEST_INPUT_WORD[7:0],   $signed(8'(TEST_INPUT_WORD[7:0])),
                 TEST_INPUT_WORD[15:8],  $signed(8'(TEST_INPUT_WORD[15:8])),
                 TEST_INPUT_WORD[23:16], $signed(8'(TEST_INPUT_WORD[23:16])),
                 TEST_INPUT_WORD[31:24], $signed(8'(TEST_INPUT_WORD[31:24])));
        axis_send(TEST_INPUT_WORD);
        cycle_axis_in_end = global_cycle;
        cyc_axis_in = cycle_axis_in_end - cycle_axis_in_start;
        $display("  [Cycle %4d] AXI-Stream input captured -- %0d cycle(s)", global_cycle, cyc_axis_in);

        // ==================================================================
        //  PHASE 2: Trigger inference via AXI-Lite write
        // ==================================================================
        $display("");
        $display("--- PHASE 2: AXI-Lite Start Trigger ---");
        cycle_axil_start = global_cycle;
        $display("  [Cycle %4d] Initiating AXI-Lite write (addr=0x00, data=0x01)", global_cycle);
        axil_write(32'h0000_0000, 32'h0000_0001);
        cycle_axil_end = global_cycle;
        cyc_axil_start = cycle_axil_end - cycle_axil_start;
        $display("  [Cycle %4d] AXI-Lite write complete (bvalid received) -- %0d cycle(s)", global_cycle, cyc_axil_start);

        // ==================================================================
        //  PHASE 3: Core Inference (TB just waits)
        // ==================================================================
        $display("");
        $display("--- PHASE 3: Core Inference (Controller + Systolic Array) ---");
        $display("  [Cycle %4d] Waiting for infer_done...", global_cycle);
        $display("  [Cycle %4d]   (L2 bias pre-loaded into logit_acc at start)", global_cycle);

        wait (dut.infer_done == 1'b1);
        cycle_infer_done = global_cycle;
        $display("  [Cycle %4d] *** infer_done ASSERTED ***", global_cycle);

        // ==================================================================
        //  Print hidden layer activations after ReLU (white-box probe)
        // ==================================================================
        $display("");
        $display("--- Hidden Layer Activations (after ReLU + Scale + Saturate) ---");
        for (int i = 0; i < HID_FEATURES; i++)
            $display("  hid_acts[%2d] = %4d", i, dut.u_ctrl.hid_acts[i]);

        // ==================================================================
        //  PHASE 4: Capture output logits via AXI-Stream Out
        // ==================================================================
        $display("");
        $display("--- PHASE 4: AXI-Stream Output Capture ---");
        cycle_axis_out_start = global_cycle;
        m_axis_tready <= 1'b1;

        axis_out_count = 0;
        while (axis_out_count < 3) begin
            @(posedge aclk);
            if (m_axis_tvalid && m_axis_tready) begin
                captured_logits[axis_out_count] = $signed(m_axis_tdata);
                $display("  [Cycle %4d] Output logit[%0d] = %0d (0x%08X)%s",
                         global_cycle, axis_out_count,
                         $signed(m_axis_tdata), m_axis_tdata,
                         m_axis_tlast ? "  [TLAST]" : "");
                axis_out_count++;
            end
        end
        m_axis_tready <= 1'b0;
        cycle_axis_out_end = global_cycle;
        cyc_axis_out = cycle_axis_out_end - cycle_axis_out_start;
        $display("  [Cycle %4d] All 3 logits captured -- %0d cycle(s)", global_cycle, cyc_axis_out);

        // ==================================================================
        //  FINAL REPORT
        // ==================================================================
        @(posedge aclk);

        $display("");
        $display("############################################################");
        $display("#              DETAILED CYCLE BREAKDOWN                     #");
        $display("############################################################");
        $display("");
        $display("--------------------------------------------------------------");
        $display("  AXI-Stream Input Transfer         : %4d cycle(s)", cyc_axis_in);
        $display("  AXI-Lite Start Handshake          : %4d cycle(s)", cyc_axil_start);
        $display("--------------------------------------------------------------");
        $display("  LAYER 1 -- Weight Loading");
        for (int t = 0; t < 4; t++)
            $display("    Tile %0d  LOAD_L1               : %4d cycle(s)", t, load_l1_tiles[t]);
        $display("    LOAD_L1 subtotal               : %4d cycle(s)", cyc_load_l1_total);
        $display("  LAYER 1 -- Systolic Compute + Bias Add");
        for (int t = 0; t < 4; t++)
            $display("    Tile %0d  COMP_L1               : %4d cycle(s)", t, comp_l1_tiles[t]);
        $display("    COMP_L1 subtotal               : %4d cycle(s)", cyc_comp_l1_total);
        $display("--------------------------------------------------------------");
        $display("  ReLU + Scale>>%0d + Saturate       : %4d cycle(s)", SHIFT_AMT, cyc_relu);
        $display("--------------------------------------------------------------");
        $display("  LAYER 2 -- Weight Loading");
        for (int t = 0; t < 4; t++)
            $display("    Tile %0d  LOAD_L2               : %4d cycle(s)", t, load_l2_tiles[t]);
        $display("    LOAD_L2 subtotal               : %4d cycle(s)", cyc_load_l2_total);
        $display("  LAYER 2 -- Systolic Compute + Bias Accumulate");
        for (int t = 0; t < 4; t++)
            $display("    Tile %0d  COMP_L2               : %4d cycle(s)", t, comp_l2_tiles[t]);
        $display("    COMP_L2 subtotal               : %4d cycle(s)", cyc_comp_l2_total);
        $display("--------------------------------------------------------------");
        $display("  DONE state                        : %4d cycle(s)", cyc_done);
        $display("  AXI-Stream Output Transfer        : %4d cycle(s)", cyc_axis_out);
        $display("--------------------------------------------------------------");

        begin
            int unsigned total_core = cyc_load_l1_total + cyc_comp_l1_total +
                                      cyc_relu +
                                      cyc_load_l2_total + cyc_comp_l2_total +
                                      cyc_done;
            int unsigned total_axi  = cyc_axis_in + cyc_axil_start + cyc_axis_out;
            int unsigned total_all  = total_core + total_axi;

            $display("");
            $display("  CORE INFERENCE CYCLES             : %4d cycles", total_core);
            $display("  AXI OVERHEAD CYCLES               : %4d cycles", total_axi);
            $display("");
            $display("  ==========================================================");
            $display("  TOTAL END-TO-END CYCLES           : %4d cycles", total_all);
            $display("  TOTAL TIME @ 100 MHz              : %4d ns", total_all * 10);
            $display("  TOTAL TIME                        : %0.2f us", real'(total_all * 10) / 1000.0);
            $display("  ==========================================================");
            $display("  Weight loads delivered             : %4d pulses", load_pulse_count);
            $display("--------------------------------------------------------------");
        end

        // ==================================================================
        //  CLASSIFICATION RESULT & PASS/FAIL
        // ==================================================================
        $display("");
        $display("  Output Logits: [%0d, %0d, %0d]", captured_logits[0], captured_logits[1], captured_logits[2]);

        begin
            int max_val;
            int pred_class;

            max_val = captured_logits[0];
            pred_class = 0;
            if (captured_logits[1] > max_val) begin max_val = captured_logits[1]; pred_class = 1; end
            if (captured_logits[2] > max_val) begin max_val = captured_logits[2]; pred_class = 2; end

            $display("");
            $display("  ┌─────────────────────────────────────────────────────┐");
            $display("  │  Hardware Predicted Class : %0d                       │", pred_class);
            $display("  │  Expected Class           : %0d                       │", EXPECTED_CLASS);
            if (pred_class == EXPECTED_CLASS)
                $display("  │  Result                  : *** PASS ***             │");
            else
                $display("  │  Result                  : *** FAIL ***             │");
            $display("  └─────────────────────────────────────────────────────┘");

            // Detailed bias contribution summary
            $display("");
            $display("  Bias contribution to final logits:");
            $display("    logit[0] includes L2 bias = %0d (addr 16)", $signed(tb_bias_rom[16]));
            $display("    logit[1] includes L2 bias = %0d (addr 17)", $signed(tb_bias_rom[17]));
            $display("    logit[2] includes L2 bias = %0d (addr 18)", $signed(tb_bias_rom[18]));
        end

        $display("");
        $display("############################################################");

        #20;
        $finish;
    end

    // =========================================================================
    //  TIMEOUT WATCHDOG
    // =========================================================================
    initial begin
        #50_000;
        $display("ERROR: Simulation timed out at %0t ns", $time);
        $finish;
    end

endmodule
