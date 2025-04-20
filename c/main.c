
#include <stdio.h>
#include <time.h>
#include <stdlib.h>
#include <stdint.h>
#include "hbird_sdk_soc.h"

#include "insn.h"
#include "data.h"

void conv_comp();
void nice(int test_num);
void normal(int test_num);


int main(void)
{
    printf("\n*************************************************\n");
    printf("****** begin to test the NICE accelerator *******\n");
    printf("*************************************************\n");
    
    int test_num = 1;

    nice(test_num);
    normal(test_num);

    printf("\n**************************************************\n");
    printf("******** end of test the NICE accelerator ********\n");
    printf("**************************************************\n\n");

    return 0;
}


void nice(int test_num)
{
    unsigned int begin_instret, end_instret, instret_nice;
    unsigned int begin_cycle,   end_cycle,   cycle_nice;

    nice_load_weights();

    int correct_cnt = 0;

    for (int i = 0; i < test_num; i++)
    {
        begin_instret  =  __get_rv_instret();
        begin_cycle    =  __get_rv_cycle();

        int res = nice_cnn(&mnist_imgs_uint8[i*784]);

        end_instret    = __get_rv_instret();
        end_cycle      = __get_rv_cycle();

        instret_nice   = end_instret - begin_instret;
        cycle_nice     = end_cycle - begin_cycle;
        
        printf("\nNICE instret: %d, cycle: %d \n", instret_nice, cycle_nice); 

        if (mnist_labels[i] == res)
        {
            printf("Test %d: Pass, Result: %d\n", i+1, res);
            correct_cnt++;
        }
        else
            printf("Test %d: Fail, expected %d, got %d\n", i+1, mnist_labels[i], res);
    }
    if (correct_cnt == test_num)
        printf("\nNICE All Passed!\n");
    else
        printf("\nNICE Results are incorrect! Errors count: %d\n", test_num - correct_cnt);
}


void normal(int test_num)
{
    unsigned int begin_instret, end_instret, instret_normal;
    unsigned int begin_cycle,   end_cycle,   cycle_normal;

    int correct_cnt = 0;

    for (int i = 0; i < test_num; i++)
    {
        begin_instret  =  __get_rv_instret();
        begin_cycle    =  __get_rv_cycle();

        int res = normal_cnn(&mnist_imgs_uint8[i*784]);

        end_instret    = __get_rv_instret();
        end_cycle      = __get_rv_cycle();

        instret_normal = end_instret - begin_instret;
        cycle_normal   = end_cycle - begin_cycle;

        printf("\nNormal instret: %d, cycle: %d \n", instret_normal, cycle_normal);

        if (mnist_labels[i] == res)
        {
            printf("Test %d: Pass, Result: %d\n", i+1, res);
            correct_cnt++;
        }
        else
            printf("Test %d: Fail, expected %d, got %d\n", i+1, mnist_labels[i], res);
    }
    if (correct_cnt == test_num)
        printf("\nNormal All Passed!\n");
    else
        printf("\nNormal Results are incorrect! Errors count: %d\n", test_num - correct_cnt);
}

