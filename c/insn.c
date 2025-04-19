#include "insn.h"
#include <stdio.h>

#include "data.h"


void conv1_cal(uint8_t input[14][14], const int8_t kernel[3][3], int32_t output[12][12], uint8_t input_zp, uint8_t weight_zp, int32_t conv_bias) 
{
    for (int i = 0; i < 12; i++) 
    {
        for (int j = 0; j < 12; j++) 
        {
            int32_t sum = 0;
            for (int k = 0; k < 3; k++) 
                for (int l = 0; l < 3; l++) 
                    sum += (int32_t)((int32_t)input[i + k][j + l] - (int32_t)input_zp) * ((int32_t)kernel[k][l] - (int32_t)weight_zp);
            printf("%d ", sum);
            output[i][j] = sum + conv_bias;
            //printf("%d ", output[i][j]);
        }
    }
}


void conv2_cal(uint8_t input[6][6], const int8_t kernel[3][3], int32_t output[4][4], uint8_t input_zp, uint8_t weight_zp, int32_t conv_bias, int n) 
{
    for (int i = 0; i < 4; i++) 
    {
        for (int j = 0; j < 4; j++) 
        {
            int32_t sum = 0;
            for (int k = 0; k < 3; k++) 
                for (int l = 0; l < 3; l++) 
                    sum += (int32_t)((int32_t)input[i + k][j + l] - (int32_t)input_zp) * ((int32_t)kernel[k][l] - (int32_t)weight_zp);
            output[i][j] += sum;
            if (n==0) output[i][j] += conv_bias;
        }
    }
}


uint8_t pool1_cal(uint8_t in1, uint8_t in2, uint8_t in3, uint8_t in4)
{
    uint8_t max = in1;
    if (in2 > max) max = in2;
    if (in3 > max) max = in3;
    if (in4 > max) max = in4;
    return max;
}

int32_t pool23_cal(int32_t in1, int32_t in2, int32_t in3, int32_t in4)
{
    int32_t max = in1;
    if (in2 > max) max = in2;
    if (in3 > max) max = in3;
    if (in4 > max) max = in4;
    return max;
}

static inline uint8_t clamp_u8(int32_t x)
{
    return (uint8_t)( x <   0 ?   0 :
                      x > 255 ? 255 : x );
}

/*------------------------------------------------------------
 * 1) conv1  :  scale = 1/510  ≈  (1 + 1/256) / 512
 *              推导:  (acc + acc/256) >> 9
 *-----------------------------------------------------------*/
uint8_t quant_conv1(int32_t acc_int32, uint8_t zp_out)
{
    /* (1 + 1/256) 部分 →  acc + (acc>>8) */
    int32_t tmp = acc_int32 + (acc_int32 >> 8);
    /* 除以 512  →  >> 9  */
    int32_t y   = (tmp >> 9) + (int32_t)zp_out;
    return clamp_u8(y);
}

/*------------------------------------------------------------
 * 2) conv2  :  scale = 1/216  ≈ 1/256 + 1/1024 − 1/4096
 *              推导:  (acc>>8) + (acc>>10) - (acc>>12)
 *-----------------------------------------------------------*/
uint8_t quant_conv2(int32_t acc_int32, uint8_t zp_out)
{
    int32_t y =  (acc_int32 >> 8)     /* 1/256  */
               + (acc_int32 >> 10)    /* 1/1024 */
               - (acc_int32 >> 12);   /* 1/4096 */
    y += (int32_t)zp_out;
    return clamp_u8(y);
}

/*------------------------------------------------------------
 * 3) fc1    :  scale = 1/206  ≈ 1/256 + 1/1024
 *              推导:  (acc>>8) + (acc>>10)
 *              绝对误差 < 0.6 %
 *-----------------------------------------------------------*/
uint8_t quant_fc1(int32_t acc_int32, uint8_t zp_out)
{
    int32_t y =  (acc_int32 >> 8)     /* 1/256  */
               + (acc_int32 >> 10);   /* 1/1024 */
    y += (int32_t)zp_out;
    return clamp_u8(y);
}

uint8_t relu(uint8_t in, uint8_t zp)
{
    return in < zp ? zp : in;
}


