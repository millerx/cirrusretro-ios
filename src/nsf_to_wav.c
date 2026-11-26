#include "cirrus_nsf.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *open_input(const char *path, cr_nsf **nsf)
{
    FILE *in = fopen(path, "rb");
    if (!in)
        return "cannot open input";
    const char *error = "input must be a seekable file within the NSF size limit";
    if (fseek(in, 0, SEEK_END) == 0) {
        long size = ftell(in);
        if (size > 0 && size <= CR_NSF_MAX_BYTES && fseek(in, 0, SEEK_SET) == 0) {
            uint8_t *data = malloc((size_t)size);
            if (!data)
                error = "out of memory";
            else if (fread(data, 1, (size_t)size, in) != (size_t)size ||
                     fgetc(in) != EOF || ferror(in))
                error = "could not read complete input";
            else
                error = cr_nsf_open(data, (size_t)size, nsf);
            free(data);
        }
    }
    fclose(in);
    return error;
}

static void put16(uint8_t *out, uint16_t n)
{
    out[0] = (uint8_t)n;
    out[1] = (uint8_t)(n >> 8);
}

static void put32(uint8_t *out, uint32_t n)
{
    put16(out, (uint16_t)n);
    put16(out + 2, (uint16_t)(n >> 16));
}

static const char *write_wave(FILE *out, cr_nsf *nsf, uint32_t frames)
{
    enum { block = 1024, stride = CR_NSF_CHANNELS * 2 };
    uint32_t bytes = frames * stride;
    uint8_t header[44] = {0};
    memcpy(header, "RIFF", 4);
    put32(header + 4, 36 + bytes);
    memcpy(header + 8, "WAVEfmt ", 8);
    put32(header + 16, 16);
    put16(header + 20, 1);
    put16(header + 22, CR_NSF_CHANNELS);
    put32(header + 24, CR_NSF_RATE);
    put32(header + 28, CR_NSF_RATE * stride);
    put16(header + 32, stride);
    put16(header + 34, 16);
    memcpy(header + 36, "data", 4);
    put32(header + 40, bytes);
    if (fwrite(header, 1, sizeof header, out) != sizeof header)
        return "cannot write WAV header";

    int16_t pcm[block * CR_NSF_CHANNELS];
    uint8_t encoded[block * stride];
    while (frames) {
        unsigned count = frames < block ? frames : block;
        const char *error = cr_nsf_render(nsf, pcm, count);
        if (error)
            return error;
        for (unsigned i = 0; i < count * CR_NSF_CHANNELS; ++i)
            put16(encoded + 2 * i, (uint16_t)pcm[i]);
        if (fwrite(encoded, stride, count, out) != count)
            return "cannot write WAV data";
        frames -= count;
    }
    return NULL;
}

static int positive_number(const char *s, unsigned max, unsigned *out)
{
    if (!*s || strspn(s, "0123456789") != strlen(s))
        return 0;
    unsigned long n = strtoul(s, NULL, 10);
    if (!n || n > max)
        return 0;
    *out = (unsigned)n;
    return 1;
}

int main(int argc, char **argv)
{
    unsigned seconds = 3, track = 0;
    if (argc < 3 || argc > 5 ||
        (argc >= 4 && !positive_number(argv[3], 3600, &seconds)) ||
        (argc == 5 && !positive_number(argv[4], 255, &track))) {
        fprintf(stderr, "Usage: nsf-to-wav INPUT.nsf NEW.wav [SECONDS 1..3600 [TRACK 1..255]]\n");
        return 2;
    }

    cr_nsf *nsf = NULL;
    const char *error = open_input(argv[1], &nsf);
    cr_nsf_info info;
    if (!error)
        error = cr_nsf_get_info(nsf, &info);
    if (!error)
        error = cr_nsf_select(nsf, track ? track - 1 : info.default_track);
    if (!error) {
        FILE *out = fopen(argv[2], "wbx");
        if (!out)
            error = "cannot create output (use a new file)";
        else {
            error = write_wave(out, nsf, (uint32_t)seconds * CR_NSF_RATE);
            if (fclose(out) != 0)
                error = "could not finish writing WAV";
            if (error && remove(argv[2]) != 0)
                fprintf(stderr, "could not remove incomplete WAV\n");
        }
    }
    cr_nsf_close(nsf);
    if (error)
        fprintf(stderr, "nsf-to-wav: %s\n", error);
    return error ? 1 : 0;
}
