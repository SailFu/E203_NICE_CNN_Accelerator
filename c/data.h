#ifndef __DATA_H__
#define __DATA_H__

#include <stdint.h>

extern int8_t conv1[5][1][3][3];
extern int8_t conv1_bias[5];
extern int8_t conv1_zero_point;

extern int8_t conv2[5][5][3][3];
extern int8_t conv2_bias[5];
extern int8_t conv2_zero_point;

extern int8_t fc1[10][20];
extern int8_t fc1_bias[10];
extern int8_t fc1_zero_point;

extern int8_t fc2[10][10];


extern int8_t mnist_labels[10];
extern int8_t mnist_imgs_int8[7840];

#endif