int normal_cnn(uint8_t input[28][28])
{
    // pool 1
    volatile uint8_t pool1[14][14] = {0};
    for (int i = 0; i < 14; i++)
        for (int j = 0; j < 14; j++)
        {
            pool1[i][j] = pool1_cal(input[i*2][j*2], input[i*2][j*2+1], input[i*2+1][j*2], input[i*2+1][j*2+1]);
            //printf("%d ", pool1[i][j]);
        }
    // conv 1
    volatile int32_t output[5][12][12] = {0};
    for (int n = 0; n < 5; n++)
    {
        const int8_t (*ker)[3] = (int8_t (*)[3])&conv1_weight[n * 9];
        conv1_cal(pool1, ker, output[n], input_zp, conv1_weight_zp, conv1_bias[n]);
    }
        

    // pool 2 + quant
    volatile uint8_t pool2[5][6][6] = {0};
    for (int n = 0; n < 5; n++)
        for (int i = 0; i < 6; i++)
            for (int j = 0; j < 6; j++)
            {    
                pool2[n][i][j] = relu(quant_conv1(pool23_cal(output[n][i*2][j*2], output[n][i*2][j*2+1], output[n][i*2+1][j*2], output[n][i*2+1][j*2+1]), conv1_out_zp), conv1_out_zp);
                printf("%d ", pool2[n][i][j]);
            }
    
    // conv 2
    volatile int32_t output2[5][4][4] = {0};
    for (int out = 0; out < 5; out++)
        for (int in = 0; in < 5; in++)
        {
            const int8_t (*ker)[3] = (int8_t (*)[3])&conv2_weight[((out * 5) + in) * 9];
            conv2_cal(pool2[in], ker, output2[out], conv1_out_zp, conv2_weight_zp, conv2_bias[out], in);
        }

    // pool 3 + quant
    volatile uint8_t pool3[5][2][2] = {0};
    for (int n = 0; n < 5; n++)
        for (int i = 0; i < 2; i++)
            for (int j = 0; j < 2; j++)
            {
                pool3[n][i][j] = relu(quant_conv2(pool23_cal(output2[n][i*2][j*2], output2[n][i*2][j*2+1], output2[n][i*2+1][j*2], output2[n][i*2+1][j*2+1]), conv2_out_zp), conv2_out_zp);
                //printf("%d ", pool3[n][i][j]);
            }

    // fc 1
    volatile uint8_t flat[20];
    int idx = 0;
    for (int j = 0; j < 5; j++)
        for (int k = 0; k < 2; k++)
            for (int l = 0; l < 2; l++)
                flat[idx++] = pool3[j][k][l];
    
    volatile int32_t fc1_out[10] = {0};
    for (int i = 0; i < 10; i++) {
        volatile int32_t sum = 0;
        for (int j = 0; j < 20; j++)
            sum += (int32_t)((int32_t)fc1_weight[i*20+j] - (int32_t)fc1_weight_zp) * ((int32_t)flat[j] - (int32_t)conv2_out_zp);
        fc1_out[i] = sum + fc1_bias[i];
    }
         
    // quant
    volatile uint8_t fc1_out_quant[10] = {0};
    for (int i = 0; i < 10; i++)
        fc1_out_quant[i] = quant_fc1(fc1_out[i], fc1_out_zp);

    // fc 2
    volatile int32_t fc2_out[10] = {0};
    for (int i = 0; i < 10; i++) {
        volatile int32_t sum = 0;
        for (int j = 0; j < 10; j++)
            sum += (int32_t)((int32_t)fc2_weight[i*10+j] - (int32_t)fc2_weight_zp) * ((int32_t)fc1_out_quant[j] - (int32_t)fc1_out_zp);
        fc2_out[i] = sum + fc2_bias[i];
    }

    // print result
    for (int i = 0; i < 10; i++) {
        printf("%d ", fc2_out[i]);
    }
    volatile int32_t max_out = fc2_out[0];
    volatile int max_idx = 0;
    for (int i = 1; i < 10; i++) {
        if (fc2_out[i] > max_out) {
            max_out = fc2_out[i];
            max_idx = i;
        }
    }
    printf("\nResult: %d\n", max_idx);
    return max_idx;
}


int nice_cnn(uint8_t input[784])
{
    int result;
    custom_load_conv1((uintptr_t)conv1_weight);
    custom_load_conv2((uintptr_t)conv2_weight);
    custom_load_fc1((uintptr_t)fc1_weight);
    custom_load_fc2((uintptr_t)fc2_weight);
    custom_load_input((uintptr_t)input);
    return 0;
}

