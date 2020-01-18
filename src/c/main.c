#define STB_IMAGE_IMPLEMENTATION
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "asm.h"
#include "stb_image.h"
#include "stb_image_write.h"

#include <stdio.h>

#include <argp.h>
#include <unistd.h>

#define DEFAULT_OUTFILE "data/cotg_out.png"

char const *argp_program_version = "canny-of-the-goose 1.0";
char const *argp_program_bug_address = "<vilhelm.engstrom@tuta.io>";

static char doc[] = "cotg (Canny of the Goose) -- Canny edge detection";
static char args_doc[] = "";

static struct argp_option options[] = {
    {"infile",  'i', "IMAGE", 0, "Specify infile (required)", 0 },
    {"outfile", 'o', "OUT",   0, "Specify file to save image to", 0 },
    { 0 }
};

struct arguments {
    char const *infile, *outfile;
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
        default:
            return ARGP_ERR_UNKNOWN;
    }
    return 0;
}

static struct argp argp = { options, parse_opt, args_doc, doc, 0, 0, 0 };

int main(int argc, char **argv) {
    struct arguments args = {
        .infile = NULL,
        .outfile = DEFAULT_OUTFILE
    };

    argp_parse(&argp, argc, argv, 0, 0, &args);
    if(!args.infile) {
        fputs("No infile specified\n", stderr);
        return 1;
    }
    if(access(args.infile, F_OK)) {
        perror("Error accessing infile");
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

    int edge_status = sobel(texdata, &width, &height);
    if(edge_status) {
        fprintf(stderr, "Edge detection failed: %d\n", edge_status);
        stbi_image_free(texdata);
        return 1;
    }
    printf("%-20s%d\n", "Edge detection:", edge_status);

    printf("Writing outfile %s\n", args.outfile);
    stbi_write_png(args.outfile, width, height, channels, texdata, width * sizeof(unsigned char));
    stbi_image_free(texdata);

	return 0;
}
