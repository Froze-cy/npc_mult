#include <stdio.h>
#include <stdint.h>
#include <time.h>
#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vtop.h"
#include <nvboard.h>
#include <iomanip>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <dlfcn.h>
#include "Vtop___024root.h"


#define SERIAL_ADDR    0x10000000   //串口地址
#define RTC_ADDR_LO    0x10000004   //实时时钟地址
#define RTC_ADDR_HI    0x10000008  
#define UPTIME_ADDR_LO 0x10000010
#define UPTIME_ADDR_HI 0x10000014

////////////////////////////////////DiffTest/////////////////////////////////////
// 定义与 NEMU 完全一致的 CPU 状态结构体
struct CPU_state {
  uint32_t gpr[32];
  uint32_t pc;
};

// 方向常量（与 NEMU 的 difftest-def.h 保持一致）
#ifndef DIFFTEST_TO_REF
#define DIFFTEST_TO_REF 1 
#define DIFFTEST_TO_DUT 0
#endif

// 定义 paddr_t 类型（用于内存地址）
typedef uint32_t paddr_t;

// 声明函数指针类型
typedef void (*difftest_memcpy_t)(paddr_t addr, void *buf, size_t n, bool direction);
typedef void (*difftest_regcpy_t)(void *dut, bool direction);
typedef void (*difftest_exec_t)(uint64_t n);

/////////////////////////////////////////////////////////////////////////////////
static Vtop dut;
static VerilatedVcdC* tfp = nullptr;

static uint8_t pmem[128*1024*1024] __attribute__((aligned(64)));
//static VerilatedVcdC* tfp = new VerilatedVcdC;

// 用于 DiffTest 对比的全局状态
static CPU_state npc_state;
static bool difftest_enabled = false;
static void *nemu_handle = NULL;
static difftest_memcpy_t difftest_memcpy = NULL;
static difftest_regcpy_t difftest_regcpy = NULL;
static difftest_exec_t difftest_exec = NULL;

//保存最后一条 add 指令信息（用于调试，可保留）
static struct {
   bool valid ;
   uint32_t pc ;
   uint32_t inst ;
   uint32_t rd_addr ;
   uint32_t expected ;
} last_add = {0,0,0,0,0};

//退出码
static int exit_code = 0;
static bool trap_hit = false;

uint32_t global_a0 = 0 ;
uint32_t current_pc ;
uint32_t curr_inst  ;
void nvboard_bind_all_pins( Vtop* top);

//DPI 函数：goodtrap（程序正确结束）
extern "C" void goodtrap_dpi(){
  printf("\n\033[1;32mEBREAK GOOD TRAP VIA DPI\033[0m\n");
  exit_code = 0;
  trap_hit = true;          // 设置标志
  Verilated::gotFinish(true);
};

//DPI 函数：badtrap（程序错误结束）
extern "C" void badtrap_dpi(){
  printf("\n\033[1;31mEBREAK BAD TRAP VIA DPI\033[0m\n");
  exit_code = 1;
  trap_hit = true;          // 设置标志
  Verilated::gotFinish(true);
};

//单周期运行
static void single_cycle() {
  dut.clk = 0; dut.eval();Verilated::timeInc(5);
  if(tfp) tfp->dump(Verilated::time());
  dut.clk = 1; dut.eval();Verilated::timeInc(5);
  if(tfp) tfp->dump(Verilated::time());

}

//复位
static void reset(int n) {
  dut.rst_n = 0;
  while (n -- > 0) single_cycle();
  dut.rst_n = 1;
}

//从二进制文件加载程序到内存指定基址
void load_image(const char* filename,uint32_t base = 0x80000000){
    FILE* fp = fopen(filename,"rb");
    if(!fp){
       printf("Failed to open %s \n",filename);
       return ;
    }
    fseek(fp,0,SEEK_END);
    long size = ftell(fp);
    fseek(fp,0,SEEK_SET);
    size_t read_size = fread(&pmem[base& 0x7FFFFFFF],1,size,fp); //假设pmem从0开始映射
    fclose(fp);
    printf("Loaded %ld bytes to physical address 0x%08x \n",size,base);
}


