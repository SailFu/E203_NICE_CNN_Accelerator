#ifndef __INSN_H__
#define __INSN_H__

#include <hbird_sdk_soc.h>

#define  ROW_LEN    3
#define  COL_LEN    3

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


// custom mul_load
__STATIC_FORCEINLINE void custom_mul_load(int addr1, int addr2)
{
    asm volatile (
        ".insn r 0x7b, 1, 1, x0, %0, %1"
        :
        : "r"(addr1), "r"(addr2)
    );
}



// normal test case without NICE accelerator.
int normal_case(unsigned int array[ROW_LEN][COL_LEN]);

// teat case using NICE accelerator.
int nice_case(unsigned int array[ROW_LEN][COL_LEN]);

void nice_mul(int array1[4][4], int array2[4][3]);


#endif

