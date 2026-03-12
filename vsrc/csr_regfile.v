module csr_regfile(
    input  wire        clk         ,  
    input  wire        rst_n       ,
    output reg         break_done  ,    
    //CSR<-->IFU
    output reg  [31:0] trap_pc     ,
    //CSR_IFU 握手
    input  wire        pc_ready    ,
    output reg         trap_valid  ,	    
    //EXU<-->CSR
    input  wire        ecall_flag  ,
    input  wire        break_flag  ,
    input  wire        mret_flag   ,
    input  wire [31:0] curr_pc     ,
    input  wire [31:0] csr_wr      ,
    input  wire        csr_wr_flag ,
    input  wire [11:0] csr_addr    ,
    output reg  [31:0] csr_rd      ,     
    //EXU_CSR 握手 
    input  wire        ex_csr_valid,
    output reg         ex_csr_ready	    
);


/////////////////////////////状态机///////////////////////////////
localparam IDLE = 2'd0, TRAP_SEND = 2'd1; 
reg [1:0]  curr_state;
reg        ecall_flag_reg;
reg        break_flag_reg;
reg        mret_flag_reg;
reg [31:0] curr_pc_reg;

always @(posedge clk or negedge rst_n)begin
	if(!rst_n)begin
                      trap_valid   <= 1'b0;    
                      ex_csr_ready <= 1'b1;
                      curr_state   <= IDLE;
                      break_done   <= 1'b0;
      	end
	else case(curr_state)
	     IDLE:begin
                  if(ex_csr_valid)begin
		      curr_state   <= TRAP_SEND;
	              trap_valid   <= 1'b1;
		      ex_csr_ready <= 1'b0;
		      break_done   <= 1'b0;
	          end
		  else begin
		      curr_state   <= IDLE;
	              trap_valid   <= 1'b0;
		      ex_csr_ready <= 1'b1;
		      break_done   <= 1'b0;
	          end	      
	     end
	     TRAP_SEND:begin 
	          if(pc_ready)begin
		      curr_state   <= IDLE;
		      trap_valid   <= 1'b0;
		      ex_csr_ready <= 1'b1;
		      break_done   <= break_flag_reg;
	          end    
		  else begin
		      curr_state   <= TRAP_SEND;
	              trap_valid   <= 1'b1;
		      ex_csr_ready <= 1'b0;
		      break_done   <= 1'b0;
	          end	      
	     end
	     default:begin
                      trap_valid   <= 1'b0;
	              ex_csr_ready <= 1'b1;
                      curr_state   <= IDLE;
		      break_done   <= 1'b0;
	     end
     endcase
end

always @(posedge clk or negedge rst_n)begin
	if(!rst_n)begin
            ecall_flag_reg <= 1'b0 ;
            break_flag_reg <= 1'b0 ;
            mret_flag_reg  <= 1'b0 ;
            curr_pc_reg    <= 32'b0;
        end
	else if(ex_csr_valid&&ex_csr_ready)begin
            ecall_flag_reg <= ecall_flag ;
            break_flag_reg <= break_flag ;
            mret_flag_reg  <= mret_flag  ;
            curr_pc_reg    <= curr_pc    ;
        end	
end


//////////////////////////////////////////////////////////////////

//定义csr地址
localparam MSTATUS   = 12'h300;
localparam MTVEC     = 12'h305;
localparam MSCRATCH  = 12'h340;
localparam MEPC      = 12'h341;
localparam MCAUSE    = 12'h342;
localparam MCYCLE    = 12'hb00;
localparam MCYCLEH   = 12'hb80;
localparam MVENDORID = 12'hf11;
localparam MARCHID   = 12'hf12;


reg [31:0] mstatus; 
reg [31:0] mepc;
reg [31:0] mcause;
reg [31:0] mcycle;
reg [31:0] mcycleh;
reg [31:0] mscratch;
reg [31:0] mtvec;
reg [31:0] mvendorid;
reg [31:0] marchid;
    
//初始化csr
initial begin
  mvendorid = 32'h79737978;
  marchid   = 32'h1234abcd;   
end

//csr_rd
always @(*)begin
     case(csr_addr)
        MSTATUS: csr_rd = mstatus;
          MTVEC: csr_rd = mtvec;
       MSCRATCH: csr_rd = mscratch;	
           MEPC: csr_rd = mepc;
	 MCAUSE: csr_rd = mcause; 
         MCYCLE: csr_rd = mcycle;
	MCYCLEH: csr_rd = mcycleh;
      MVENDORID: csr_rd = mvendorid;
        MARCHID: csr_rd = marchid;
        default: csr_rd = 32'hffffffff;	
     endcase
end

//trap_pc
always @(*)begin
   if(ecall_flag_reg||break_flag_reg)
        trap_pc = {mtvec[31:2],2'b0};	   
   else if(mret_flag_reg)
	trap_pc = mepc;
   else
	trap_pc = 32'h0;   
end

//mtvec
always @(posedge clk or negedge rst_n)begin
   if(!rst_n)
	mtvec <= 32'h0;
   else if(csr_wr_flag&&csr_addr==MTVEC)
	mtvec <= csr_wr;  
end



//mstatus
always @(posedge clk or negedge rst_n)begin
   if(!rst_n)
	mstatus <= 32'h0;   
   else if(ecall_flag_reg||break_flag_reg)//MPP=3,MPIE=0,MIE=0
	mstatus <= 32'h00001800;  
   else if(mret_flag_reg) //MPP=3,MPIE=1,MIE=0
	mstatus <= 32'h00001c00;
   else if(csr_wr_flag&&csr_addr==MSTATUS)
	mstatus <= csr_wr;   
end

//mepc
always @(posedge clk or negedge rst_n)begin
   if(!rst_n)
	mepc <= 32'h0;    
   else if(ecall_flag_reg||break_flag_reg)
	mepc <= curr_pc_reg;
   else if(csr_wr_flag&&csr_addr==MEPC)
	mepc <= csr_wr;   
end

//mcause
always @(posedge clk or negedge rst_n)begin
   if(!rst_n)
	mcause <= 32'h0;   
   else if(ecall_flag_reg)
	mcause <= 32'h0000000b; //异常号11,即M模式环境调用 
   else if(break_flag_reg)
	mcause <= 32'h00000003; //异常号3，break   
   else if(csr_wr_flag&&csr_addr==MCAUSE)
	mcause <= csr_wr;   
end

//mscratch
always @(posedge clk or negedge rst_n)begin
     if(!rst_n)
       mscratch <= 32'h0;	     
     else if(csr_wr_flag&&csr_addr==MSCRATCH)
       mscratch <= csr_wr;	   
end

//mcycle
always @(posedge clk or negedge rst_n)begin
     if(!rst_n)
         mcycle <= 32'h0;
     else if(csr_wr_flag&&csr_addr==MCYCLE)
	 mcycle <= csr_wr;
     else 
	 mcycle <= mcycle + 32'h1;   
end

//mcycleh
always @(posedge clk or negedge rst_n)begin
    if(!rst_n)
	 mcycleh <= 32'h0;   
    else if(csr_wr_flag&&csr_addr==MCYCLEH)
	 mcycleh <= csr_wr;   
    else if(&mcycle)
	 mcycleh <= mcycleh + 32'h1;
end


endmodule
