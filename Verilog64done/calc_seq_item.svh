class calc_seq_item #(int DataSize, int AddrSize);

  rand logic rdn_wr;
  rand logic [AddrSize-1:0] read_start_addr;
  rand logic [AddrSize-1:0] read_end_addr;
  rand logic [AddrSize-1:0] write_start_addr;
  rand logic [AddrSize-1:0] write_end_addr;
  rand logic [DataSize-1:0] lower_data;
  rand logic [DataSize-1:0] upper_data;
  rand logic [AddrSize-1:0] curr_rd_addr;
  rand logic [AddrSize-1:0] curr_wr_addr;
  rand logic loc_sel;
  rand logic initialize;
  // Fields used to capture initialization transactions driven from the testbench
  rand logic [AddrSize-1:0] initialize_addr;
  rand logic [DataSize-1:0] initialize_data;

  // TODO: Implement constraint to make sure read end addresses are valid
  // ensure read_end is not below read_start
  constraint read_end_gt_start { read_end_addr >= read_start_addr; }
  // TODO: Implement constraint to make sure write end addresses are valid
  // ensure write_end is not below write_start
  constraint write_end_gt_start { write_end_addr >= write_start_addr; }
  // TODO: Implement constraint to make sure the read address ranges and write address ranges are valid
  // ensure addresses fall within the allowed address width (these are redundant with declared widths
  // but make the intent explicit for randomization engines)
  constraint address_ranges_valid {
    read_start_addr <= (2**AddrSize - 1);
    read_end_addr   <= (2**AddrSize - 1);
    write_start_addr <= (2**AddrSize - 1);
    write_end_addr   <= (2**AddrSize - 1);
  }

  function new();
  endfunction

  function void display();
  $display($stime, " Rdn_Wr: %b Read Start Addr: 0x%0x, Read End Addr: 0x%0x, Write Start Addr: 0x%0x, Write End Addr: 0x%0x, Data 0x%0x, Current Read Addr: 0x%0x, Current Write Addr: 0x%0x, Buffer location select: %b, SRAM initialization: %b InitAddr:0x%0x InitData:0x%0x\n",
    rdn_wr, read_start_addr, read_end_addr, write_start_addr, write_end_addr, {upper_data, lower_data}, curr_rd_addr, curr_wr_addr, loc_sel, initialize, initialize_addr, initialize_data);
  endfunction

endclass : calc_seq_item
