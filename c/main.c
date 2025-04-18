
#include <stdio.h>
#include <time.h>
#include <stdlib.h>
#include <stdint.h>
#include "hbird_sdk_soc.h"

#include "insn.h"
#include "data.h"

void conv_comp();

int main(void)
{
    printf("\n*************************************************\n");
    printf("****** begin to test the NICE accelerator *******\n");
    printf("*************************************************\n");

    //conv_comp();

    // for (int i = 0; i < 10; i++)
    // {
    //     int res = normal_cnn(&mnist_imgs_uint8[i*784]);
    //     if (mnist_labels[i]  == res)
    //         printf("Test %d: Pass\n", i);
    //     else
    //         printf("Test %d: Fail, expected %d, got %d\n", i, mnist_labels[i], res);
    // }
    
    nice_cnn(&mnist_imgs_uint8[0*784]);

    printf("\n**************************************************\n");
    printf("******** end of test the NICE accelerator ********\n");
    printf("**************************************************\n\n");

    return 0;
}


void conv_comp()
{
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
        {   {  1,  2, -1 },
            {  2,  -1, -2 },
            {  1,  6, -1 }
        },
        {   {  1,  2,  1 },
            {  3,  0,  0 },
            { -1, -2, -1 }
        },
        {   {  0, -1,  9 },
            { -1,  5, -1 },
            {  -7, -1,  0 }
        },
        {   {  1,  1,  1 },
            {  1,  1,  1 },
            {  1,  1,  1 }
        }
    };

    int output_matrix_normal[NUM_KERNELS][OUT_ROWS][OUT_COLS] = {0};
    int output_matrix_nice[NUM_KERNELS][OUT_ROWS][OUT_COLS] = {0};

    begin_instret  =  __get_rv_instret();
    begin_cycle    =  __get_rv_cycle();

    // Normal convolution without NICE accelerator
    normal_conv(input_matrix, kernels, output_matrix_normal);

    end_instret    = __get_rv_instret();
    end_cycle      = __get_rv_cycle();

    instret_normal = end_instret - begin_instret;
    cycle_normal   = end_cycle - begin_cycle;

    begin_instret  =  __get_rv_instret();
    begin_cycle    =  __get_rv_cycle();

    // NICE accelerator convolution
    nice_conv(input_matrix, kernels, output_matrix_nice);

    end_instret    = __get_rv_instret();
    end_cycle      = __get_rv_cycle();

    instret_nice   = end_instret - begin_instret;
    cycle_nice     = end_cycle - begin_cycle;
    
    printf("\nNormal instret: %d, cycle: %d \n", instret_normal, cycle_normal);
    printf("\nNICE instret: %d, cycle: %d \n", instret_nice, cycle_nice); 

    int correct_cnt = 0;
    for (int n = 0; n < NUM_KERNELS; n++) {
        for (int i = 0; i < OUT_ROWS; i++) {
            for (int j = 0; j < OUT_COLS; j++) {
                if (output_matrix_normal[n][i][j] == output_matrix_nice[n][i][j])
                    correct_cnt++;
            }
        }
    }
    if (correct_cnt == NUM_KERNELS * OUT_ROWS * OUT_COLS) {
        printf("\nAll results are correct!\n");
    } else {
        printf("\nResults are incorrect! Errors count: %d\n", NUM_KERNELS * OUT_ROWS * OUT_COLS - correct_cnt);
    }

    // for (int n = 0; n < NUM_KERNELS; n++) 
    // {
    //     printf("\nConvlolution Output %d (12*12):\n", n);
    //     for (int i = 0; i < OUT_ROWS; i++) {
    //         for (int j = 0; j < OUT_COLS; j++) {
    //             printf("%6d ", output_matrix[n][i][j]);
    //         }
    //         printf("\n");
    //     }
    // }
}


