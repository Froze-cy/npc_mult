module mem_lsu
#(
      parameter MEM_WIDTH = 32 ,
      parameter MEM_DEPTH = 32  
)
(
   input  wire        clk       ,
   input  wire        byte_type ,
   input  wire [31:0] wr_data   ,
   input  wire [31:0] wr_addr   ,
   input  wire        mem_we    ,
   input  wire        mem_re    ,
   input  wire [31:0] rd_addr   ,       
   output wire [31:0] rd_data   
);




reg [MEM_WIDTH-1:0] mem [2**MEM_DEPTH-1:0] ;

integer i;

initial begin

  //$readmemh("/home/froze/ysyx-workbench/npc/vsrc/sum.hex",mem); 
  for(i=0;i<2**MEM_DEPTH-1;i=i+1)
	  mem[i] = 0;
end

assign rd_data = (mem_re&&rd_addr[1:0]==2'b0)?mem[rd_addr]:32'h0;

always @(posedge clk)begin

       if(mem_we&&wr_addr[1:0]==2'b0&&byte_type)
	 mem[wr_addr][7:0] <= wr_data[7:0];

       else if(mem_we&&wr_addr[1:0]==2'b0)
	 mem[wr_addr] <= wr_data ;   

end

endmodule
