#ifndef ASM_H
#define ASM_H

#include <stdint.h>

extern int rgb2grayscale(uint8_t *data, int32_t width, int32_t height, int32_t *channels);
extern int gaussblur(uint8_t *data, int32_t width, int32_t height);
extern int edgedetect(uint8_t *data, int32_t *width, int32_t *height);

#endif
