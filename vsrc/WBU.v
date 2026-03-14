module WBU
(   
    input  wire        exu_reg_done   ,
    input  wire [31:0] exu_rd_wr      ,
    input  wire [4:0]  exu_rd_addr    ,
    input  wire        exu_reg_we     ,
    input  wire        exu_load_flag  ,
    input  wire [31:0] lsu_load_data  ,
    input  wire        lsu_data_valid , 
    output wire [31:0] wbu_wr_data    ,   
    output wire        wbu_we         ,
    output wire [4:0]  wbu_wr_addr     
);


assign wbu_we      = exu_load_flag?lsu_data_valid:(exu_reg_we&exu_reg_done);
assign wbu_wr_data = exu_load_flag?lsu_load_data:exu_rd_wr;
assign wbu_wr_addr = exu_rd_addr;


endmodule
