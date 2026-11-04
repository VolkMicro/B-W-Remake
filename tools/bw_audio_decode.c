/* In-memory MPEG Layer I/II/III decoder used by the Godot port.
 * Protocol: stdin uint32 LE byte count + compressed elementary stream.
 * stdout: "BWAD", uint32 status, sample rate, channels, PCM byte count,
 *         then interleaved signed little-endian 16-bit PCM.
 * No game data is written to disk. Decoder: minimp3 (CC0-1.0).
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif

#define MINIMP3_IMPLEMENTATION
#include "minimp3.h"

#define MAX_INPUT (32u * 1024u * 1024u)
#define MAX_OUTPUT (128u * 1024u * 1024u)

static int write_u32(uint32_t n) {
    unsigned char b[4] = {(unsigned char)n, (unsigned char)(n >> 8),
                          (unsigned char)(n >> 16), (unsigned char)(n >> 24)};
    return fwrite(b, 1, sizeof(b), stdout) == sizeof(b);
}

static int reply(uint32_t status, uint32_t hz, uint32_t channels,
                 const unsigned char *samples, uint32_t length) {
    if (fwrite("BWAD", 1, 4, stdout) != 4 || !write_u32(status) ||
        !write_u32(hz) || !write_u32(channels) || !write_u32(length)) return 1;
    if (length && fwrite(samples, 1, length, stdout) != length) return 1;
    return fflush(stdout) == 0 ? 0 : 1;
}

int main(void) {
#ifdef _WIN32
    _setmode(_fileno(stdin), _O_BINARY);
    _setmode(_fileno(stdout), _O_BINARY);
#endif
    unsigned char size_bytes[4];
    if (fread(size_bytes, 1, 4, stdin) != 4) return reply(1, 0, 0, NULL, 0);
    uint32_t size = (uint32_t)size_bytes[0] | ((uint32_t)size_bytes[1] << 8) |
                    ((uint32_t)size_bytes[2] << 16) | ((uint32_t)size_bytes[3] << 24);
    if (size == 0 || size > MAX_INPUT) return reply(2, 0, 0, NULL, 0);
    unsigned char *input = (unsigned char *)malloc(size);
    if (!input) return reply(3, 0, 0, NULL, 0);
    if (fread(input, 1, size, stdin) != size) {
        free(input);
        return reply(4, 0, 0, NULL, 0);
    }
    mp3dec_t decoder;
    mp3dec_init(&decoder);
    size_t offset = 0, used = 0, capacity = 0;
    unsigned char *output = NULL;
    uint32_t rate = 0, channels = 0, decoded_frames = 0, skipped_bytes = 0;
    while (offset < size) {
        mp3dec_frame_info_t info;
        int16_t pcm[MINIMP3_MAX_SAMPLES_PER_FRAME];
        memset(&info, 0, sizeof(info));
        int count = mp3dec_decode_frame(&decoder, input + offset,
                                        (int)(size - offset), pcm, &info);
        if (info.frame_bytes <= 0) {
            skipped_bytes += (uint32_t)(size - offset);
            break;
        }
        if ((size_t)info.frame_bytes > size - offset) { skipped_bytes++; break; }
        offset += (size_t)info.frame_bytes;
        if (count <= 0) { skipped_bytes += (uint32_t)info.frame_bytes; continue; }
        if ((info.channels != 1 && info.channels != 2) || info.hz <= 0 ||
            (rate && (rate != (uint32_t)info.hz || channels != (uint32_t)info.channels))) {
            free(input); free(output); return reply(5, 0, 0, NULL, 0);
        }
        rate = (uint32_t)info.hz;
        channels = (uint32_t)info.channels;
        size_t bytes = (size_t)count * channels * sizeof(int16_t);
        if (bytes > MAX_OUTPUT - used) {
            free(input); free(output); return reply(6, 0, 0, NULL, 0);
        }
        if (used + bytes > capacity) {
            size_t next = capacity ? capacity : 16384;
            while (next < used + bytes) next *= 2;
            if (next > MAX_OUTPUT) next = MAX_OUTPUT;
            void *expanded = realloc(output, next);
            if (!expanded) { free(input); free(output); return reply(3, 0, 0, NULL, 0); }
            output = (unsigned char *)expanded;
            capacity = next;
        }
        memcpy(output + used, pcm, bytes);
        used += bytes;
        decoded_frames++;
    }
    free(input);
    if (!decoded_frames || !used || skipped_bytes > size / 2) {
        free(output); return reply(7, 0, 0, NULL, 0);
    }
    int rc = reply(0, rate, channels, output, (uint32_t)used);
    free(output);
    return rc;
}
