#include "filter.h"
#include <stdlib.h>
#include <stdio.h>

#define MAX(x,y) x < y ? y : x
#define MIN(x,y) x < y ? x : y

static float gauss_weights[] = { 0.028532, 0.067234, 0.124009, 0.179044, 0.20236, 0.179044, 0.124009, 0.067234, 0.028532 };

int cgaussblur(uint8_t *data, int32_t width, int32_t height) {
    
    uint8_t *tmp = malloc(width * height);
    if(!tmp) {
        return 1;
    }

    float sum;
    int idx;
    for(int i = 0; i < height; i++) {
        for(int j = 4; j < width - 4; j++) {
            sum = 0.f;
            idx = i * width + j;
            for(int k = -4; k <= 4; k++) {
                sum += data[idx + k] * gauss_weights[k + 4];
            }
            tmp[idx] = sum;
        }
    }

    for(int i = 4; i < height - 4; i++) {
        for(int j = 0; j < width; j++) {
            sum= 0.f;
            idx = i * width + j;
            for(int k = -4; k <=4; k++) {
                sum += tmp[idx + k * width] * gauss_weights[k + 4];
            }
            data[idx] = sum;
        }
    }
    free(tmp);
    return 0;
}
