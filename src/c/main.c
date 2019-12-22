#define STB_IMAGE_IMPLEMENTATION
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "asm.h"
#include "stb_image.h"
#include "stb_image_write.h"

#include <stdio.h>

#include <argp.h>
#include <unistd.h>

#define DEFAULT_OUTFILE "cotg_out.png"

char const *argp_program_version = "canny-of-the-goose 1.0";
char const *argp_program_bug_address = "<vilhelm.engstrom@tuta.io>";

static char doc[] = "canny-of-the-goose -- Canny edge detection";
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
    texdata = stbi_load(args.infile, &width, &height, &channels, 0);
    if(!texdata) {
        fputs("Failed to load image\n", stderr);
        return 1;
    }

    printf("%d: %d\n", height, rgb2grayscale(texdata, width, height, &channels));
    printf("%d\n", channels);

	return 0;
}
