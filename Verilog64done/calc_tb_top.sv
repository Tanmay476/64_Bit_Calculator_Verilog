module calc_tb_top;

  import calc_tb_pkg::*;
  import calculator_pkg::*;

  parameter int DataSize = DATA_W;
  parameter int AddrSize = ADDR_W;
  logic clk = 0;
  // Local signals for directed tests
  logic [AddrSize-1:0] tb_test_addr;
  logic [DataSize-1:0] tb_a_val, tb_b_val, tb_expected;
  logic rst;
  state_t state;
  logic [DataSize-1:0] rd_data;

  logic [DataSize-1:0] read_lo, read_hi;

    // We'll use two consecutive read addresses so the controller will place the
    // first addition into the lower 32 bits of the buffer and the second into the upper 32 bits.
    logic [AddrSize-1:0] addr0, addr1, write_addr;
    logic [DataSize-1:0] a0, b0, a1, b1;
    logic [DataSize-1:0] expected_lo, expected_hi;

    logic [DataSize-1:0] got_lo, got_hi;
    logic [AddrSize-1:0] a, a1, a2;
    int NUM_RANDOM;


  calc_if #(.DataSize(DataSize), .AddrSize(AddrSize)) calc_if(.clk(clk));
  top_lvl my_calc(
    .clk(clk),
    .rst(calc_if.reset),
    `ifdef VCS
    .read_start_addr(calc_if.read_start_addr),
    .read_end_addr(calc_if.read_end_addr),
    .write_start_addr(calc_if.write_start_addr),
    .write_end_addr(calc_if.write_end_addr)
    `endif
    `ifdef CADENCE
    .read_start_addr(calc_if.calc.read_start_addr),
    .read_end_addr(calc_if.calc.read_end_addr),
    .write_start_addr(calc_if.calc.write_start_addr),
    .write_end_addr(calc_if.calc.write_end_addr)
    `endif
  );

  assign rst = calc_if.reset;
  assign state = my_calc.u_ctrl.state;
  `ifdef VCS
  assign calc_if.wr_en = my_calc.write;
  assign calc_if.rd_en = my_calc.read;
  assign calc_if.wr_data = my_calc.w_data;
  assign calc_if.rd_data = my_calc.r_data;
  assign calc_if.ready = my_calc.u_ctrl.state == S_END;
  assign calc_if.curr_rd_addr = my_calc.r_addr;
  assign calc_if.curr_wr_addr = my_calc.w_addr;
  assign calc_if.loc_sel = my_calc.buffer_control;
  `endif
  `ifdef CADENCE
  assign calc_if.calc.wr_en = my_calc.write;
  assign calc_if.calc.rd_en = my_calc.read;
  assign calc_if.calc.wr_data = my_calc.w_data;
  assign calc_if.calc.rd_data = my_calc.r_data;
  assign calc_if.calc.ready = my_calc.u_ctrl.state == S_END;
  assign calc_if.calc.curr_rd_addr = my_calc.r_addr;
  assign calc_if.calc.curr_wr_addr = my_calc.w_addr;
  assign calc_if.calc.loc_sel = my_calc.buffer_control;
  `endif

  calc_tb_pkg::calc_driver #(.DataSize(DataSize), .AddrSize(AddrSize)) calc_driver_h;
  calc_tb_pkg::calc_sequencer #(.DataSize(DataSize), .AddrSize(AddrSize)) calc_sequencer_h;
  calc_tb_pkg::calc_monitor #(.DataSize(DataSize), .AddrSize(AddrSize)) calc_monitor_h;
  calc_tb_pkg::calc_sb #(.DataSize(DataSize), .AddrSize(AddrSize)) calc_sb_h;

  always #5 clk = ~clk;

  task write_sram(input [AddrSize-1:0] addr, input [DataSize-1:0] data, input logic block_sel);
    @(posedge clk);
    if (!block_sel) begin
      my_calc.sram_A.mem[addr] = data;
    end
    else begin
      my_calc.sram_B.mem[addr] = data;
    end
    calc_driver_h.initialize_sram(addr, data, block_sel);
  endtask

  // Task that starts a background calculation and pulses reset when the controller
  // reaches a specific state, mainly to increase fsm coverage in verdi
  task automatic reset_when_state(input state_t target,
                                  input [AddrSize-1:0] read_s,
                                  input [AddrSize-1:0] read_e,
                                  input [AddrSize-1:0] write_s,
                                  input [AddrSize-1:0] write_e);
    int timeout;
    begin
      // Launch the calc in background so this task can wait for the requested state
      fork
        begin
          calc_driver_h.start_calc(read_s, read_e, write_s, write_e, 1);
        end
      join_none

      timeout = 1000;
      // wait for the DUT to reach the desired state or timeout
      while ((state !== target) && (timeout > 0)) begin
        @(posedge clk);
        timeout -= 1;
      end
      if (timeout == 0) begin
        $display("RESET_WHEN_STATE: timed out waiting for state %0d (current=%0d)", target, state);
      end else begin
        $display("RESET_WHEN_STATE: reached state %0d at time %0t; pulsing reset", target, $time);
        calc_driver_h.reset_task(); // pulse re\set via clocking block
        // allow some cycles to settle
        repeat (3) @(posedge clk);
      end
    end
  endtask

  // Helper task: start a background calculation and pulse reset when the controller
  // reaches the specified `target` state. Includes a timeout to avoid hangs.

  initial begin
    `ifdef VCS
    $fsdbDumpon;
    $fsdbDumpfile("simulation.fsdb");
    $fsdbDumpvars(0, calc_tb_top, "+mda", "+all", "+trace_process");
    $fsdbDumpMDA;
    `endif
    `ifdef CADENCE
    $shm_open("waves.shm");
    $shm_probe("AC");
    `endif

    calc_monitor_h = new(calc_if);
    calc_sb_h = new(calc_monitor_h.mon_box);
    calc_sequencer_h = new();
    calc_driver_h = new(calc_if, calc_sequencer_h.calc_box);
    fork
      calc_monitor_h.main();
      calc_sb_h.main();
    join_none
    calc_if.reset <= 1;
    for (int i = 0; i < 2 ** AddrSize; i++) begin
      write_sram(i, $random, 0);
      write_sram(i, $random, 1);
    end

  repeat (100) @(posedge clk);

  // Directed part
  $display("Directed Testing");
  $display("Test case 1 - normal addition");
  // TODO: Finish test case 1 (additional directed cases can be added here)

  // Choose an address and operand values
    tb_test_addr = 'h10;
    tb_a_val = 32'h0000_000A; // 10
    tb_b_val = 32'h0000_0014; // 20
    tb_expected = tb_a_val + tb_b_val;

    // Initialize SRAM A (lower) and SRAM B (upper) at test address
    write_sram(tb_test_addr, tb_a_val, 0);
    write_sram(tb_test_addr, tb_b_val, 1);

    // Small delay
    @(posedge clk);

  // Use driver API to start a single-address calculation so monitor/scoreboard see transactions
  $display("Starting directed normal-add test via driver at addr 0x%0x: %0d + %0d", tb_test_addr, tb_a_val, tb_b_val);
  // call start_calc in direct mode (direct=1)
  calc_driver_h.start_calc(tb_test_addr, tb_test_addr, tb_test_addr, tb_test_addr, 1);

  // Wait until controller reaches end state (driver.start_calc already waits for ready, but keep this to be safe)
  wait (state == S_END);
  @(posedge clk);

    // Read back SRAM contents from DUT memory arrays
    read_lo = my_calc.sram_A.mem[tb_test_addr];
    read_hi = my_calc.sram_B.mem[tb_test_addr];

  $display("Directed result: SRAM A (lower 32): 0x%0x, SRAM B (upper 32): 0x%0x", read_lo, read_hi);
  $display("Expected (32-bit sum): 0x%0x", tb_expected);

    // Test case 2 - addition with overflow (top-half overflow)
    $display("Test case 2 - addition with overflow (top-half)");
    addr0 = 'h20;
    addr1 = 'h21;
    write_addr = 'h30; // where the combined 64-bit result will be written

    // lower-half operands (no overflow)
    a0 = 32'h0000_0005; // 5
    b0 = 32'h0000_0003; // 3
    expected_lo = a0 + b0; // 8

    // upper-half operands (cause 32-bit overflow)
    a1 = 32'hFFFF_FFFF; // 0xFFFFFFFF
    b1 = 32'h0000_0001; // 1
    expected_hi = a1 + b1; // wraps to 0x00000000 in 32-bit arithmetic

    // Initialize SRAM for both read addresses
    write_sram(addr0, a0, 0);
    write_sram(addr0, b0, 1);
    write_sram(addr1, a1, 0);
    write_sram(addr1, b1, 1);

    @(posedge clk);

    // Start calculation over the two read addresses; write back to write_addr
    calc_driver_h.start_calc(addr0, addr1, write_addr, write_addr, 1);
    wait (state == S_END);
    @(posedge clk);

    // Read back the written 64-bit word and check halves
    got_lo = my_calc.sram_A.mem[write_addr];
    got_hi = my_calc.sram_B.mem[write_addr];
    $display("Overflow test result at write addr 0x%0x: lo=0x%0x hi=0x%0x", write_addr, got_lo, got_hi);
    $display("Expected lo=0x%0x hi=0x%0x", expected_lo, expected_hi);

    if (got_lo !== expected_lo) begin
      $error("Overflow test FAILED (lower half mismatch): got 0x%0x expected 0x%0x", got_lo, expected_lo);
      $finish;
    end
    if (got_hi !== expected_hi) begin
      $error("Overflow test FAILED (upper half mismatch): got 0x%0x expected 0x%0x", got_hi, expected_hi);
      $finish;
    end
    $display("Overflow test PASSED: lower and upper halves match expected values");

    //Test Case 3 - 0+0=0
    $display("Test case 3 - 0 + 0 = 0");
    tb_test_addr = 'h12;
    tb_a_val = 32'h0000_0000; // 0
    tb_b_val = 32'h0000_0000; // 0
    tb_expected = tb_a_val + tb_b_val; 

    write_sram(tb_test_addr, tb_a_val, 0);
    write_sram(tb_test_addr, tb_b_val, 1);

    @(posedge clk);
    $display("Starting directed zero-add test via driver at addr 0x%0x: %0d + %0d", tb_test_addr, tb_a_val, tb_b_val);
    calc_driver_h.start_calc(tb_test_addr, tb_test_addr, tb_test_addr, tb_test_addr, 1);
    wait (state == S_END);
    @(posedge clk); 
    read_lo = my_calc.sram_A.mem[tb_test_addr];
    read_hi = my_calc.sram_B.mem[tb_test_addr];
    $display("Zero Directed result: SRAM A (lower 32): 0x%0x, SRAM B (upper 32): 0x%0x", read_lo, read_hi);
    $display("Expected (32-bit sum): 0x%0x", tb_expected);
    if (read_lo !== tb_expected && read_hi !== tb_expected) begin
      $error("Zero test FAILED at addr 0x%0x: got lo=0x%0x hi=0x%0x expected=0x%0x", tb_test_addr, read_lo, read_hi, tb_expected);
      $finish;
    end else begin
      $display("Zero test PASSED: expected 0x%0x found (lo=0x%0x hi=0x%0x)", tb_expected, read_lo, read_hi);
    end

    // Directed FSM coverage tests: exercise read->write and idle->write transitions
    $display("Directed FSM coverage tests: single-read / multi-write and multi-read / single-write");

    // Case A: single read (read_start == read_end) but multi-write (write_start < write_end)
    // This should exercise paths where read range completes quickly and writes continue,
    // exercising the condition (read_addr != read_end_addr) == 0 while (write_addr_next != write_end_addr) == 1
    addr0 = 'h40;
    write_addr = 'h50;
    // initialize single read address
    write_sram(addr0, 32'h1, 0);
    write_sram(addr0, 32'h2, 1);
    // initialize write addresses
    for (int i = 0; i < 3; i++) begin
      write_sram(write_addr + i, $random, 0);
      write_sram(write_addr + i, $random, 1);
    end
    @(posedge clk);
    $display("Starting Case A: single-read %0h multi-write %0h-%0h", addr0, write_addr, write_addr+2);
    calc_driver_h.start_calc(addr0, addr0, write_addr, write_addr+2, 1);
    wait (state == S_END);
    @(posedge clk);

    // Case B: multi-read (read_start < read_end) but single-write (write_start == write_end)
    // This should exercise the inverse condition where reads are still pending when write finishes.
    addr0 = 'h60;
    addr1 = 'h62; // two reads
    write_addr = 'h70;
    // initialize multi-read addresses
    write_sram(addr0, $random, 0);
    write_sram(addr0, $random, 1);
    write_sram(addr1, $random, 0);
    write_sram(addr1, $random, 1);
    // initialize single write address
    write_sram(write_addr, $random, 0);
    write_sram(write_addr, $random, 1);
    @(posedge clk);
    $display("Starting Case B: multi-read %0h-%0h single-write %0h", addr0, addr1, write_addr);
    calc_driver_h.start_calc(addr0, addr1, write_addr, write_addr, 1);
    wait (state == S_END);
    @(posedge clk);

    // Toggle stress: exercise address bit toggles and buffer loc_sel transitions
    $display("Toggle stress: exercising address and loc_sel toggles");
    // Choose a write base that is unlikely to collide with other test addresses
    write_addr = 'h100;
    // declare temporaries once (more simulator-friendly)
    for (int b = 0; b < AddrSize; b++) begin
      // Create a pair of consecutive addresses that toggle one bit using a safe shift
      a  = (1'b1 << b);
      a1 = a;
      a2 = a + 1;

      // Initialize the pair in both SRAMs
      write_sram(a1, $random, 0);
      write_sram(a1, $random, 1);
      write_sram(a2, $random, 0);
      write_sram(a2, $random, 1);

      @(posedge clk);
      // Start a small range read (two addresses) so controller toggles buffer_half internally
      calc_driver_h.start_calc(a1, a2, write_addr, write_addr, 1);
      wait (state == S_END);
      @(posedge clk);
      write_addr++;
    end

  // Add a few conservative, explicit directed tests (no SVA, no loops)
  // These are written plainly to avoid simulator dialect issues.

  // Manual Test A - consecutive back-to-back starts (explicit sequential calls)
  // Reset-the-calc-at-each-state directed tests (run automatically)
  $display("RESET_AT_STATES: pulse reset while in S_IDLE");
  reset_when_state(S_IDLE, 'h00, 'h00, 'h10, 'h10);
  $display("RESET_AT_STATES: pulse reset while in S_READ");
  reset_when_state(S_READ, 'h20, 'h24, 'h30, 'h30);
  $display("RESET_AT_STATES: pulse reset while in S_ADD");
  reset_when_state(S_ADD, 'h40, 'h41, 'h50, 'h50);
  $display("RESET_AT_STATES: pulse reset while in S_WRITE");
  reset_when_state(S_WRITE, 'h60, 'h62, 'h70, 'h72);
  $display("RESET_AT_STATES: pulse reset while in S_END");
  reset_when_state(S_END, 'h80, 'h80, 'h90, 'h90);

  // Random part
  $display("Randomized Testing");
  // TODO: Finish randomized testing
  // HINT: The sequencer is responsible for generating random input sequences. How can the
  // sequencer and driver be combined to generate multiple randomized test cases?
  // Generate a batch of randomized transactions with the sequencer, then have the
  // driver consume them. The current driver implementation uses a non-blocking
  // try_get() loop, so we populate the mailbox first and then call drive().
  NUM_RANDOM = 200; // adjust as needed for thoroughness
  $display("Generating %0d random transactions via sequencer...", NUM_RANDOM);
  calc_sequencer_h.gen(NUM_RANDOM);
  $display("Starting driver to consume randomized transactions...");
  calc_driver_h.drive();
  $display("Randomized transactions processed.");

  repeat (100) @(posedge clk);

  $display("TEST PASSED");
  $finish;
  end

  /********************
        ASSERTIONS
  *********************/

  // SystemVerilog Assertions (SVA) to catch common protocol bugs early.
  // These are lightweight checks for the interface signals the TB drives/observes.

  // 1) Never assert read and write at the same time (protocol violation)
  assert property (@(posedge clk) disable iff (calc_if.reset) !(calc_if.rd_en && calc_if.wr_en))
    else $error("ASSERTION FAILED at %0t: rd_en and wr_en both asserted", $time);

  // 2) Initialization pulse should be single-cycle (we sample it for one clock in the monitor)
  assert property (@(posedge clk) disable iff (calc_if.reset) (calc_if.initialize |-> ##1 (!calc_if.initialize)))
    else $error("ASSERTION FAILED at %0t: initialize should be a single-cycle pulse", $time);

  // 3) During reset, no read or write should be asserted
  assert property (@(posedge clk) (calc_if.reset |-> (!calc_if.rd_en && !calc_if.wr_en)))
    else $error("ASSERTION FAILED at %0t: rd_en/wr_en asserted during reset", $time);

  // 4) Address ranges: end addresses must be >= start addresses
  assert property (@(posedge clk) disable iff (calc_if.reset) (calc_if.read_end_addr >= calc_if.read_start_addr))
    else $error("ASSERTION FAILED at %0t: read_end_addr < read_start_addr (0x%0x < 0x%0x)", $time, calc_if.read_end_addr, calc_if.read_start_addr);

  assert property (@(posedge clk) disable iff (calc_if.reset) (calc_if.write_end_addr >= calc_if.write_start_addr))
    else $error("ASSERTION FAILED at %0t: write_end_addr < write_start_addr (0x%0x < 0x%0x)", $time, calc_if.write_end_addr, calc_if.write_start_addr);

  // 5) Ready signal should imply controller is in S_END (sanity check)
  assert property (@(posedge clk) disable iff (calc_if.reset) (calc_if.ready |-> (state == S_END)))
    else $error("ASSERTION FAILED at %0t: ready asserted while state != S_END (state=%0d)", $time, state);

// Coverage properties to capture important FSM transitions directly
cover property (@(posedge clk) (state == S_READ ##1 state == S_WRITE));
cover property (@(posedge clk) (state == S_IDLE ##1 state == S_WRITE));

endmodule
