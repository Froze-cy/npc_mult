module LSU
(
   input   wire        clk          ,
   input   wire        rst_n        , 
   //IDU<-->LSU
   input   wire        exu_valid    ,
   output  reg         lsu_ready    ,
   input   wire [1:0]  exu_byte_type,
   input   wire        exu_sign_type,
   input   wire        exu_mem_we   ,
   input   wire        exu_mem_re   ,
   input   wire [31:0] store_data   ,
   input   wire [31:0] store_addr   ,
   input   wire [31:0] load_addr    ,
   //LSU<-->WBU
   output  reg  [31:0] lsu_load_data  
);


import "DPI-C" function int pmem_read(input int raddr);
import "DPI-C" function void pmem_write(input int waddr,input int wdata,input byte wmask);
/////////////////////////状态机////////////////////////////////
localparam IDLE = 2'd0, LD_ST = 2'd1;
reg [1:0]  curr_state,next_state;
reg [1:0]  byte_type_reg;
reg        sign_type_reg;
reg        mem_we_reg;
reg        mem_re_reg;
reg [31:0] store_addr_reg;
reg [31:0] store_data_reg;
reg [31:0] load_addr_reg;

always @(posedge clk or negedge rst_n)begin
     if(!rst_n)
	   curr_state <= IDLE;
     else
	   curr_state <= next_state;  
end

always @(*)begin
     case(curr_state)
	     IDLE:begin
                  lsu_ready = 1'b1;
                  if(exu_valid)
			next_state = LD_ST;
	          else
			next_state = IDLE;  
	     end
	     LD_ST:begin
	          lsu_ready  = 1'b0;
                  next_state = IDLE; 		  
	     end
	     default:begin
                  lsu_ready  = 1'b1;
		  next_state = IDLE;
	     end
     endcase
end

always @(posedge clk or negedge rst_n)begin
     if(!rst_n)begin
         byte_type_reg <= 2'b0;
         sign_type_reg <= 1'b0;
         mem_we_reg <= 1'b0;
         mem_re_reg <= 1'b0;
         store_addr_reg <= 32'b0;
         store_data_reg <= 32'b0;
         load_addr_reg  <= 32'b0;

     end
     else if(exu_valid&&lsu_ready)begin
         byte_type_reg <= exu_byte_type;
         sign_type_reg <= exu_sign_type;
         mem_we_reg <= exu_mem_we;
         mem_re_reg <= exu_mem_re;
         store_addr_reg <= store_addr;
         store_data_reg <= store_data;
         load_addr_reg  <= load_addr ;
     end
end


wire [31:0] mem_rd_addr ;
wire [31:0] mem_wr_addr ;
wire [1:0]  offset      ;
reg  [31:0] mem_rd_data ;

assign mem_rd_addr = {load_addr_reg[31:2],2'b0};
assign mem_wr_addr = {store_addr_reg[31:2],2'b0};
assign offset      = load_addr_reg[1:0];

always @(*)begin
	if(mem_re_reg)
       mem_rd_data = pmem_read(mem_rd_addr);
   else 
       mem_rd_data = 32'h0;	     
end


always @(posedge clk)begin
    if(mem_we_reg&&byte_type_reg==2'b0)  //sw
        pmem_write(mem_wr_addr,store_data_reg,8'b1111);
    else if(mem_we_reg&&byte_type_reg==2'b1) //sb
	pmem_write(mem_wr_addr,store_data_reg,8'b0001<<store_addr_reg[1:0]);
    else if(mem_we_reg&&byte_type_reg==2'b10) //sh
	pmem_write(mem_wr_addr,store_data_reg,8'b0011<<store_addr_reg[1:0]);
end


always @(*)begin
   if(byte_type_reg==2'b0)
	   lsu_load_data = mem_rd_data;  //lw
   else if(!sign_type_reg&&byte_type_reg==2'b1) begin //lbu
        case (offset)
            2'b00: lsu_load_data = {24'b0, mem_rd_data[7:0]};
            2'b01: lsu_load_data = {24'b0, mem_rd_data[15:8]};
            2'b10: lsu_load_data = {24'b0, mem_rd_data[23:16]};
            2'b11: lsu_load_data = {24'b0, mem_rd_data[31:24]};
        endcase
   end
   else if(sign_type_reg&&byte_type_reg==2'b1)begin//lb
	 case (offset)
            2'b00: lsu_load_data = {{24{mem_rd_data[7]}}, mem_rd_data[7:0]};
            2'b01: lsu_load_data = {{24{mem_rd_data[15]}}, mem_rd_data[15:8]};
            2'b10: lsu_load_data = {{24{mem_rd_data[23]}}, mem_rd_data[23:16]};
            2'b11: lsu_load_data = {{24{mem_rd_data[31]}}, mem_rd_data[31:24]};
        endcase  
   end
    else if(sign_type_reg&&byte_type_reg==2'b10)begin//lh
	 case (offset)
            2'b00: lsu_load_data = {{16{mem_rd_data[15]}}, mem_rd_data[15:0]};
            2'b10: lsu_load_data = {{16{mem_rd_data[31]}}, mem_rd_data[31:16]};
          default: lsu_load_data =32'hffffffff;
         endcase  
   end
    else begin//lhu
	 case (offset)
            2'b00: lsu_load_data = {16'h0, mem_rd_data[15:0]};
            2'b10: lsu_load_data = {16'h0, mem_rd_data[31:16]};
          default: lsu_load_data =32'hffffffff;
         endcase  
   end
  
end

endmodule
