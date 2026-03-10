module IFU
(
   input   wire          clk          ,
   input   wire          rst_n        ,
   output  reg   [31:0]  inst         ,  
   output  wire  [31:0]  curr_pc      ,
   output  reg           pc_ready     ,
   //IFU_IDU 握手
   input   wire          if_id_ready  ,    
   output  reg           if_id_valid  ,
   //EXU_IFU 握手
   input   wire          jump_valid   ,
   input   wire  [31:0]  jump_pc      ,
   //WBU-->IFU
   input   wire          wb_done      ,
   //CSR-->IFU
   input   wire          trap_valid   , 
   input   wire  [31:0]  trap_pc      	   

);
import "DPI-C" function int pmem_read(input int raddr);
import "DPI-C" function void pmem_write(input int waddr,input int wdata,input byte wmask);

reg  [31:0]  pc        ;
wire [31:0]  imem_addr ;


////////////////////////////状态机/////////////////////////////
localparam IDLE = 2'd0, SEND = 2'd1, WAIT_PC = 2'd2;
reg [1:0] curr_state,next_state;
reg       imem_addr_valid;

always @(posedge clk or negedge rst_n)begin
      if(!rst_n)
	   curr_state <= IDLE;
      else   
           curr_state <= next_state;
end

always @(*)begin
     case(curr_state)
	     IDLE:begin
                  imem_addr_valid = 1'b1;  
                  if_id_valid = 1'b0;
		  pc_ready = 1'b0;
		  if(if_id_ready)
		     next_state = SEND; 
	          else 
		     next_state = IDLE;	  
	     end
	     SEND:begin
                  if_id_valid = 1'b1;
		  imem_addr_valid = 1'b0;
		  pc_ready = 1'b0; 
		  if(if_id_ready)
                     next_state = WAIT_PC;
	          else
	             next_state = SEND;		  
	     end
	 WAIT_PC:begin
                  if_id_valid   = 1'b0;
 		  imem_addr_valid = 1'b0;
                  pc_ready = 1'b1;		  
                  if(jump_valid||trap_valid||wb_done)
		      next_state = IDLE;
                  else 
	              next_state = WAIT_PC;		  
	     end
	     default: begin
                  imem_addr_valid = 1'b0;
		  if_id_valid = 1'b0;
		  ex_if_ready = 1'b0;
		  next_state = IDLE;
	     end
     endcase    
end

always @(posedge clk or negedge rst_n)begin
   if(!rst_n)
	 inst <= 32'h0;
   else if(imem_addr_valid)
	 inst <= pmem_read(imem_addr); 
end
////////////////////////////////////////////////////////////////

always @(posedge clk or negedge rst_n)begin
   if(!rst_n)
	 pc <= 32'h80000000;
   else if(trap_valid&&pc_ready)
	 pc <= trap_pc;  
   else if(jump_valid&&pc_ready)
	 pc <= jump_pc;
   else if(wb_done&&pc_ready)
	 pc <= curr_pc + 4;  
end

assign curr_pc   = pc ;
assign imem_addr = {pc[31:2],2'b0};

/*mem_pc 
#(
  .MEM_WIDTH(32),
  .MEM_DEPTH(18)
)
mem_pc_inst
(
.pc_addr (imem_addr ),       
.inst    (inst      )
);*/

endmodule

