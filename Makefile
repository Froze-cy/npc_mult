TOPNAME = top
NXDC_FILES = constr/top.nxdc
INC_PATH ?=


VERILATOR = verilator
VERILATOR_CFLAGS += -MMD --build -cc \
                                -Wall \
                                -O3 \
                                --x-assign fast \
				--x-initial fast \
                                --assert \
			        -Wno-fatal \
			        -Wno-LATCH  \
				--trace	    \
				--LDFLAGS "-ldl"	
	                       
        			
        			
        			
# VERILATOR_FLAGS = -Wall --cc --exe --build
# VERILATOR_TRACE_FLAG = --trace

BUILD_DIR = ./build
OBJ_DIR = $(BUILD_DIR)/obj_dir
BIN = $(BUILD_DIR)/$(TOPNAME)

default: $(BIN)

$(shell mkdir -p $(BUILD_DIR))

# constraint file
SRC_AUTO_BIND = $(abspath $(BUILD_DIR)/auto_bind.cpp)
$(SRC_AUTO_BIND): $(NXDC_FILES)
	python3 $(NVBOARD_HOME)/scripts/auto_pin_bind.py $^ $@

# project source
VSRCS = $(shell find $(abspath ./vsrc) -name "*.v")
CSRCS = $(shell find $(abspath ./csrc) -name "*.c" -or -name "*.cc" -or -name "*.cpp")
# CSRCS += $(SRC_AUTO_BIND)

# SRC_V = ./vsrc/test1.v
# SRC_CPP = ./csrc/test1_sim.cpp

# rules for NVBoard
include $(NVBOARD_HOME)/scripts/nvboard.mk

# rules for verilator
INCFLAGS = $(addprefix -I, $(INC_PATH))
CXXFLAGS += $(INCFLAGS) -DTOP_NAME="\"V$(TOPNAME)\"" -g -O0

$(BIN):	$(VSRCS) $(CSRCS) $(NVBOARD_ARCHIVE)
	@rm -rf $(OBJ_DIR)
	$(VERILATOR) $(VERILATOR_CFLAGS) \
        	--top-module $(TOPNAME) $^ \
        	$(addprefix -CFLAGS , $(CXXFLAGS)) $(addprefix -LDFLAGS , $(LDFLAGS)) \
        	--Mdir $(OBJ_DIR) --exe -o $(abspath $(BIN))
all: default	
        	  
run: $(BIN)
	@$(BIN) $(BINFILE) $(if $(DIFF),--diff $(DIFF)) $(if $(filter on,$(TRACE)),--trace)

wave:	$(VSRCS) $(CSRCS)
	$(VERILATOR) $(VERILATOR_FLAGS) $(VERILATOR_TRACE_FLAGS) \
        	--top-module top \
        	-o $(TOPNAME)_wave
	@mv obj_dir/$(TOPNAME)_wave .
	@echo "Running simulation with waveform generation.."
	./$(TOPNAME)_wave
	@echo "Waveform saved to $(TOPNAME)_wave.vcd"

clean: 
	rm -rf $(BUILD_DIR) 

sim:
	$(call git_commit, "sim RTL") # DO NOT REMOVE THIS LINE!!!
	@echo "Write this Makefile by your self."

.PHONY:default all run 

include ../Makefile