//DPI-C pmem_read
extern "C" int pmem_read(int raddr){
         
       	uint32_t addr = (uint32_t)raddr;
       //获取当前时间
        struct timespec ts;
	uint64_t us;
        //处理UPTIME低32位
        if(addr == UPTIME_ADDR_LO){
	  
         clock_gettime(CLOCK_MONOTONIC,&ts);
	 us = ts.tv_sec * 1000000ULL + ts.tv_nsec / 1000 ;
         return 0;
	 //返回低32位
	 //return (int)(us & 0xFFFFFFFF);
	}
        //处理UPTIME高32位
        if(addr == UPTIME_ADDR_HI){
	 clock_gettime(CLOCK_MONOTONIC,&ts);
	 us = ts.tv_sec * 1000000ULL + ts.tv_nsec / 1000 ;
    	 return 0;
	 //返回高32位
	 //return (int)(us >> 32);      
	}
        //处理RTC低32位
        if(addr == RTC_ADDR_LO){
	  
         clock_gettime(CLOCK_REALTIME,&ts);
	 us = ts.tv_sec * 1000000ULL + ts.tv_nsec / 1000 ;
         return 0;
	 //返回低32位
	 //return (int)(us & 0xFFFFFFFF);
	}
        //处理RTC高32位
        if(addr == RTC_ADDR_HI){

	 clock_gettime(CLOCK_REALTIME,&ts);
	 us = ts.tv_sec * 1000000ULL + ts.tv_nsec / 1000 ;
         return 0;
	 //返回高32位
	 //return (int)(us >> 32);      
	}


        //物理地址 = raddr & ~0x3u （总是4字节对齐）
        uint32_t paddr = addr & ~0x3u;
	if(addr>=0x80000000&&addr<(0x80000000+sizeof(pmem))){
	   uint32_t offset = paddr - 0x80000000;
	   uint32_t val = *(uint32_t*)&pmem[offset];
 
	   return val;

	}
        else {
	/*   if(paddr !=0 ){
	       printf("ERROR: pmem_read out of range: 0x%08x, PC = 0x%08x, inst = 0x%08x\n",paddr,current_pc,curr_inst);
	   
	   }*/
	
	return 0;
	}
}
/*
//DPI-C pmem_write
extern "C" void pmem_write(int waddr, int wdata, char wmask) {
    uint32_t addr = (uint32_t)waddr;
    // 处理串口等 MMIO 地址（如果有）
    if (addr == SERIAL_ADDR) {
        // 输出字符
        for (int i = 0; i < 4; i++) {
            if (wmask & (1 << i)) {
                putchar((char)(wdata >> (i * 8)));
                fflush(stdout);
            }
        }
        return;
    }
    // 其他 MMIO 地址可以在这里添加

    uint32_t paddr = addr & ~0x3u;
    if (paddr >= 0x80000000 && paddr < 0x80000000 + sizeof(pmem)) {
        uint32_t offset = paddr - 0x80000000;
        uint32_t* word = (uint32_t*)&pmem[offset];
        uint32_t old = *word;
        uint32_t new_val = old;
        for (int i = 0; i < 4; i++) {
            if (wmask & (1 << i)) {
	//new_val = (new_val & ~(0xFF << (i*8))) | ((wdata >> (i*8)) & 0xFF) << (i*8);
            uint8_t byte;
            //判断是 sw (wmask 全1) 还是 sb (只有一位为1)
            if (wmask == 0xF) { // sw：使用 wdata 的对应字节
                    byte = (uint8_t)((wdata >> (i*8)) & 0xFF);
            } else { // sb：始终使用 wdata 的低 8 位
                    byte = (uint8_t)(wdata & 0xFF);
            }
              new_val = (new_val & ~(0xFF << (i*8))) | (byte << (i*8));       
	    }
        }
        *word = new_val;
    }
}*/

extern "C" void pmem_write(int waddr, int wdata, char wmask) {
    uint32_t addr = (uint32_t)waddr;
    if (addr == SERIAL_ADDR) {
        for (int i = 0; i < 4; i++) {
            if (wmask & (1 << i)) {
                putchar((char)(wdata >> (i * 8))); // 串口输出仍按原方式（因为串口写通常字节）
                fflush(stdout);
            }
        }
        return;
    }

    uint32_t paddr = addr & ~0x3u;
    if (paddr >= 0x80000000 && paddr < 0x80000000 + sizeof(pmem)) {
        uint32_t offset = paddr - 0x80000000;
        uint32_t* word = (uint32_t*)&pmem[offset];

        if (wmask == 0xF) {
            *word = wdata;
        } else {
            // 找到连续字节区域的起始和长度
            int first = -1;
            int len = 0;
            for (int i = 0; i < 4; i++) {
                if (wmask & (1 << i)) {
                    if (first == -1) first = i;
                    len++;
                } else if (first != -1) {
                    break; // 假设只有一段连续区域
                }
            }
            uint32_t old = *word;
            uint32_t new_val = old;
            for (int i = 0; i < len; i++) {
                int byte_pos = first + i;
                uint8_t byte = (uint8_t)((wdata >> (i * 8)) & 0xFF);
                new_val = (new_val & ~(0xFF << (byte_pos * 8))) | (byte << (byte_pos * 8));
            }
            *word = new_val;
        }
    }
}


