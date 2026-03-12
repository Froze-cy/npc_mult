module IDU
(
    input  wire        clk        ,
    input  wire        rst_n      ,    
    //IFU	
    input  wire [31:0] inst       ,
    input  wire [31:0] curr_pc    ,
    //IFU_IDU 握手
    input  wire        if_id_valid,
    output reg         if_id_ready, 
    //registers
    output wire [4:0]  rs1_addr   ,
    output wire [4:0]  rs2_addr   , 
    output wire [4:0]  rd_wr_addr ,
    //EXU
    output reg  [31:0] imm        ,
    output reg  [5:0]  alu_op     ,
    output reg         idu_reg_we ,
    output reg         mem_we     ,
    output reg         mem_re     ,
    output reg  [1:0]  byte_type  ,
    output reg         sign_type  ,
    output reg         break_flag ,
    output reg         ecall_flag ,
    output reg         mret_flag  ,  
    output wire [11:0] csr_addr   , 
    output reg         csr_wr_flag,
    output reg         load_flag  ,
    output reg  [31:0] idu_curr_pc,     
    //IDU_EXU IDU_CSR 握手
    input  wire        exu_ready  ,
    output reg         idu_valid  ,
    output wire        jump_flag  ,
    output wire        trap_flag  ,
    output wire        lsu_flag    
);

import "DPI-C" function void goodtrap_dpi();
import "DPI-C" function void badtrap_dpi();

////////////////////////////状态机//////////////////////////////
localparam  IDLE = 2'd0, SEND = 2'd1;

reg  [1:0]  curr_state;
reg  [31:0] inst_reg;

always @(posedge clk or negedge rst_n)begin
	if(!rst_n)begin
           curr_state  <= IDLE;
	   if_id_ready <= 1'b1;
           idu_valid   <= 1'b0;
	end
        else
	case(curr_state)
		IDLE:begin 
		  if(if_id_valid)begin
                    if_id_ready<= 1'b0;
		    idu_valid  <= 1'b1;
		    curr_state <= SEND; 
	          end
		  else begin
                    if_id_ready<= 1'b1;
                    idu_valid  <= 1'b0;
                    curr_state <= IDLE; 
		  end 
	        end
		SEND:begin
		  if(exu_ready)begin
		    curr_state <= IDLE;
                    if_id_ready<= 1'b1;
		    idu_valid  <= 1'b0;
	          end  
		  else begin
	            curr_state <= SEND;		    
	            if_id_ready<= 1'b0;
		    idu_valid  <= 1'b1;
	          end 
	       end
	      default:begin
                    if_id_ready<= 1'b1;
		    idu_valid  <= 1'b0;
                    curr_state <= IDLE;
	      end
      endcase
end

always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
         inst_reg <= 32'h0;
         idu_curr_pc <= 32'h0;    
    end
    else if(if_id_valid&&if_id_ready)begin 
         inst_reg <= inst;
         idu_curr_pc <= curr_pc;
    end 
end

/////////////////////////////////////////////////////////////////
wire [6:0]  opcode ; 
wire [2:0]  funct3 ;
wire [6:0]  funct7 ;

assign opcode     = inst_reg[06:00];
assign rd_wr_addr = inst_reg[11:07]; 
assign funct3     = inst_reg[14:12];
assign rs1_addr   = inst_reg[19:15];
assign rs2_addr   = inst_reg[24:20];
assign funct7     = inst_reg[31:25];
assign csr_addr   = inst_reg[31:20];
assign jump_flag  = alu_op==6'd22||alu_op==6'd23||(alu_op>=6'd25&&alu_op<=6'd30);
assign trap_flag  = alu_op==6'd24||alu_op==6'd40||alu_op==6'd41;
assign lsu_flag   = (alu_op>=6'd17&&alu_op<=6'd21)||(alu_op>=6'd33&&alu_op<=6'd35);

