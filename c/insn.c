#include "insn.h"
#include <stdio.h>

#include "data.h"


void conv1_cal(int8_t input[14][14], int8_t kernel[3][3], int32_t output[12][12]) 
{
    for (int i = 0; i < 12; i++) 
    {
        for (int j = 0; j < 12; j++) 
        {
            int32_t sum = 0;
            for (int k = 0; k < 3; k++) 
                for (int l = 0; l < 3; l++) 
                    sum += (int32_t)input[i + k][j + l] * (int32_t)kernel[k][l];
            output[i][j] = sum;
        }
    }
}


void conv2_cal(int8_t input[6][6], int8_t kernel[3][3], int32_t output[4][4]) 
{
    for (int i = 0; i < 4; i++) 
    {
        for (int j = 0; j < 4; j++) 
        {
            int32_t sum = 0;
            for (int k = 0; k < 3; k++) 
                for (int l = 0; l < 3; l++) 
                    sum += (int32_t)input[i + k][j + l] * (int32_t)kernel[k][l];
            output[i][j] += sum;
        }
    }
}


int8_t pool(int8_t in1, int8_t in2, int8_t in3, int8_t in4)
{
    int8_t max = in1;
    if (in2 > max) max = in2;
    if (in3 > max) max = in3;
    if (in4 > max) max = in4;
    return max;
}

int8_t pool_relu(int8_t in1, int8_t in2, int8_t in3, int8_t in4, int8_t bias)
{
    int8_t max = in1;
    if (in2 > max) max = in2;
    if (in3 > max) max = in3;
    if (in4 > max) max = in4;
    max = max + bias; // add bias
    if (max < 0) max = 0;
    return max;
}

int8_t quant_conv1(int32_t in)
{
    int32_t tmp;
    tmp = (in << 5);      // in * 32
    tmp = tmp + (in << 1); // + in * 2
    tmp = tmp + in;       // + in * 1
    // => tmp = in * 35
    tmp = tmp >> 9;      // 相当于 / 512
    tmp = tmp + conv1_zero_point; // add zero point
    tmp = tmp > 127 ? 127 : tmp; // saturate to 127
    tmp = tmp < -128 ? -128 : tmp; // saturate to -128
    return (int8_t)tmp;
}

int8_t quant_conv2(int32_t in)
{
    int32_t tmp;
    tmp     = (in << 7)  // in *128
            + (in << 3) // in *8
            + (in << 2) // in *4
            + (in << 1) // in *2
            + in;        // in *1
    // out_val = tmp64 / 1024 => >> 10
    tmp = tmp >> 10;
    tmp = tmp + conv1_zero_point; // add zero point
    tmp = tmp > 127 ? 127 : tmp; // saturate to 127
    tmp = tmp < -128 ? -128 : tmp; // saturate to -128
    return (int8_t)tmp;
}

int8_t quant_fc1(int32_t in)
{
    // 1) 先乘以 75
    //    75 = 64 + 8 + 2 + 1
    int32_t tmp = (in << 6)    // in_val * 64
                + (in << 3)   // + in_val * 8
                + (in << 1)   // + in_val * 2
                +  in;                 // + in_val * 1
    // 2) 右移 8 位 => 除以 256
    //    如果需要“向最近整数舍入”，可加 (1 << 7) 再右移。这里只做截断。
    tmp = (tmp >> 8);
    tmp = tmp + fc1_zero_point; // add zero point
    tmp = tmp > 127 ? 127 : tmp; // saturate to 127
    tmp = tmp < -128 ? -128 : tmp; // saturate to -128
    return (int8_t)tmp;
}

int normal_cnn(int8_t input[28][28])
{
    // pool 1
    printf("pool 1\n");
    volatile int8_t pool1[14][14] = {0};
    for (int i = 0; i < 14; i++)
        for (int j = 0; j < 14; j++)
            pool1[i][j] = pool(input[i*2][j*2], input[i*2][j*2+1], input[i*2+1][j*2], input[i*2+1][j*2+1]);

    // conv 1
    printf("conv 1\n");
    volatile int32_t output[5][12][12] = {0};
    for (int n = 0; n < 5; n++)
        conv1_cal(pool1, conv1[n][0], output[n]);

    // pool 2 + quant
    printf("pool 2\n");
    volatile int8_t pool2[5][6][6] = {0};
    for (int n = 0; n < 5; n++)
        for (int i = 0; i < 6; i++)
            for (int j = 0; j < 6; j++)
                pool2[n][i][j] = quant_conv1(pool_relu(output[n][i*2][j*2], output[n][i*2][j*2+1], output[n][i*2+1][j*2], output[n][i*2+1][j*2+1], conv1_bias[n]));
    
    // conv 2
    printf("conv 2\n");
    volatile int32_t output2[5][4][4] = {0};
    for (int n = 0; n < 5; n++)
        for (int i = 0; i < 5; i++)
            conv2_cal(pool2[n], conv2[i][n], output2[i]);

    // pool 3 + quant
    printf("pool 3\n");
    volatile int8_t pool3[5][2][2] = {0};
    for (int n = 0; n < 5; n++)
        for (int i = 0; i < 2; i++)
            for (int j = 0; j < 2; j++)
                pool3[n][i][j] = quant_conv2(pool_relu(output2[n][i*2][j*2], output2[n][i*2][j*2+1], output2[n][i*2+1][j*2], output2[n][i*2+1][j*2+1], conv2_bias[n]));

    // fc 1
    printf("fc 1\n");
    volatile int8_t flat[20];
    int idx = 0;
    for (int j = 0; j < 5; j++)
        for (int k = 0; k < 2; k++)
            for (int l = 0; l < 2; l++)
                flat[idx++] = pool3[j][k][l];
    
    volatile int32_t fc1_out[10] = {0};
    for (int i = 0; i < 10; i++) {
        volatile int32_t sum = 0;
        for (int j = 0; j < 20; j++)
            sum += fc1[i][j] * flat[j];
        fc1_out[i] = sum + fc1_bias[i];
    }
         
    // quant
    printf("quant\n");
    volatile int8_t fc1_out_quant[10] = {0};
    for (int i = 0; i < 10; i++)
        fc1_out_quant[i] = quant_fc1(fc1_out[i]);

    // fc 2
    printf("fc 2\n");
    volatile int32_t fc2_out[10] = {0};
    for (int i = 0; i < 10; i++) {
        volatile int32_t sum = 0;
        for (int j = 0; j < 10; j++)
            sum += fc2[i][j] * fc1_out_quant[j];
        fc2_out[i] = sum;
    }

    // print result
    for (int i = 0; i < 10; i++) {
        printf("%d ", fc2_out[i]);
    }

}


void nice_conv(int input[ROWS][COLS], int kernels[NUM_KERNELS][KERNEL_SIZE][KERNEL_SIZE], int output[NUM_KERNELS][OUT_ROWS][OUT_COLS])
{
    custom_load_conv1((uintptr_t)kernels[0][0]);

    custom_load_input((uintptr_t)input[0]);

    custom_start((uintptr_t)output[0][0]);
    
}