//寄存器名称映射
const char* get_reg_name(int reg_num){
  static const char* names[32] = {
    "zeros","ra","sp","gp","tp","t0","t1","t2",
    "s0","s1","a0","a1","a2","a3","a4","a5",
    "a6","a7","s2","s3","s4","s5","s6","s7",
    "s8","s9","s10","s11","t3","t4","t5","t6"
    };
    return(reg_num>=0&&reg_num<=32)?names[reg_num]:"unknown" ;

}

//读取寄存器
uint32_t get_debug_reg(int reg_num){
     dut.debug_addr = reg_num;
     dut.eval();
     return dut.debug_reg;

}
//直接读取寄存器
uint32_t get_reg_direct(int index) {
    return dut.rootp->top__DOT__regfile_inst__DOT__registers[index];
}

// 初始化 DiffTest（加载 NEMU 动态库）
bool init_difftest(const char *ref_so) {
    nemu_handle = dlopen(ref_so, RTLD_LAZY);
    if (!nemu_handle) {
        fprintf(stderr, "Failed to open REF SO %s: %s\n", ref_so, dlerror());
        return false;
    }

    difftest_memcpy = (difftest_memcpy_t)dlsym(nemu_handle, "difftest_memcpy");
    difftest_regcpy = (difftest_regcpy_t)dlsym(nemu_handle, "difftest_regcpy");
    difftest_exec = (difftest_exec_t)dlsym(nemu_handle, "difftest_exec");
    if (!difftest_memcpy || !difftest_regcpy || !difftest_exec) {
        fprintf(stderr, "Failed to get DiffTest symbols: %s\n", dlerror());
        dlclose(nemu_handle);
        nemu_handle = NULL;
        return false;
    }

    printf("DiffTest enabled with REF SO: %s\n", ref_so);
    return true;
}

//////////////////////////////////////////////////////////////////////////////////////

