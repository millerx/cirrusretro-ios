#ifndef CIRRUS_VGM_H
#define CIRRUS_VGM_H
#include "cirrus_music.h"

/* Validate the command stream and determine the single selection's frame limit. */
const char *cr_validate_vgm(const uint8_t *b, size_t size, cr_music_info *info);
#endif
