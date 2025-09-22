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
  //assign calc_if.loc_sel = my_calc.loc_sel;
  `endif
  `ifdef CADENCE
  assign calc_if.calc.wr_en = my_calc.write;
  assign calc_if.calc.rd_en = my_calc.read;
  assign calc_if.calc.wr_data = my_calc.w_data;
  assign calc_if.calc.rd_data = my_calc.r_data;
  assign calc_if.calc.ready = my_calc.u_ctrl.state == S_END;
  assign calc_if.calc.curr_rd_addr = my_calc.r_addr;
  assign calc_if.calc.curr_wr_addr = my_calc.w_addr;
  //assign calc_if.calc.loc_sel = my_calc.loc_sel;
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
      // Run driver in background to consume sequencer mailbox
      calc_driver_h.drive();
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
    logic [DataSize-1:0] read_lo, read_hi;
    read_lo = my_calc.sram_A.mem[tb_test_addr];
    read_hi = my_calc.sram_B.mem[tb_test_addr];

  $display("Directed result: SRAM A (lower 32): 0x%0x, SRAM B (upper 32): 0x%0x", read_lo, read_hi);
  $display("Expected (32-bit sum): 0x%0x", tb_expected);

  // TODO: Finish test case 1 (additional directed cases can be added here)

    // Test case 2 - addition with overflow (top-half overflow)
    $display("Test case 2 - addition with overflow (top-half)");

    // We'll use two consecutive read addresses so the controller will place the
    // first addition into the lower 32 bits of the buffer and the second into the upper 32 bits.
    logic [AddrSize-1:0] addr0, addr1, write_addr;
    logic [DataSize-1:0] a0, b0, a1, b1;
    logic [DataSize-1:0] expected_lo, expected_hi;

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
    logic [DataSize-1:0] got_lo, got_hi;
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
    calc_driver_h.start_calc(tb_test_addr, tb_test_addr, tb_test_addr, tb
_test_addr, 1);
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

    // TODO: Add test cases according to your test plan. If you need additional test cases to reach
    // 96% coverage, make sure to add them to your test plan

    // Random part
    $display("Randomized Testing");
    // TODO: Finish randomized testing
    // HINT: The sequencer is responsible for generating random input sequences. How can the
    // sequencer and driver be combined to generate multiple randomized test cases?

    repeat (100) @(posedge clk);

    $display("TEST PASSED");
    $finish;
  end

  /********************
        ASSERTIONS
  *********************/

  // TODO: Add Assertions
//  RESET: ;
//  VALID_INPUT_ADDRESS: ;
//  BUFFER_LOC_TOGGLES: ;
endmodule
