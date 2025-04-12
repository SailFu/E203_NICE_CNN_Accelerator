
#include <stdio.h>
#include <time.h>
#include <stdlib.h>
#include "hbird_sdk_soc.h"

#include "insn.h"

int main(void)
{
    printf("\n***********************************************\n");
    printf("***** begin to test the NICE accelerator ******\n");
    printf("***********************************************\n\n");

    unsigned int begin_instret, end_instret, instret_normal, instret_nice;
    unsigned int begin_cycle,   end_cycle,   cycle_normal,   cycle_nice;

    int input_matrix[ROWS][COLS];
    int value = 1;
    for (int i = 0; i < ROWS; i++)
        for (int j = 0; j < COLS; j++)
            input_matrix[i][j] = value++;

    int kernels[NUM_KERNELS][KERNEL_SIZE][KERNEL_SIZE] = {
        {   {  1,  1,  0 },
            {  1, -4,  1 },
            {  0,  1,  0 }
        },
        {   {  1,  0, -1 },
            {  2,  0, -2 },
            {  1,  0, -1 }
        },
        {   {  1,  2,  1 },
            {  0,  0,  0 },
            { -1, -2, -1 }
        },
        {   {  0, -1,  0 },
            { -1,  5, -1 },
            {  0, -1,  0 }
        },
        {   {  1,  1,  1 },
            {  1,  1,  1 },
            {  1,  1,  1 }
        }
    };

    int output_matrix[NUM_KERNELS][OUT_ROWS][OUT_COLS] = {0};

    begin_instret  =  __get_rv_instret();
    begin_cycle    =  __get_rv_cycle();

    //normal_conv(input_matrix, kernels, output_matrix);
    nice_conv(input_matrix, kernels, output_matrix);

    end_instret    = __get_rv_instret();
    end_cycle      = __get_rv_cycle();

    instret_nice   = end_instret - begin_instret;
    cycle_nice     = end_cycle - begin_cycle;

    printf("\nNICE instret: %d, cycle: %d \n", instret_nice, cycle_nice); 

    // instret_normal   = end_instret - begin_instret;
    // cycle_normal     = end_cycle - begin_cycle;

    // printf("\nNormal instret: %d, cycle: %d \n", instret_normal, cycle_normal); 


    printf("\n**************************************************\n");
    printf("******** end of test the NICE accelerator ********\n");
    printf("**************************************************\n\n");

    return 0;
}
