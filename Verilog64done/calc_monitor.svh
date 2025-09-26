class calc_monitor #(int DataSize, int AddrSize);
  logic written = 0;

  virtual interface calc_if #(.DataSize(DataSize), .AddrSize(AddrSize)) calcVif;
  mailbox #(calc_seq_item #(DataSize, AddrSize)) mon_box;

  function new(virtual interface calc_if #(DataSize, AddrSize) calcVif);
    this.calcVif = calcVif;
    this.mon_box = new();
  endfunction

  task main();
    forever begin
      @(calcVif.cb);
      if (calcVif.cb.rd_en && calcVif.cb.wr_en) begin
        $error($stime, " Mon: Error rd_en and wr_en both asserted at the same time\n");
      end
      // Sample the transaction and send to scoreboard
      if (calcVif.cb.wr_en || calcVif.cb.rd_en) begin
        calc_seq_item #(DataSize, AddrSize) trans = new();
        // Capture common fields visible at this clocking sample
        trans.rdn_wr       = calcVif.cb.wr_en; // write=1, read=0
        trans.curr_wr_addr = calcVif.cb.curr_wr_addr;
        trans.curr_rd_addr = calcVif.cb.curr_rd_addr;
        trans.read_start_addr  = calcVif.cb.read_start_addr;
        trans.read_end_addr    = calcVif.cb.read_end_addr;
        trans.write_start_addr = calcVif.cb.write_start_addr;
        trans.write_end_addr   = calcVif.cb.write_end_addr;
        trans.loc_sel      = calcVif.cb.loc_sel;

        if (trans.rdn_wr) // Write
        begin
          // Sample write data (packed {upper, lower}) from clocking block
          trans.lower_data = calcVif.cb.wr_data[31:0];
          trans.upper_data = calcVif.cb.wr_data[63:32];

          if (!written) begin
            written = 1;
            $display($stime, " Mon: Write to Addr: 0x%0x, Data to SRAM A (lower 32 bits): 0x%0x, Data to SRAM B (upper 32 bits): 0x%0x\n",
                trans.curr_wr_addr, trans.lower_data, trans.upper_data);
            mon_box.put(trans);
          end
        end
        else if (!trans.rdn_wr) // Read
        begin
          // For reads, r_data may become valid the following clocking sample in this design
          @(calcVif.cb);
          written = 0;
          // Sample read data (packed {upper, lower}) from clocking block
          trans.lower_data = calcVif.cb.rd_data[31:0];
          trans.upper_data = calcVif.cb.rd_data[63:32];

          $display($stime, " Mon: Read from Addr: 0x%0x, Data from SRAM A: 0x%0x, Data from SRAM B: 0x%0x\n",
              trans.curr_rd_addr, trans.lower_data, trans.upper_data);
          mon_box.put(trans);
        end
      end

      if (calcVif.cb.initialize) begin
        calc_seq_item #(DataSize, AddrSize) trans = new();
        // Populate init transaction fields so the scoreboard can update mirrors
        trans.initialize = calcVif.cb.initialize;
        trans.initialize_addr = calcVif.cb.initialize_addr;
        trans.initialize_data = calcVif.cb.initialize_data;
        trans.loc_sel = calcVif.cb.initialize_loc_sel;
        // For clarity mark as a write-like transaction
        trans.rdn_wr = 1;

        $display($stime, " Mon: Initialize SRAM; Write to SRAM %s, Addr: 0x%0x, Data: 0x%0x\n", !calcVif.cb.initialize_loc_sel ? "A" : "B", calcVif.cb.initialize_addr, calcVif.cb.initialize_data);
        mon_box.put(trans);
      end
    end
  endtask : main

endclass : calc_monitor
