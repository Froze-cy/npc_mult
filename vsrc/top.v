module top
(
    input  wire        clk        ,
    input  wire        rst_n      , 
    output wire [31:0] curr_pc    ,
    output wire [31:0] inst       ,
    //debug
    input  wire [4:0]  debug_addr ,
    output wire [31:0] debug_reg  ,
    output wire        good_trap  ,
    output wire        bad_trap   ,
    output wire        mem_re     ,
    output wire        mem_we     ,
    output wire [31:0] mem_rd_addr,
    output wire [31:0] mem_wr_addr,     
    output wire        diff_flag 
);

import "DPI-C" function void goodtrap_dpi();
import "DPI-C" function void badtrap_dpi();
import "DPI-C" function int pmem_read(input int raddr);
import "DPI-C" function void pmem_write(input int waddr,input int wdata,input byte wmask);

//IFU
wire        if_id_valid;
wire        pc_ready   ;

//IDU
wire        if_id_ready    ;
wire        idu_valid      ;
wire [4:0]  idu_rs1_addr   ;
wire [4:0]  idu_rs2_addr   ;
wire [4:0]  rd_wr_addr     ;  
wire [31:0] imm            ;
wire [5:0]  alu_op         ;
wire        idu_reg_we     ;
wire [1:0]  byte_type      ;
wire        sign_type      ;
wire        load_flag      ;
wire        ecall_flag     ;
wire        mret_flag      ;
wire        break_flag     ;
wire        jump_flag      ;
wire        trap_flag      ;
wire [31:0] idu_curr_pc    ;
wire [11:0] idu_csr_addr   ;
wire        idu_csr_wr_flag;

//EXU
wire        jump_valid     ;
wire [31:0] jump_pc        ;
wire        ex_csr_valid   ;
wire        ex_ls_valid    ;
wire        exu_ready      ; 
wire [31:0] exu_rs2        ;
wire        exu_mem_we     ; 
wire        exu_mem_re     ;
wire [1:0]  exu_byte_type  ;
wire        exu_sign_type  ;
wire        exu_break_flag ;
wire        exu_ecall_flag ; 
wire        exu_mret_flag  ; 
wire        exu_reg_we     ; 
wire [4:0]  exu_rd_addr    ;
wire        exu_load_flag  ;
wire        exu_csr_wr_flag;
wire [11:0] exu_csr_addr   ; 
wire [31:0] exu_curr_pc    ;
wire [31:0] exu_rd_wr      ;
wire [31:0] csr_wr         ;

//LSU
wire        ex_ls_ready   ;
wire [31:0] lsu_load_data ;
wire        lsu_data_valid;

//WBU
wire [31:0] wbu_wr_data;
wire        wb_done    ;
wire        wbu_we     ;
wire [4:0]  wbu_wr_addr;

//regfile
wire [31:0] rs1 ;
wire [31:0] rs2 ;

//csr_regfile
wire        trap_valid  ;
wire [31:0] trap_pc     ;
wire        ex_csr_ready;
wire [31:0] csr_rd      ;

/////////////////////////////////////////////////////////////

assign good_trap = exu_break_flag&&inst[31:20]==12'h1;
assign bad_trap  = exu_break_flag&&inst[31:20]==12'h2;
assign diff_flag = trap_valid || wb_done || jump_valid;

/////////////////////////////////////////////////////////////
IFU  IFU_inst
(
.clk         (clk         ) ,
.rst_n       (rst_n       ) ,
.pc_ready    (pc_ready    ) ,
.jump_valid  (jump_valid  ) ,
.trap_valid  (trap_valid  ) ,
.wb_done     (wb_done     ) ,
.if_id_valid (if_id_valid ) ,
.if_id_ready (if_id_ready ) ,
.jump_pc     (jump_pc     ) ,
.trap_pc     (trap_pc     ) ,
.curr_pc     (curr_pc     ) ,    
.inst        (inst        )
);


/////////////////////////////////////////////////////////////
IDU IDU_inst
(
.clk        (clk        ) ,
.rst_n      (rst_n      ) ,
//IFU<-->IDU
.if_id_ready(if_id_ready) ,
.inst       (inst       ) ,
.if_id_valid(if_id_valid) ,
.curr_pc    (curr_pc    ) ,
//IDU<-->register
.rs1_addr   (idu_rs1_addr) ,
.rs2_addr   (idu_rs2_addr) , 
//IDU<-->EXU
.imm        (imm        ) ,
.idu_valid  (idu_valid  ) ,
.exu_ready  (exu_ready  ) ,
.alu_op     (alu_op     ) ,   
.mem_we     (mem_we     ) ,
.mem_re     (mem_re     ) ,
.idu_reg_we (idu_reg_we ) ,
.rd_wr_addr (rd_wr_addr ) ,
.byte_type  (byte_type  ) ,
.sign_type  (sign_type  ) ,
.load_flag  (load_flag  ) ,
.jump_flag  (jump_flag  ) ,
.trap_flag  (trap_flag  ) ,
.idu_curr_pc(idu_curr_pc) ,
.ecall_flag (ecall_flag ) ,
.mret_flag  (mret_flag  ) ,
.break_flag (break_flag ) ,
//IDU<-->csr_register
.csr_addr   (idu_csr_addr   ) ,
.csr_wr_flag(idu_csr_wr_flag) 
);


