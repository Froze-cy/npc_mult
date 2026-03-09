module csr_regfile(
    input  wire        clk         ,  
    input  wire        rst_n       , 
    input  wire        ecall_flag  ,
    input  wire        ebreak_flag ,
    input  wire        mret_flag   ,
    input  wire        csr_wr_flag ,
    input  wire [11:0] csr_addr    ,    
    input  wire [31:0] curr_pc     , 
    input  wire [31:0] csr_wr      ,
    output wire [31:0] csr_rd      ,
    output wire [31:0] csr_mepc    ,
    output reg  [31:0] mtvec_pc    
        
   
);
//定义csr地址
localparam mstatus   = 12'h300;
localparam mtvec     = 12'h305;
localparam mscratch  = 12'h340;
localparam mepc      = 12'h341;
localparam mcause    = 12'h342;
localparam mcycle    = 12'hb00;
localparam mcycleh   = 12'hb80;
localparam mvendorid = 12'hf11;
localparam marchid   = 12'hf12;


reg [31:0] csr_rf [4095:0] ;

//初始化csr
initial begin
integer i;
for(i=0;i<4096;i=i+1)
   if(i==mvendorid)
       csr_rf[i] = 32'h79737978;
   else if(i==marchid)
       csr_rf[i] = 32'h1234abcd;
   else	   
       csr_rf[i] = 32'h0 ;	
end


reg         cycle_flag   ;
wire [31:0] csr_mstatus  ;
wire [31:0] csr_mtvec    ; 
wire [31:0] csr_mscratch ;  
wire [31:0] csr_mcause   ; 
wire [31:0] csr_mcycle   ; 
wire [31:0] csr_mcycleh  ; 
wire [31:0] csr_mvendorid; 
wire [31:0] csr_marchid  ; 
wire [29:0] mtvec_base   ;
wire [1:0]  mtvec_mode   ;

//读取特殊csr的值
assign csr_mstatus   = csr_rf[mstatus  ]; 
assign csr_mtvec     = csr_rf[mtvec    ];
assign csr_mscratch  = csr_rf[mscratch ];
assign csr_mepc      = csr_rf[mepc     ];
assign csr_mcause    = csr_rf[mcause   ];
assign csr_mcycle    = csr_rf[mcycle   ];
assign csr_mcycleh   = csr_rf[mcycleh  ];
assign csr_mvendorid = csr_rf[mvendorid];
assign csr_marchid   = csr_rf[marchid  ];


assign csr_rd     = csr_rf[csr_addr];
assign mtvec_base = csr_rf[mtvec][31:2];
assign mtvec_mode = csr_rf[mtvec][1:0];

//mtvec
always @(*)begin
   if(ecall_flag)
	mtvec_pc = {mtvec_base,2'b0};
   else
	mtvec_pc = 32'h0;   
end

//mstatus
always @(posedge clk)begin
   if(ecall_flag)
	csr_rf[mstatus] <= 32'h00001800;   
end

//mepc
always @(posedge clk)begin
   if(ecall_flag)
	csr_rf[mepc] <= curr_pc;
end

//mcause
always @(posedge clk)begin
   if(ecall_flag)
	csr_rf[mcause] <= 32'h0000000b; //异常号11,即M模式环境调用   
end


//csrrs csrrw
always @(posedge clk)begin	   
   if(csr_wr_flag&&(csr_addr!=mvendorid)&&(csr_addr!=marchid))
	csr_rf[csr_addr] <= csr_wr ;
end



//计数器实现
always @(posedge clk or negedge rst_n)begin
     if(!rst_n)
         csr_rf[mcycle] <= 32'h0;
     else 
	 csr_rf[mcycle] <= csr_rf[mcycle] + 32'h1;   
end

always @(posedge clk or negedge rst_n)begin  
    if(!rst_n)
	 cycle_flag <= 1'b0;   
    else if(&csr_rf[mcycle]==1'b1)
	 cycle_flag <= 1'b1;
    else
	 cycle_flag <= 1'b0;   
end

always @(posedge clk or negedge rst_n)begin
    if(!rst_n)
	 csr_rf[mcycleh] <= 32'h0;   
    else if(cycle_flag)
	 csr_rf[mcycleh] <= csr_rf[mcycleh] + 32'h1 ;
end



endmodule