always @(*)begin
     case (opcode) 	     
     //I-type
     7'b0010011: imm  = {{20{inst_reg[31]}},inst_reg[31:20]};  //addi  andi		
     7'b0000011: imm  = {{20{inst_reg[31]}},inst_reg[31:20]};  //lbu lw lb   
     7'b1100111: imm  = {{20{inst_reg[31]}},inst_reg[31:20]};  //jalr
     //S-type
     7'b0100011: imm  = {{20{inst_reg[31]}},inst_reg[31:25],inst_reg[11:7]}; //sw sb
     //U-type 
     7'b0110111: imm  = inst_reg[31:12]<<12;  //lui
     7'b0010111: imm  = inst_reg[31:12]<<12;  //auipc
     //J-type jal
     7'b1101111: imm  = {{12{inst_reg[31]}},inst_reg[19:12],inst_reg[20],inst_reg[30:21],1'b0}; 
     //B-type bne beq
     7'b1100011: imm  = {{20{inst_reg[31]}},inst_reg[7],inst_reg[30:25],inst_reg[11:8],1'b0}; 
     default   : imm  = 32'b0;        
   endcase	
end


//控制信号
always @(*)begin

    alu_op     = 6'b0 ;
    mem_we     = 1'b0 ;
    mem_re     = 1'b0 ;
    idu_reg_we = 1'b0 ;
    byte_type  = 2'b0 ;  //2'b0:lw 2'b1:lb 2'b10:lh
    sign_type  = 1'b0 ;
    load_flag  = 1'b0 ;
    break_flag = 1'b0 ;
    ecall_flag = 1'b0 ;
    csr_wr_flag= 1'b0 ;
    mret_flag  = 1'b0 ;
    
    case (opcode)
    //R-type
    7'b0110011:begin
	idu_reg_we = 1'b1 ;
        mem_we     = 1'b0 ;
        mem_re     = 1'b0 ;
	byte_type  = 2'b0 ;
        sign_type  = 1'b0 ;
	load_flag  = 1'b0 ;
	ecall_flag = 1'b0 ;
        csr_wr_flag= 1'b0 ;
	mret_flag  = 1'b0 ;
	break_flag = 1'b0 ;        
        case(funct3)
	 3'h0:begin
	     if(funct7==7'h0) 
               alu_op = 6'd0 ;  //add
             else  
               alu_op = 6'd1 ;  //sub
	     end
	 3'h1: alu_op = 6'd2 ;  //sll 
	 3'h2: alu_op = 6'd3 ;  //slt       
         3'h3: alu_op = 6'd4 ;  //sltu
         3'h4: alu_op = 6'd5 ;  //xor
	 3'h5:begin
              if(funct7==7'h20)
	       alu_op = 6'd6 ;  //sra	      
              else
	       alu_op = 6'd7 ;  //srl	      
	      end
	 3'h6: alu_op = 6'd37;  //or     
	 3'h7: alu_op = 6'h8 ;  //and	        
        default:
               alu_op = 6'd0 ;		  
        endcase
      end
    //I-type
    7'b0010011:begin   
               idu_reg_we = 1'b1 ;
	       mem_we     = 1'b0 ;
               mem_re     = 1'b0 ;
               byte_type  = 2'b0 ;
               sign_type  = 1'b0 ;
	       load_flag  = 1'b0 ;
               ecall_flag = 1'b0 ;
	       csr_wr_flag= 1'b0 ;
	       mret_flag  = 1'b0 ;
	       break_flag = 1'b0 ;	
           case(funct3)  
               3'h0:alu_op  = 6'd9 ;  //addi
	       3'h1:alu_op  = 6'd10;  //slli 
	       3'h2:alu_op  = 6'd31;  //slti
	       3'h3:alu_op  = 6'd32;  //sltiu
	       3'h4:alu_op  = 6'd11;  //xori
	       3'h5:begin  
         	    if(imm[11:5]==7'h20) //srai
	            alu_op  = 6'd12;
		    else if(imm[11:5]==7'h0) //srli 
                    alu_op  = 6'd13;     	
	            else
		    alu_op  = 6'd12;	    
	            end
	       3'h6:alu_op  = 6'd36 ; //ori	    
	       3'h7:alu_op  = 6'd14 ; //andi	    
	      default :alu_op = 6'd9 ;    
	   endcase
         end
    //lui
    7'b0110111:begin
                alu_op     = 6'd15;
		idu_reg_we = 1'b1 ;
                mem_we     = 1'b0 ;
                mem_re     = 1'b0 ;
                byte_type  = 2'b0 ;
        	sign_type  = 1'b0 ;
		load_flag  = 1'b0 ;
                break_flag = 1'b0 ;       
	        csr_wr_flag= 1'b0 ;
	       	mret_flag  = 1'b0 ;
		ecall_flag = 1'b0 ;
	        end
    //auipc
    7'b0010111:begin
                alu_op     = 6'd16;
		idu_reg_we = 1'b1 ;
                mem_we     = 1'b0 ;
                mem_re     = 1'b0 ;
                byte_type  = 2'b0 ;
        	sign_type  = 1'b0 ;
		load_flag  = 1'b0 ;
                break_flag = 1'b0 ; 
                csr_wr_flag= 1'b0 ;
	        mret_flag  = 1'b0 ;
		ecall_flag = 1'b0 ;
	        end
    //I-type		
    7'b0000011:begin
	idu_reg_we = 1'b1 ;
        mem_we     = 1'b0 ;
        mem_re     = 1'b1 ;
        load_flag  = 1'b1 ;
        break_flag = 1'b0 ;	
	csr_wr_flag= 1'b0 ;
	mret_flag  = 1'b0 ;
	ecall_flag = 1'b0 ;
	case(funct3)
          3'h0:begin //lb 
	        alu_op     = 6'd17;
                byte_type  = 2'b1 ;
	        sign_type  = 1'b1 ;
	       end
          3'h1:begin //lh 
	        alu_op     = 6'd33;
                byte_type  = 2'b10;
	        sign_type  = 1'b1 ;
	       end
	
     	  3'h2:begin //lw 
	        alu_op     = 6'd18;
                byte_type  = 2'b0 ;
	        sign_type  = 1'b0 ;
	       end
	  3'h4:begin //lbu
                alu_op     = 6'd19;
                byte_type  = 2'b1 ;
	        sign_type  = 1'b0 ;
	       end
	  3'h5:begin //lhu 
	        alu_op     = 6'd34;
                byte_type  = 2'b10;
	        sign_type  = 1'b0 ;
	       end
	     
          default:begin
                alu_op     = 6'd17;
                byte_type  = 2'b1 ;
	        sign_type  = 1'b1 ;
	       end		  
          endcase	               
      end
    //S-type
    7'b0100011:begin
	    idu_reg_we = 1'b0 ;
            mem_we     = 1'b1 ;
            mem_re     = 1'b0 ;
       	    load_flag  = 1'b0 ;
            ecall_flag = 1'b0 ;
	    csr_wr_flag= 1'b0 ;
	    mret_flag  = 1'b0 ;
	    break_flag = 1'b0 ;	 
 	    case(funct3)
	     3'h0:begin //sb		    
                   alu_op     = 6'd20;
                   byte_type  = 2'b1 ;
	           sign_type  = 1'b1 ;    
	          end
             3'h1:begin //sh
                   alu_op     = 6'd35;
                   byte_type  = 2'b10;
	           sign_type  = 1'b1 ;
	          end	     
             3'h2:begin //sw
                   alu_op     = 6'd21;
                   byte_type  = 2'b0 ;
	           sign_type  = 1'b0 ;
	          end
	     default:begin
                   alu_op     = 6'd21;
                   byte_type  = 2'b0 ;
	           sign_type  = 1'b0 ;
	          end
             endcase		
	   end
     //jal
     7'b1101111:begin
               alu_op     = 6'd22;
	       idu_reg_we = 1'b1 ;
               mem_we     = 1'b0 ;
               mem_re     = 1'b0 ;
               byte_type  = 2'b0 ;
               sign_type  = 1'b0 ;	       
               load_flag  = 1'b0 ;
               break_flag = 1'b0 ;
               csr_wr_flag= 1'b0 ; 
	       mret_flag  = 1'b0 ;
	       ecall_flag = 1'b0 ;
               end
    
     //jalr
     7'b1100111:begin
               alu_op     = 6'd23;
	       idu_reg_we = 1'b1 ;
               mem_we     = 1'b0 ;
               mem_re     = 1'b0 ;
               byte_type  = 2'b0 ;
               sign_type  = 1'b0 ;	       
               load_flag  = 1'b0 ;
               csr_wr_flag= 1'b0 ;
	       break_flag = 1'b0 ;	
               mret_flag  = 1'b0 ; 
	       ecall_flag = 1'b0 ;
               end
     //csrrs csrrw  
     7'b1110011:begin             
           mem_we     = 1'b0 ;
           mem_re     = 1'b0 ;
           byte_type  = 2'b0 ;
           sign_type  = 1'b0 ;	       
	   load_flag  = 1'b0 ;
	   case(funct3)
                3'b0:
		    case(inst_reg[31:20])
		         //ecall
		        12'h0:begin
				idu_reg_we = 1'b0 ;
                                break_flag = 1'b0 ;
		                ecall_flag = 1'b1 ;
		                csr_wr_flag= 1'b0 ;
			        mret_flag  = 1'b0 ;
				alu_op     = 6'd40;
		              end
		        //ebreak		
		        12'h1:begin  //good trap
			        idu_reg_we = 1'b0 ; 
                                break_flag = 1'b1 ;
		                ecall_flag = 1'b0 ;
		                csr_wr_flag= 1'b0 ;
				mret_flag  = 1'b0 ;	
				alu_op     = 6'd24;
		                //goodtrap_dpi();
		              end
		        12'h2:begin  //bad trap 
                                idu_reg_we = 1'b0 ;
			        break_flag = 1'b1 ;
		                ecall_flag = 1'b0 ;
		                csr_wr_flag= 1'b0 ;
				mret_flag  = 1'b0 ;
				alu_op     = 6'd24;
		                //badtrap_dpi();
		              end
		      12'h302:begin  //mret
                                idu_reg_we = 1'b0 ;
		                break_flag = 1'b0 ;
                                ecall_flag = 1'b0 ;
				csr_wr_flag= 1'b0 ;
			        mret_flag  = 1'b1 ;
			        alu_op     = 6'd41;	
		              end 	   
		      default:begin
			        idu_reg_we = 1'b0 ;
		                break_flag = 1'b1 ;
			        ecall_flag = 1'b0 ;
			        csr_wr_flag= 1'b0 ;
				mret_flag  = 1'b0 ;
				alu_op     = 6'd24;
			        //badtrap_dpi();	               
		              end		  
	             endcase
		 //csrrw
		 3'b1:begin 
		        idu_reg_we = 1'b1 ;
	                break_flag = 1'b0 ;
			ecall_flag = 1'b0 ;
		        csr_wr_flag= 1'b1 ;
		        mret_flag  = 1'b0 ;	
			alu_op     = 6'd38;
	              end
	     	//csrrs      
                3'b10:begin
			idu_reg_we = 1'b1 ;
                        break_flag = 1'b0 ;
			ecall_flag = 1'b0 ;
			mret_flag  = 1'b0 ;
			alu_op     = 6'd39;
			if(rs1_addr!=0)
		          csr_wr_flag = 1'b1;
                        else  //csrr
	                  csr_wr_flag = 1'b0;			
		      end
	     default:begin
		      idu_reg_we   = 1'b0 ;
                      break_flag   = 1'b1 ;
		      ecall_flag   = 1'b0 ;
		      csr_wr_flag  = 1'b0 ; 
		      mret_flag    = 1'b0 ; 
		      alu_op       = 6'd24;
	              //badtrap_dpi();
	             end
	    endcase
      end
   //B-type
   7'b1100011: begin
	 idu_reg_we = 1'b0 ;
         mem_we     = 1'b0 ;
         mem_re     = 1'b0 ;
         byte_type  = 2'b0 ;
         sign_type  = 1'b0 ;	       
         load_flag  = 1'b0 ;
	 break_flag = 1'b0 ;          
         csr_wr_flag= 1'b0 ; 
         mret_flag  = 1'b0 ;
         ecall_flag = 1'b0 ;
  
	 case(funct3)  
	     3'h0: alu_op = 6'd25; //beq
             3'h1: alu_op = 6'd26; //bne
             3'h4: alu_op = 6'd27; //blt
	     3'h5: alu_op = 6'd28; //bge
	     3'h6: alu_op = 6'd29; //bltu
	     3'h7: alu_op = 6'd30; //bgeu
	  default: alu_op = 6'd25;
	 endcase
       end    
  default:begin  
            alu_op     = 6'd0 ;
	    idu_reg_we = 1'b0 ;
            mem_we     = 1'b0 ;
            mem_re     = 1'b0 ;
            byte_type  = 2'b0 ;
            sign_type  = 1'b0 ;	       
            load_flag  = 1'b0 ;
	    break_flag = 1'b0 ;
            csr_wr_flag= 1'b0 ; 
            mret_flag  = 1'b0 ;
            ecall_flag = 1'b0 ;
        end
  endcase
end

endmodule