/////////////////////////////////////////////////////////////
EXU EXU_inst
(
.clk          (clk           ) ,
.rst_n        (rst_n         ) ,
.pc_ready     (pc_ready      ) ,
//EXU<-->IFU
.jump_valid   (jump_valid    ) ,
.jump_pc      (jump_pc       ) ,
//IDU<-->EXU
.idu_valid      (idu_valid      ) ,
.exu_ready      (exu_ready      ) ,
.idu_alu_op     (alu_op         ) ,
.idu_imm        (imm            ) ,
.idu_curr_pc    (idu_curr_pc    ) , 
.idu_mem_we     (mem_we         ) ,
.idu_mem_re     (mem_re         ) ,
.idu_byte_type  (byte_type      ) ,
.idu_sign_type  (sign_type      ) ,
.idu_reg_we     (idu_reg_we     ) ,
.idu_rd_addr    (rd_wr_addr     ) ,
.idu_load_flag  (load_flag      ) ,
.idu_break_flag (break_flag     ) , 
.idu_ecall_flag (ecall_flag     ) ,
.idu_mret_flag  (mret_flag      ) ,
.idu_csr_addr   (idu_csr_addr   ) ,
.idu_csr_wr_flag(idu_csr_wr_flag) ,
.jump_flag      (jump_flag      ) ,
.trap_flag      (trap_flag      ) ,
//EXU<-->CSR
.ex_csr_valid   (ex_csr_valid   ) ,
.ex_csr_ready   (ex_csr_ready   ) ,
.trap_valid     (trap_valid     ) ,	
.exu_csr_wr_flag(exu_csr_wr_flag) ,
.exu_csr_addr   (exu_csr_addr   ) ,
.exu_curr_pc    (exu_curr_pc    ) ,
.exu_break_flag (exu_break_flag ) , 
.exu_ecall_flag (exu_ecall_flag ) , 
.exu_mret_flag  (exu_mret_flag  ) , 
.csr_rd         (csr_rd         ) ,
.csr_wr         (csr_wr         ) ,      
//EXU<-->LSU
.ex_ls_valid  (ex_ls_valid   ) ,
.ex_ls_ready  (ex_ls_ready   ) ,
.mem_wr_addr  (mem_wr_addr   ) ,
.mem_rd_addr  (mem_rd_addr   ) ,
.exu_rs2      (exu_rs2       ) ,
.exu_mem_we   (exu_mem_we    ) , 
.exu_mem_re   (exu_mem_re    ) , 
.exu_byte_type(exu_byte_type ) ,
.exu_sign_type(exu_sign_type ) ,
//EXU<-->WBU
.exu_reg_we   (exu_reg_we    ) ,
.exu_rd_addr  (exu_rd_addr   ) ,
.exu_rd_wr    (exu_rd_wr     ) , 
.exu_load_flag(exu_load_flag ) ,
//EXU<-->register
.rs1          (rs1           ) ,
.rs2          (rs2           ) 
);


/////////////////////////////////////////////////////////////
LSU LSU_inst
(
.clk           (clk           ) ,
.rst_n         (rst_n         ) ,
//EXU<-->LSU
.ex_ls_valid   (ex_ls_valid   ) ,
.ex_ls_ready   (ex_ls_ready   ) ,
.exu_mem_we    (exu_mem_we    ) , 
.exu_mem_re    (exu_mem_re    ) , 
.exu_byte_type (exu_byte_type ) ,
.exu_sign_type (exu_sign_type ) ,
.store_data    (exu_rs2       ) ,
.store_addr    (mem_wr_addr   ) ,
.load_addr     (mem_rd_addr   ) ,
//LSU-->WBU
.lsu_load_data (lsu_load_data ) ,
.lsu_data_valid(lsu_data_valid) 	
);


/////////////////////////////////////////////////////////////
WBU WBU_isnt
(
.clk           (clk           ) ,
.rst_n         (rst_n         ) ,
.exu_load_flag (exu_load_flag ) ,
.exu_rd_wr     (exu_rd_wr     ) ,   
.exu_reg_we    (exu_reg_we    ) ,
.exu_rd_addr   (exu_rd_addr   ) ,
.lsu_load_data (lsu_load_data ) ,
.lsu_data_valid(lsu_data_valid) ,
.wbu_wr_data   (wbu_wr_data   ) , 
.wbu_we        (wbu_we        ) ,
.wbu_wr_addr   (wbu_wr_addr   ) ,
.wb_done       (wb_done       )
);

/////////////////////////////////////////////////////////////
regfile regfile_inst
(
.clk         (clk         ) , 
.rs1_addr    (idu_rs1_addr) ,
.rs2_addr    (idu_rs2_addr) ,
.rd_wr_addr  (wbu_wr_addr ) ,
.reg_we      (wbu_we      ) ,
.wr_data     (wbu_wr_data ) ,    
.rs1         (rs1         ) ,
.rs2         (rs2         ) ,
.debug_addr  (debug_addr  ) ,
.debug_reg   (debug_reg   )
);

////////////////////////////////////////////////////////////
csr_regfile csr_regfile_inst
(
.clk         (clk            ),  
.rst_n       (rst_n          ),
.ex_csr_valid(ex_csr_valid   ),
.ex_csr_ready(ex_csr_ready   ),
.pc_ready    (pc_ready       ),
.trap_valid  (trap_valid     ),
.trap_pc     (trap_pc        ),
.ecall_flag  (exu_ecall_flag ),
.break_flag  (exu_break_flag ),
.mret_flag   (exu_mret_flag  ),
.csr_wr_flag (exu_csr_wr_flag),
.csr_addr    (exu_csr_addr   ),    
.curr_pc     (exu_curr_pc    ), 
.csr_wr      (csr_wr         ),
.csr_rd      (csr_rd         )
);


endmodule
