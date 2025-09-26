class calc_sb #(int DataSize, int AddrSize);

  // 4-state mirrors of SRAM contents for read checking
  logic [DataSize-1:0] mem_a [2**AddrSize];
  logic [DataSize-1:0] mem_b [2**AddrSize];

  // Track per-pair expected sums
  bit                  have_lower;  // 0 = expecting first read, 1 = have lower sum
  logic [DataSize-1:0] exp_lo_sum;  // sum from first read
  logic [DataSize-1:0] exp_hi_sum;  // sum from second read

  mailbox #(calc_seq_item #(DataSize, AddrSize)) sb_box;

  function new(mailbox #(calc_seq_item #(DataSize, AddrSize)) sb_box);
    this.sb_box = sb_box;
    have_lower  = 1'b0;
    exp_lo_sum  = '0;
    exp_hi_sum  = '0;
  endfunction

  task main();
    calc_seq_item #(DataSize, AddrSize) trans;
    forever begin
      sb_box.get(trans);

      // Backdoor initialization events keep our mirrors in sync
      if (trans.initialize) begin
        if (!trans.loc_sel) mem_a[trans.initialize_addr] = trans.initialize_data;
        else                mem_b[trans.initialize_addr] = trans.initialize_data;
        // Safe to reset pair state around init
        have_lower = 1'b0;
        continue;
      end

      // READ: check against mirror and compute per-word sum
      if (!trans.rdn_wr) begin
        logic [DataSize-1:0] exp_lo = mem_a[trans.curr_rd_addr];
        logic [DataSize-1:0] exp_hi = mem_b[trans.curr_rd_addr];
        if (trans.lower_data !== exp_lo || trans.upper_data !== exp_hi) begin
          $error("%0t SB READ mismatch @0x%0x: got lo=0x%0x hi=0x%0x exp lo=0x%0x hi=0x%0x",
                 $time, trans.curr_rd_addr, trans.lower_data, trans.upper_data, exp_lo, exp_hi);
          $finish;
        end

        // Compute 32-bit sum for this word
        if (!have_lower) begin
          exp_lo_sum = trans.lower_data + trans.upper_data; // first read → lower sum
          have_lower = 1'b1;
        end else begin
          exp_hi_sum = trans.lower_data + trans.upper_data; // second read → upper sum
          have_lower = 1'b0;
        end

        continue;
      end

      // WRITE: compare packed sums and update mirrors
      if (trans.rdn_wr) begin
        logic [DataSize-1:0] got_lo = trans.lower_data;
        logic [DataSize-1:0] got_hi = trans.upper_data;

        // Expect write only after two reads
        if (have_lower) begin
          $error("%0t SB WRITE seen before second read (partial pair) @0x%0x",
                 $time, trans.curr_wr_addr);
          $finish;
        end

        if (got_lo !== exp_lo_sum || got_hi !== exp_hi_sum) begin
          $error("%0t SB WRITE mismatch @0x%0x: got {hi,lo}={0x%0x,0x%0x} exp {0x%0x,0x%0x}",
                 $time, trans.curr_wr_addr, got_hi, got_lo, exp_hi_sum, exp_lo_sum);
          $finish;
        end else begin
          $display("%0t SB WRITE OK @0x%0x: {hi,lo}={0x%0x,0x%0x}",
                   $time, trans.curr_wr_addr, got_hi, got_lo);
        end

        // Update mirrors to reflect the write
        mem_a[trans.curr_wr_addr] = got_lo;
        mem_b[trans.curr_wr_addr] = got_hi;
        // pair state already cleared by have_lower=0
        continue;
      end
    end
  endtask

endclass
