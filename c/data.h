#ifndef __DATA_H__
#define __DATA_H__

#include <stdint.h>


extern uint8_t input_zp;

extern int8_t conv1_weight[45];
extern uint8_t conv1_weight_zp;
extern int32_t conv1_bias[5];
// conv1_scale = 1/510 => to uint8
extern uint8_t conv1_out_zp;

extern int8_t conv2_weight[225];
extern uint8_t conv2_weight_zp;
extern int32_t conv2_bias[5];
// conv2_scale = 1/216 => to uint8
extern uint8_t conv2_out_zp;

extern int8_t fc1_weight[200];
extern uint8_t fc1_weight_zp;
extern int32_t fc1_bias[10];
// fc1_scale = 1/206 => to uint8
extern uint8_t fc1_out_zp;

extern int8_t fc2_weight[100];
extern uint8_t fc2_weight_zp;
extern int32_t fc2_bias[10];
// fc2_scale = 1/11 => to uint8
extern uint8_t fc2_out_zp;


extern int8_t mnist_labels[10];
extern uint8_t mnist_imgs_uint8[7840];


#endif
