class calc_driver #(int DataSize, int AddrSize);

  mailbox #(calc_seq_item #(DataSize, AddrSize)) drv_box;

  virtual interface calc_if #(.DataSize(DataSize), .AddrSize(AddrSize)) calcVif;

  function new(virtual interface calc_if #(DataSize, AddrSize) calcVif,
      mailbox #(calc_seq_item #(DataSize, AddrSize)) drv_box);
    this.calcVif = calcVif;
    this.drv_box = drv_box;
  endfunction

  int timeout_cycles = 200;
  int t;
  int quiet_count = 0;
  int quiet_count2 = 0;

  task reset_task();
    // Apply an active-high reset pulse to the DUT using the interface clocking block.
    // Before asserting reset, wait for any active read/write strobes to deassert
    // to avoid protocol violations and partial transactions being observed by the
    // scoreboard. Use a timeout to avoid hanging if the DUT never quiesces.
    @(calcVif.cb);
    // wait until rd_en and wr_en are both low for two consecutive clocking samples or timeout
    t = timeout_cycles;
    quiet_count = 0;
    while ((quiet_count < 2) && (t > 0)) begin
      @(calcVif.cb);
      if (!(calcVif.cb.rd_en || calcVif.cb.wr_en)) begin
        quiet_count += 1; // one more quiet cycle observed
      end else begin
        quiet_count = 0; // activity seen, reset consecutive quiet counter
      end
      t -= 1;
    end
    if (quiet_count < 2) begin
      $display("%0t Drv: reset_task timed out waiting for two quiet cycles (rd/wr); proceeding to assert reset", $time);
    end
    // Assert reset so controller latches start/write addresses into internal pointers
    calcVif.cb.reset <= 1;
    // keep reset asserted for a couple cycles
    repeat (2) @(calcVif.cb);
    calcVif.cb.reset <= 0;
    @(calcVif.cb);
  endtask

  virtual task initialize_sram(input [AddrSize-1:0] addr, input [DataSize-1:0] data, input logic block_sel);
    // Drive the initialization signals so the monitor can capture an initialization transaction.
    @(calcVif.cb);
    calcVif.cb.initialize <= 1;
    calcVif.cb.initialize_addr <= addr;
    calcVif.cb.initialize_data <= data;
    calcVif.cb.initialize_loc_sel <= block_sel;
    $display($stime, "Drv: initialize_sram: SRAM %s addr=0x%0x data=0x%0x", !block_sel ? "A" : "B", addr, data);
    // sample for one clock to ensure monitor sees it
    @(calcVif.cb);
    calcVif.cb.initialize <= 0;
    @(calcVif.cb);
  endtask : initialize_sram

  virtual task automatic start_calc(input logic [AddrSize-1:0] read_start_addr, input logic [AddrSize-1:0] read_end_addr,
    input logic [AddrSize-1:0] write_start_addr, input logic [AddrSize-1:0] write_end_addr,
    input bit direct = 1);

    int delay;
    calc_seq_item #(DataSize, AddrSize) trans;
  // Drive the calculation parameters into the DUT via the clocking block.
  @(calcVif.cb);
  calcVif.cb.read_start_addr  <= read_start_addr;
  calcVif.cb.read_end_addr    <= read_end_addr;
  calcVif.cb.write_start_addr <= write_start_addr;
  calcVif.cb.write_end_addr   <= write_end_addr;
  $display($stime, "Drv: start_calc: read_start=0x%0x read_end=0x%0x write_start=0x%0x write_end=0x%0x direct=%0d", read_start_addr, read_end_addr, write_start_addr, write_end_addr, direct);
  // Drive addresses on one clocking tick, then assert reset on the following tick so
  // the controller reliably latches the provided start/write addresses.
  @(calcVif.cb);
  // Before asserting reset, ensure there are no active read/write strobes.
  // This avoids asserting reset in the middle of a transfer which violates
  // the TB's reset-time protocol SVA and can create partial pairs in the
  // scoreboard. Use a timeout to avoid deadlocking if the DUT never quiesces.
  t = timeout_cycles;
  // wait until rd_en and wr_en are both low for two consecutive clocking samples or timeout
  while ((quiet_count2 < 2) && (t > 0)) begin
    @(calcVif.cb);
    if (!(calcVif.cb.rd_en || calcVif.cb.wr_en)) begin
      quiet_count2 += 1;
    end else begin
      quiet_count2 = 0;
    end
    t -= 1;
  end
  if (quiet_count2 < 2) begin
    $display("%0t Drv: start_calc timed out waiting for two quiet cycles (rd/wr); asserting reset anyway", $time);
  end
  // Assert reset so controller latches start/write addresses into internal pointers
  calcVif.cb.reset <= 1;
  @(calcVif.cb);
  calcVif.cb.reset <= 0;
  @(calcVif.cb);

  // Now wait until DUT indicates it's finished (ready asserted when controller in S_END)
  @(calcVif.cb iff calcVif.cb.ready);

    if (!direct) begin // Random Mode
      if (drv_box.try_peek(trans)) begin
        delay = $urandom_range(0, 5); // Add a Random delay before the next transaction
        repeat (delay) begin
          @(calcVif.cb);
        end
      end
    end
    // leave reset deasserted; controller will progress
  endtask : start_calc

  virtual task drive();
    calc_seq_item #(DataSize, AddrSize) trans;
    while (drv_box.try_get(trans)) begin
      start_calc(trans.read_start_addr, trans.read_end_addr, trans.write_start_addr, trans.write_end_addr, 0);
    end
  endtask : drive

endclass : calc_driver
