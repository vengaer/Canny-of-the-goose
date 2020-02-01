#define STB_IMAGE_IMPLEMENTATION
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "asm.h"
#include "stb_image.h"
#include "stb_image_write.h"

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>

#include <argp.h>
#include <regex.h>
#include <unistd.h>

#define DEFAULT_OUTFILE "data/cotg_out.png"

static regex_t float_rgx;

char const *argp_program_version = "canny-of-the-goose 1.0";
char const *argp_program_bug_address = "<vilhelm.engstrom@tuta.io>";

static char doc[] = "cotg (Canny of the Goose) -- Canny edge detection";
static char args_doc[] = "";

static struct argp_option options[] = {
    {"infile",  'i', "IMAGE",          0, "Specify infile (required)", 0 },
    {"outfile", 'o', "OUT",            0, "Specify file to save image to", 0 },
    {"high",    'h', "HIGH_THRESHOLD", 0, "High threshold", 0 },
    {"low",     'l', "LOW_THRESHOLD",  0, "Low threshold", 0 },
    { 0 }
};

struct arguments {
    char const *infile, *outfile;
    float high, low;
};

static error_t parse_opt(int key, char *arg, struct argp_state *state) {
    struct arguments *args = state->input;
    switch(key) {
        case 'i':
            args->infile = arg;
            break;
        case 'o':
            args->outfile = arg;
            break;
        case 'h':
            if(regexec(&float_rgx, arg, 0, NULL, 0)) {
                fprintf(stderr, "%s is not a floating point\n", arg);
                return ARGP_ERR_UNKNOWN;
            }
            args->high = atof(arg);
            break;
        case 'l':
            if(regexec(&float_rgx, arg, 0, NULL, 0)) {
                fprintf(stderr, "%s is not a floating point\n", arg);
                return ARGP_ERR_UNKNOWN;
            }
            args->low = atof(arg);
            break;
        default:
            return ARGP_ERR_UNKNOWN;
    }
    return 0;
}

static inline bool thresholds_valid(struct arguments const *args) {
    if(args->low < 0.f) {
        fputs("Low threshold must be positive\n", stderr);
        return false;
    }
    if(args->high > 1.f) {
        fputs("High threshold may not be larger than 1.0\n", stderr);
        return false;
    }
    if(args->low >= args->high) {
        fputs("Low threshold must be smaller than high threshold\n", stderr);
        return false;
    }
    return true;
}

static struct argp argp = { options, parse_opt, args_doc, doc, 0, 0, 0 };

int main(int argc, char **argv) {
    struct arguments args = {
        .infile = NULL,
        .outfile = DEFAULT_OUTFILE,
        .high = 0.5f,
        .low = 0.05f
    };

    if(regcomp(&float_rgx, "^[0-9]+(\\.[0-9]*f?)?$", REG_EXTENDED)) {
        fputs("Failed to compile float regex\n", stderr);
        return 1;
    }

    argp_parse(&argp, argc, argv, 0, 0, &args);
    if(!args.infile) {
        fputs("No infile specified\n", stderr);
        return 1;
    }
    if(access(args.infile, F_OK)) {
        perror("Error accessing infile");
        return 1;
    }
    if(!thresholds_valid(&args)) {
        return 1;
    }
    int width, height, channels;
    unsigned char *texdata = NULL;
    printf("Reading infile %s\n", args.infile);
    texdata = stbi_load(args.infile, &width, &height, &channels, 0);
    if(!texdata) {
        fputs("Failed to load image\n", stderr);
        return 1;
    }

    printf("%-20s%dx%d\n", "Image dims:", width, height);

    int color_cvt_status = rgb2grayscale(texdata, width, height, &channels);
    if(color_cvt_status) {
        fprintf(stderr, "Color conversion failed: %d\n", color_cvt_status);
        stbi_image_free(texdata);
        return 1;
    }
    printf("%-20s%d\n", "Color cvt:", color_cvt_status);

    int blur_status = gaussblur(texdata, width, height);
    if(blur_status) {
        fprintf(stderr, "Blur failed: %d\n", blur_status);
        stbi_image_free(texdata);
        return 1;
    }
    printf("%-20s%d\n", "Blur:", blur_status);

    int edge_status = edgedetect(texdata, &width, &height);
    if(edge_status) {
        fprintf(stderr, "Edge detection failed: %d\n", edge_status);
        stbi_image_free(texdata);
        return 1;
    }
    printf("%-20s%d\n", "Edge detection:", edge_status);

    dbl_threshold(texdata, width, height, args.low, args.high);
    printf("%-20s%d\n", "Double threshold:", 0); /* Cannot fail */

    int hysteresis_status = hysteresis(texdata, width, height);
    if(hysteresis_status) {
        fprintf(stderr, "Edge tracking failed: %d\n", hysteresis_status);
        stbi_image_free(texdata);
        return 1;
    }
    printf("%-20s%d\n", "Edge tracking:", hysteresis_status);

    printf("Writing outfile %s\n", args.outfile);
    stbi_write_png(args.outfile, width, height, channels, texdata, width * sizeof(unsigned char));
    stbi_image_free(texdata);

	return 0;
}
