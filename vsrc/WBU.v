module WBU
(   
    input  wire [31:0] exu_rd_wr      ,
    input  wire [4:0]  exu_rd_addr    ,
    input  wire        exu_load_flag  ,
    input  wire [31:0] lsu_load_data  , 
    output wire [31:0] wbu_wr_data     
);

assign wbu_wr_data  = exu_load_flag?lsu_load_data:exu_rd_wr;

endmodule
