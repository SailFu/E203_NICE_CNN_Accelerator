#ifndef __INSN_H__
#define __INSN_H__

#include <hbird_sdk_soc.h>

#define  ROW_LEN    3
#define  COL_LEN    3

#define ROWS 14
#define COLS 14
#define KERNEL_SIZE 3
#define OUT_ROWS (ROWS - KERNEL_SIZE + 1)
#define OUT_COLS (COLS - KERNEL_SIZE + 1)
#define NUM_KERNELS 5

//#define DEBUG_INFO


////////////////////////////////////////////////////////////
// custom3:
// Supported format: only R type here
// Supported instr:
//  1. custom3 lbuf: load data(in memory) to row_buf
//     lbuf (a1)
//     .insn r opcode, func3, func7, rd, rs1, rs2    
//  2. custom3 sbuf: store data(in row_buf) to memory
//     sbuf (a1)
//     .insn r opcode, func3, func7, rd, rs1, rs2    
//  3. custom3 acc rowsum: load data from memory(@a1), accumulate row datas and write back 
//     rowsum rd, a1, x0
//     .insn r opcode, func3, func7, rd, rs1, rs2    
////////////////////////////////////////////////////////////

// custom lbuf 
__STATIC_FORCEINLINE void custom_lbuf(int addr)
{
    int zero = 0;
    asm volatile (
       ".insn r 0x7b, 2, 1, x0, %1, x0"
           :"=r"(zero)
           :"r"(addr)
     );
}

// custom sbuf 
__STATIC_FORCEINLINE void custom_sbuf(int addr)
{
    int zero = 0;
    asm volatile (
       ".insn r 0x7b, 2, 2, x0, %1, x0"
           :"=r"(zero)
           :"r"(addr)
     );
}

// custom rowsum 
__STATIC_FORCEINLINE int custom_rowsum(int addr)
{
    int rowsum;
    asm volatile (
       ".insn r 0x7b, 6, 6, %0, %1, x0"
             :"=r"(rowsum)
             :"r"(addr)
     );
    
    return rowsum; 
}

// custom mul_loada
__STATIC_FORCEINLINE void custom_mul_loada(uintptr_t addr)
{
    int zero = 0;
    asm volatile (
        ".insn r 0x7b, 2, 8, x0, %1, x0"
        : "=r"(zero)
        : "r"(addr)
    );
}

// custom mul_loadb
__STATIC_FORCEINLINE void custom_mul_loadb(uintptr_t addr)
{
    int zero = 0;
    asm volatile (
        ".insn r 0x7b, 2, 9, x0, %1, x0"
        : "=r"(zero)
        : "r"(addr)
    );
}

// custom mul_cals
__STATIC_FORCEINLINE void custom_mul_cals(uintptr_t st_addr)
{
    int zero = 0;
    asm volatile (
        ".insn r 0x7b, 2, 10, x0, %1, x0"
        : "=r"(zero)
        : "r"(st_addr)
    );
}


__STATIC_FORCEINLINE void custom_load_conv1(uintptr_t addr)
{
    int zero = 0;
    asm volatile (
        ".insn r 0x7b, 2, 11, x0, %1, x0"
        : "=r"(zero)
        : "r"(addr)
    );
}

__STATIC_FORCEINLINE void custom_load_input(uintptr_t addr)
{
    int zero = 0;
    asm volatile (
        ".insn r 0x7b, 2, 12, x0, %1, x0"
        : "=r"(zero)
        : "r"(addr)
    );
}

__STATIC_FORCEINLINE void custom_start(uintptr_t addr)
{
    int zero = 0;
    asm volatile (
        ".insn r 0x7b, 2, 13, x0, %1, x0"
        : "=r"(zero)
        : "r"(addr)
    );
}


// normal test case without NICE accelerator.
int normal_case(unsigned int array[ROW_LEN][COL_LEN]);

// teat case using NICE accelerator.
int nice_case(unsigned int array[ROW_LEN][COL_LEN]);


void normal_conv(int input[ROWS][COLS], int kernels[NUM_KERNELS][KERNEL_SIZE][KERNEL_SIZE], int output[NUM_KERNELS][OUT_ROWS][OUT_COLS]);


void nice_mul(int matrix_A[4][4], int matrix_B[4][3], int matrix_C[4][3]);


#endif

