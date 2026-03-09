module mem_pc
#(
      parameter MEM_WIDTH = 32 ,
      parameter MEM_DEPTH = 32  
)
(
   input  wire [31:0] pc_addr   ,       
   output wire [31:0] inst   
);


reg [MEM_WIDTH-1:0] mem [2**MEM_DEPTH-1:0] ;

integer i;

initial begin
  $readmemh("/home/froze/ysyx-workbench/npc/vsrc/test.hex",mem);
  for (i=0;i<10;i=i+1)
   $display("IMEM[%0d]=0x%08x",i,mem[i]);
end

assign inst = mem[pc_addr>>2];


endmodule
