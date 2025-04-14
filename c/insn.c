#include "insn.h"
#include <stdio.h>
 
// normal test case without NICE accelerator.
int normal_case(unsigned int array[ROW_LEN][COL_LEN])
{
  volatile unsigned char i=0, j=0;
  volatile unsigned int col_sum[COL_LEN]={0};
  volatile unsigned int row_sum[ROW_LEN]={0};
  volatile unsigned int tmp=0;
  for (i = 0; i < ROW_LEN; i++)
  {
    tmp = 0;
    for (j = 0; j < COL_LEN; j++)
    {
      col_sum[j] += array[i][j];
      tmp += array[i][j];
    }
    row_sum[i] = tmp;
  }
  return 0;
}

// test case using NICE accelerator.
int nice_case(unsigned int array[ROW_LEN][COL_LEN])
{
  volatile unsigned char i, j;
  volatile unsigned int col_sum[COL_LEN]={0};
  volatile unsigned int row_sum[ROW_LEN]={0};
  volatile unsigned int init_buf[3]={0};

  custom_lbuf((int)init_buf);
  for (i = 0; i < ROW_LEN; i++)
  {
    row_sum[i] = custom_rowsum((int)array[i]);
  }
  custom_sbuf((int)col_sum);
  return 0;
}


void conv2d(int input[ROWS][COLS], int kernel[KERNEL_SIZE][KERNEL_SIZE], int output[OUT_ROWS][OUT_COLS]) 
{
    for (int i = 0; i < OUT_ROWS; i++) 
    {
        for (int j = 0; j < OUT_COLS; j++) 
        {
            int sum = 0;
            for (int k = 0; k < KERNEL_SIZE; k++) 
                for (int l = 0; l < KERNEL_SIZE; l++) 
                    sum += input[i + k][j + l] * kernel[k][l];
            output[i][j] = sum;
        }
    }
}

void normal_conv(int input[ROWS][COLS], int kernels[NUM_KERNELS][KERNEL_SIZE][KERNEL_SIZE], int output[NUM_KERNELS][OUT_ROWS][OUT_COLS]) 
{
    for (int n = 0; n < NUM_KERNELS; n++)
        conv2d(input, kernels[n], output[n]);

    #ifdef DEBUG_INFO
    printf("Input Matrix (14*14):\n");
    for (int i = 0; i < ROWS; i++) {
        for (int j = 0; j < COLS; j++) {
            printf("%4d ", input[i][j]);
        }
        printf("\n");
    }

    for (int n = 0; n < NUM_KERNELS; n++) {
        printf("\nConvolution Kernel %d (3*3):\n", n);
        for (int i = 0; i < KERNEL_SIZE; i++) {
            for (int j = 0; j < KERNEL_SIZE; j++) {
                printf("%4d ", kernels[n][i][j]);
            }
            printf("\n");
        }
        printf("\nConvlolution Output %d (12*12):\n", n);
        for (int i = 0; i < OUT_ROWS; i++) {
            for (int j = 0; j < OUT_COLS; j++) {
                printf("%6d ", output[n][i][j]);
            }
            printf("\n");
        }
    }
    #endif
}


void nice_conv(int input[ROWS][COLS], int kernels[NUM_KERNELS][KERNEL_SIZE][KERNEL_SIZE], int output[NUM_KERNELS][OUT_ROWS][OUT_COLS])
{
    custom_load_conv1((uintptr_t)kernels[0][0]);

    custom_load_input((uintptr_t)input[0]);

    custom_start((uintptr_t)output[0][0]);
    
}



void nice_mul(int matrix_A[4][4], int matrix_B[4][3], int matrix_C[4][3])
{
    custom_mul_loada((uintptr_t)matrix_A[0]);
    custom_mul_loadb((uintptr_t)matrix_B[0]);

    // printf("matrix_A address: %p\n", (void*)matrix_A[0]);
    // printf("matrix_B address: %p\n", (void*)matrix_B[0]);

    custom_mul_cals((uintptr_t)matrix_C[0]);

}

