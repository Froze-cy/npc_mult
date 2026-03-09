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
    output wire [31:0] mem_wr_addr     
);

import "DPI-C" function void goodtrap_dpi();
import "DPI-C" function void badtrap_dpi();
import "DPI-C" function int pmem_read(input int raddr);
import "DPI-C" function void pmem_write(input int waddr,input int wdata,input byte wmask);

//IFU
wire        if_id_valid;
wire        pc_ready   ;

//IDU
wire        if_id_ready;
wire [4:0]  rs1_addr   ;
wire [4:0]  rs2_addr   ;
wire [4:0]  rd_wr_addr ;  
wire [11:0] csr_addr   ;
wire [31:0] imm        ;
wire [5:0]  alu_op     ;
wire        reg_we     ;
wire [1:0]  byte_type  ;
wire        sign_type  ;
wire        load_flag  ;
wire        ecall_flag ;
wire        csr_wr_flag;
wire        mret_flag  ;
wire        break_flag ;
wire        jump_flag  ;
wire        trap_flag  ;
wire [31:0] idu_curr_pc;
wire        id_ex_valid;

//EXU
wire        jump_valid    ;
wire [31:0] jump_pc       ;
wire        ex_ls_valid   ;
wire        id_ex_ready   ;
wire [31:0] exu_rs2       ;
wire        exu_mem_we    ; 
wire        exu_mem_re    ;
wire [1:0]  exu_byte_type ;
wire        exu_sign_type ;
wire        exu_break_flag;
wire        exu_ecall_flag; 
wire        exu_mret_flag ; 
wire        exu_reg_we    ; 
wire [4:0]  exu_rd_addr   ;
wire        exu_load_flag ;
wire [31:0] exu_rd_wr     ;
wire [31:0] csr_wr        ;
wire [31:0] mepc_wr       ;

//LSU
wire        lsu_ready     ;
wire [31:0] lsu_load_data ;

//WBU
wire [31:0] reg_wr_data;
wire        wb_done    ;

//regfile
wire [31:0] rs1 ;
wire [31:0] rs2 ;

//csr_regfile
wire        trap_valid;
wire [31:0] mtvec_pc  ;
wire [31:0] csr_mepc  ;
wire [31:0] csr_rd    ;

/////////////////////////////////////////////////////////////

assign good_trap = exu_break_flag&&inst[31:20]==12'h1;
assign bad_trap  = exu_break_flag&&inst[31:20]==12'h2;

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
.inst_ready (inst_ready ) ,
.inst       (inst       ) ,
.inst_valid (inst_valid ) ,
.curr_pc    (curr_pc    ) ,
//IDU<-->register
.rs1_addr   (rs1_addr   ) ,
.rs2_addr   (rs2_addr   ) , 
//IDU<-->EXU
.imm        (imm        ) ,
.id_ex_valid(id_ex_valid) ,
.id_ex_ready(id_ex_ready) ,
.alu_op     (alu_op     ) ,   
.mem_we     (mem_we     ) ,
.mem_re     (mem_re     ) ,
.reg_we     (reg_we     ) ,
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
.csr_addr   (csr_addr   ) ,
.csr_wr_flag(csr_wr_flag) 
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
.idu_valid    (idu_valid     ) ,
.exu_ready    (exu_ready     ) ,
.idu_alu_op   (alu_op        ) ,
.idu_imm      (imm           ) ,
.idu_mem_we   (mem_we        ) ,
.idu_mem_re   (mem_re        ) ,
.idu_byte_type(byte_type     ) ,
.idu_sign_type(sign_type     ) ,
.idu_reg_we   (reg_we        ) ,
.idu_rd_addr  (rd_wr_addr    ) ,
.idu_load_flag(idu_load_flag ) ,
.idu_break_flag(break_flag   ) , 
.idu_ecall_flag(ecall_flag   ) ,
.idu_mret_flag (mret_flag    ) ,
.jump_flag     (jump_flag    ) ,
.trap_flag     (trap_flag    ) ,
//EXU<-->CSR
.exu_break_flag(exu_break_flag) , 
.exu_ecall_flag(exu_ecall_flag) , 
.exu_mret_flag (exu_mret_flag ) , 
//EXU<-->LSU
.exu_valid    (exu_valid     ) ,
.lsu_ready    (lsu_ready     ) ,
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
.rs2          (rs2           ) ,
//EXU<-->csr_register
.csr_rd       (csr_rd        ) ,
.csr_wr       (csr_wr        ) ,
.csr_mepc     (csr_mepc      ) ,
.mepc_wr      (mepc_wr       ) ,
.curr_pc      (curr_pc       )           
);


/////////////////////////////////////////////////////////////
LSU LSU_inst
(
.clk       (clk           ) ,
.rst_n     (rst_n         ) ,
//EXU<-->LSU
.exu_valid (exu_valid     ) ,
.lsu_ready (lsu_ready     ) ,
.mem_we    (exu_mem_we    ) , 
.mem_re    (exu_mem_re    ) , 
.byte_type (exu_byte_type ) ,
.sign_type (exu_sign_type ) ,
.store_data(exu_rs2       ) ,
.store_addr(mem_wr_addr   ) ,
.load_addr (mem_rd_addr   ) ,
.load_data (load_data     )
);


/////////////////////////////////////////////////////////////
WBU WBU_isnt
(
.exu_load_flag(exu_load_flag) ,
.exu_rd_wr    (exu_rd_wr    ) ,   
.exu_rd_addr  (exu_rd_addr  ) ,
.lsu_load_data(lsu_load_data) ,
.wbu_wr_data  (wbu_wr_data  ) 
);

/////////////////////////////////////////////////////////////
regfile regfile_inst
(
.clk         (clk         ) , 
.rs1_addr    (rs1_addr    ) ,
.rs2_addr    (rs2_addr    ) ,
.rd_wr_addr  (wbu_rd_addr ) ,
.reg_we      (wbu_reg_we  ) ,
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
.trap_valid  (trap_valid     ),
.ecall_flag  (exu_ecall_flag ),
.ebreak_flag (exu_ebreak_flag),
.mret_flag   (exu_mret_flag  ),
.csr_wr_flag (csr_wr_flag    ),
.csr_addr    (csr_addr       ),    
.curr_pc     (curr_pc        ), 
.csr_wr      (csr_wr         ),
.csr_rd      (csr_rd         ),
.csr_mepc    (csr_mepc       ),
.mtvec_pc    (mtvec_pc       )
);


endmodule