int main(int argc, char** argv) {

      Verilated::commandArgs(argc,argv);
      if(argc < 2){
         printf("Usage: %s <binary file>\n",argv[0]);
	 return 1;
      }
      //解析命令行参数：获取镜像文件名和可选的 --diff 参数和--trace 参数
      const char *image_file = NULL;
      const char *diff_so = NULL;
      bool trace_enabled = false;
      //解析TRACE
      for (int i = 1; i < argc; i++) {
        if (strncmp(argv[i], "--diff=", 7) == 0) {
            diff_so = argv[i] + 7;
        } else if (strcmp(argv[i], "--diff") == 0 && i + 1 < argc) {
            diff_so = argv[i + 1];
            i++;
        } else if (strcmp(argv[i], "--trace") == 0) {   // 新增：识别 --trace
            trace_enabled = true;
        } else if (image_file == NULL) {
            image_file = argv[i];
        }
      }
      //解析DIFF
      for (int i = 1; i < argc; i++) {
        if (strncmp(argv[i], "--diff=", 7) == 0) {
            diff_so = argv[i] + 7;
        } else if (strcmp(argv[i], "--diff") == 0 && i + 1 < argc) {
            diff_so = argv[i + 1];
            i++; // 跳过下一个参数
        } else if (image_file == NULL) {
            image_file = argv[i];
        }
      }

      if (!image_file) {
        printf("Usage: %s [--diff <ref_so>] <binary file>\n", argv[0]);
        return 1;
      }

     // 根据是否有 diff_so 决定是否启用 DiffTest
      if (diff_so) {
        if (init_difftest(diff_so)) {
            difftest_enabled = true;
        } else {
            printf("Warning: DiffTest initialization failed, running without comparison.\n");
            difftest_enabled = false;
        }
   } else {
        printf("DiffTest disabled (no --diff given).\n");
        difftest_enabled = false;
     } 
    //根据trace_enabled决定是否启用波形
    if (trace_enabled) {
        Verilated::traceEverOn(true);
        tfp = new VerilatedVcdC;
        dut.trace(tfp, 99);
        tfp->open("wave.vcd");
        printf("Waveform enabled: wave.vcd\n");
    }
    else {
        tfp = nullptr;
    }    
    //绑定引脚
    //nvboard_bind_all_pins(&dut);

    //初始化
    //nvboard_init();

   
    //加载程序到内存
    load_image(argv[1],0x80000000); 

    //复位
    reset(5);
    //如果 DiffTest 启用，将 NPC 的初始状态同步给 NEMU
    if (difftest_enabled) {
        // 拷贝整个内存
        difftest_memcpy(0x80000000, pmem, sizeof(pmem), DIFFTEST_TO_REF);
        // 获取 NPC 初始寄存器状态（使用直接读取函数）
        for (int i = 0; i < 32; i++) {
            npc_state.gpr[i] = get_debug_reg(i);
        }
        npc_state.pc = dut.curr_pc;
        difftest_regcpy(&npc_state, DIFFTEST_TO_REF);
        printf("Initial state synchronized to NEMU.\n");
    }


    uint32_t prev_pc = dut.curr_pc;
    int same_pc_count= 0;
    int cycle = 0; 
    vluint64_t sim_time = 0;
    uint32_t last_pc = 0;
    uint32_t last_inst = 0;    
    
    while(!Verilated::gotFinish()){
        //保存当前指令作为上一条
        last_pc = dut.curr_pc;
        last_inst = dut.inst;

	single_cycle();
        current_pc = dut.curr_pc ;
	curr_inst  = dut.inst    ;
	global_a0  = get_debug_reg(10);
        cycle++;

        if (trap_hit) break;   // 触发 ebreak 后立即退出循环
        static uint32_t last_s0 = 0,last_s1 = 0,last_x15 = 0; 
        uint32_t s0 = get_debug_reg(8);
        uint32_t s1 = get_debug_reg(9);
        uint32_t x15 = get_debug_reg(15);
     
     if (difftest_enabled) {

        if(dut.diff_flag) {		
            // 获取 NPC 当前寄存器状态
            for (int i = 0; i < 32; i++) {
                npc_state.gpr[i] = get_debug_reg(i);
            }
            npc_state.pc = dut.curr_pc;

            // 让 NEMU 执行一条指令
            difftest_exec(1);

            // 获取 NEMU 的寄存器状态
            CPU_state ref_state;
            difftest_regcpy(&ref_state, DIFFTEST_TO_DUT);

            // 对比
            bool mismatch = false;
            if (npc_state.pc != ref_state.pc) {
                printf("\n[DiffTest] PC mismatch at cycle %d: NPC=0x%08x, REF=0x%08x\n",cycle, npc_state.pc, ref_state.pc);
                mismatch = true;
            } else {
                for (int i = 0; i < 32; i++) {
                    if (npc_state.gpr[i] != ref_state.gpr[i]) {
                        printf("\n[DiffTest] Reg x%d (%s) mismatch at cycle %d: NPC=0x%08x, REF=0x%08x\n",
                               i, get_reg_name(i), cycle, npc_state.gpr[i], ref_state.gpr[i]);
                        mismatch = true;
                        break;
                    }
                }
            }
            if (mismatch) {
		printf("Previous instruction: PC=0x%08x, instruction=0x%08x\n", last_pc, last_inst);
                printf("Current instruction: PC=0x%08x, instruction=0x%08x\n", dut.curr_pc, dut.inst);

        	exit_code = 1;
                break;   // 停止仿真
            }
         }
      }


        // 简单的 PC 停滞检测（可选）
        if (dut.curr_pc == prev_pc) {
            same_pc_count++;
            if (same_pc_count > 10) {
                printf("\n PC stuck at 0x%08x for %d cycles. Stopping!\n", dut.curr_pc, same_pc_count);
                exit_code = 1;
                break;
            }
        } else {
            same_pc_count = 0;
            prev_pc = dut.curr_pc;
        }	
      /* if(cycle > 1000000){
          printf("\n\033[1;33mTimeout after %d cycles\033[0m\n",cycle);
	  exit_code = 1;
	  break;
      }*/
   }

   // 关闭波形
   if (tfp) {
     tfp->close();
     delete tfp;
   }
   //仿真结束，关闭动态库  
   if (nemu_handle) dlclose(nemu_handle);
 
   //最终状态
   printf("\n=====================================================\n");
   printf("Total cycles: %d\n", cycle);
   printf("PC: 0x%08x\n",dut.curr_pc);
   printf("Instruction: 0x%08x \n",dut.inst);
   printf("\n Final register values: \n");
   
   for(int i = 0; i < 32;i++){
      uint32_t val = get_reg_direct(i);
      if(val!=0){
         printf("x%02d = 0x%08x \n",i,val);
      }
   }
    
 
 /*  while(1){
     
     nvboard_update();

     single_cycle();

    }*/ 
   
    return exit_code;
   
}
