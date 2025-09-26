module controller import calculator_pkg::*;(
  	input  logic              clk_i,
    input  logic              rst_i,
  
  	// Memory Access
    input  logic [ADDR_W-1:0] read_start_addr,
    input  logic [ADDR_W-1:0] read_end_addr,
    input  logic [ADDR_W-1:0] write_start_addr,
    input  logic [ADDR_W-1:0] write_end_addr,
  
  	// Control
    output logic write,
    output logic [ADDR_W-1:0] w_addr,
    output logic [MEM_WORD_SIZE-1:0] w_data,

    output logic read,
    output logic [ADDR_W-1:0] r_addr,
    input  logic [MEM_WORD_SIZE-1:0] r_data,

  	// Buffer Control (1 = upper, 0, = lower)
    output logic              buffer_control,
  
  	// These go into adder
  	output logic [DATA_W-1:0]       op_a,
    output logic [DATA_W-1:0]       op_b,
  
    input  logic [MEM_WORD_SIZE-1:0]       buff_result
  
); 
	//TODO: Write your controller state machine as you see fit. 
	//HINT: See "6.2 Two Always BLock FSM coding style" from refmaterials/1_fsm_in_systemVerilog.pdf
	// This serves as a good starting point, but you might find it more intuitive to add more than two always blocks.

	//See calculator_pkg.sv for state_t enum definition
  	state_t state, next;

	logic [ADDR_W-1:0] read_addr, read_addr_next;
    logic [ADDR_W-1:0] write_addr, write_addr_next;
    logic buffer_half, buffer_half_next;

	//State reg, other registers as needed
	always_ff @(posedge clk_i) begin
		if (rst_i) begin
			state <= S_IDLE;
			read_addr <= read_start_addr;
            write_addr <= write_start_addr;
            buffer_half <= 1'b0; 
	end else begin
			state <= next;
			read_addr <= read_addr_next;
            write_addr <= write_addr_next;
            buffer_half <= buffer_half_next;
		end
	end
	
	//Next state logic, outputs
	always_comb begin
		next = state;
		read = 0;
		write = 0;
		buffer_control = buffer_half;

		read_addr_next  = read_addr;
        write_addr_next = write_addr;
        buffer_half_next = buffer_half;

		w_data =0;

		r_addr = read_addr;
        w_addr = write_addr;


		case (state)
			S_IDLE: begin
				read_addr_next  = read_start_addr;
                write_addr_next = write_start_addr;
                buffer_half_next = 1'b0;
				next = S_READ;
			end
			S_READ: begin
				read = 1;
				next = S_ADD;
				if (read_addr != read_end_addr) begin
                    read_addr_next = read_addr + 1;
				end
			end
			S_ADD:   begin
				op_a = r_data[31:0];
				op_b = r_data[63:32];
				if (buffer_half==0) begin
					buffer_half_next = 1'b1;
					next = S_READ;
				end else begin
					next = S_WRITE;	
				end
			end
			S_WRITE: begin
  				write = 1'b1;
  				w_data = buff_result;

  				// advance write pointer if not at the end
  				if (write_addr != write_end_addr) begin
    			write_addr_next = write_addr + 1;
				end
  				buffer_half_next = 1'b0;

  				// keep going if either side still has work
  				if ((read_addr != read_end_addr) || (write_addr_next != write_end_addr)) begin
    				next = S_READ;
				end else begin
    				next = S_END;
				end
end

			S_END: begin
				// After finishing a calculation, return to IDLE so the controller can accept
				// a new start without relying on an external reset. This also exercises
				// the S_END -> S_IDLE transition for coverage.
				next = S_END;
			end
			default: begin
				next = S_IDLE;
			end
		endcase
	end

endmodule
