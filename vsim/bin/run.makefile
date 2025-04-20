RUN_DIR      := ${PWD}

#TB_NAME      := tb_systolic_array_4_4
TB_NAME      := tb_top

TESTCASE     := ${RUN_DIR}/../../riscv-tools/riscv-tests/isa/generated/rv32ui-p-addi
DUMPWAVE     := 1

SMIC130LL    := 0
GATE_SIM     := 0
GATE_SDF     := 0
GATE_NOTIME  := 0

VSRC_DIR     := ${RUN_DIR}/../install/rtl
VTB_DIR      := ${RUN_DIR}/../install/tb
TESTNAME     := $(notdir $(patsubst %.dump,%,${TESTCASE}.dump))
TEST_RUNDIR  := ${TESTNAME}

# 收集 RTL 文件：分别查找 .v 和 .sv 文件（支持多级目录）
RTL_V_FILES  := $(wildcard ${VSRC_DIR}/*/*.v) $(wildcard ${VSRC_DIR}/*/*.sv) $(wildcard ${VSRC_DIR}/*/*/*.v) $(wildcard ${VSRC_DIR}/*/*/*.sv)
# 收集 TB 文件：同时支持 .v 和 .sv 文件
TB_V_FILES   := $(wildcard ${VTB_DIR}/*.v) $(wildcard ${VTB_DIR}/*.sv)

SIM_TOOL      := vcs

# 仿真工具选项配置
ifeq ($(SIM_TOOL),vcs)
SIM_OPTIONS   := +v2k -sverilog -q +lint=all,noSVA-NSVU,noVCDE,noUI,noSVA-CE,noSVA-DIU  -debug_access+all -full64 -timescale=1ns/10ps
SIM_OPTIONS   += +incdir+"${VSRC_DIR}/core/"+"${VSRC_DIR}/perips/"+"${VSRC_DIR}/perips/apb_i2c/"
endif
ifeq ($(SIM_TOOL),iverilog)
SIM_OPTIONS   := -o vvp.exec -I "${VSRC_DIR}/core/" -I "${VSRC_DIR}/perips/" -I "${VSRC_DIR}/perips/apb_i2c/" -D DISABLE_SV_ASSERTION=1 -g2005-sv
endif

ifeq ($(SMIC130LL),1) 
SIM_OPTIONS   += +define+SMIC130_LL
endif
ifeq ($(GATE_SIM),1) 
SIM_OPTIONS   += +define+GATE_SIM  +lint=noIWU,noOUDPE,noPCUDPE
endif
ifeq ($(GATE_SDF),1) 
SIM_OPTIONS   += +define+GATE_SDF
endif
ifeq ($(GATE_NOTIME),1) 
SIM_OPTIONS   += +nospecify +notimingcheck 
endif
ifeq ($(GATE_SDF_MAX),1) 
SIM_OPTIONS   += +define+SIM_MAX
endif
ifeq ($(GATE_SDF_MIN),1) 
SIM_OPTIONS   += +define+SIM_MIN
endif

# 设置仿真执行命令
ifeq ($(SIM_TOOL),vcs)
SIM_EXEC      := ${RUN_DIR}/simv +ntb_random_seed_automatic
endif
ifeq ($(SIM_TOOL),iverilog)
SIM_EXEC      := vvp ${RUN_DIR}/vvp.exec -lxt2	
endif

# 设置波形查看工具及选项
ifeq ($(SIM_TOOL),vcs)
WAV_TOOL := verdi
endif
ifeq ($(SIM_TOOL),iverilog)
WAV_TOOL := gtkwave
endif

ifeq ($(WAV_TOOL),verdi)
WAV_OPTIONS   := +v2k -sverilog
endif
ifeq ($(WAV_TOOL),gtkwave)
WAV_OPTIONS   := 
endif

ifeq ($(SMIC130LL),1) 
WAV_OPTIONS   += +define+SMIC130_LL
endif
ifeq ($(GATE_SIM),1) 
WAV_OPTIONS   += +define+GATE_SIM  
endif
ifeq ($(GATE_SDF),1) 
WAV_OPTIONS   += +define+GATE_SDF
endif

ifeq ($(WAV_TOOL),verdi)
WAV_INC      := +incdir+"${VSRC_DIR}/core/"+"${VSRC_DIR}/perips/"+"${VSRC_DIR}/perips/apb_i2c/"
endif
ifeq ($(WAV_TOOL),gtkwave)
WAV_INC      := 
endif

ifeq ($(WAV_TOOL),verdi)
WAV_RTL      := ${RTL_V_FILES} ${TB_V_FILES}
endif
ifeq ($(WAV_TOOL),gtkwave)
WAV_RTL      := 
endif

ifeq ($(WAV_TOOL),verdi)
WAV_FILE      := -ssf ${TEST_RUNDIR}/${TB_NAME}.fsdb
endif
ifeq ($(WAV_TOOL),gtkwave)
WAV_FILE      := ${TEST_RUNDIR}/${TB_NAME}.vcd
endif

# 判断测试平台文件后缀：如果同时存在 .sv，则优先使用 .sv，否则使用 .v
TB_FILE_EXT := v
ifneq ($(wildcard ${VTB_DIR}/${TB_NAME}.sv),)
TB_FILE_EXT := sv
endif

# 编译阶段：插入宏定义，并调用仿真工具进行编译
compile.flg: ${RTL_V_FILES} ${TB_V_FILES}
	@-rm -f compile.flg
	# 在 TB 文件顶部插入定义，用于区分仿真工具
	sed -i '1i`define ${SIM_TOOL}' ${VTB_DIR}/${TB_NAME}.${TB_FILE_EXT}
	${SIM_TOOL} ${SIM_OPTIONS}  ${RTL_V_FILES} ${TB_V_FILES} ;
	touch compile.flg

compile: compile.flg 

wave: 
	# 同时打开日志和波形文件
	gvim -p ${TESTCASE}.spike.log ${TESTCASE}.dump &
	${WAV_TOOL} ${WAV_OPTIONS} ${WAV_INC} ${WAV_RTL} ${WAV_FILE}  & 

run: compile
	@rm -rf ${TEST_RUNDIR}
	mkdir ${TEST_RUNDIR}
	cd ${TEST_RUNDIR}; ${SIM_EXEC} +DUMPWAVE=${DUMPWAVE} +TESTCASE=${TESTCASE} +SIM_TOOL=${SIM_TOOL} 2>&1 | tee ${TESTNAME}.log; cd ${RUN_DIR}; 

.PHONY: run clean all
