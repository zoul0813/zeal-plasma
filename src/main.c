#include <stdio.h>
#include <stdint.h>

#include <zos_sys.h>
#include <zos_vfs.h>
#include <zos_video.h>
#include <zvb_hardware.h>

#define SCREEN_COL80_WIDTH  80
#define SCREEN_COL80_HEIGHT 40
#define COLUMNS             80
#define ROWS                40

uint8_t charcodes[] = {
    254,249,250,46,
    254,249,250,46,
    254,249,250,46,
    254,249,250,46,
};

uint8_t colorcodes[] = {
    1,9,5,13,
    0,1,9,8,
    8,9,5,7,
    0,3,11,15,
};

/** tables */
uint8_t charcode[256];
uint8_t colorcode[256];

uint8_t sin[256] = {
        32,28,24,20,16,13,10,7,5,3,1,0,0,0,0,1,
        2,4,6,9,11,15,18,22,26,30,33,37,41,45,48,52,
        54,57,59,61,62,63,63,63,63,62,60,58,56,53,50,47,
        43,39,35,32,28,24,20,16,13,10,7,5,3,1,0,0,
        0,0,1,2,4,6,9,11,15,18,22,26,30,33,37,41,
        45,48,52,54,57,59,61,62,63,63,63,63,62,60,58,56,
        53,50,47,43,39,35,32,28,24,20,16,13,10,7,5,3,
        1,0,0,0,0,1,2,4,6,9,11,15,18,22,26,30,
        33,37,41,45,48,52,54,57,59,61,62,63,63,63,63,62,
        60,58,56,53,50,47,43,39,35,32,28,24,20,16,13,10,
        7,5,3,1,0,0,0,0,1,2,4,6,9,11,15,18,
        22,26,30,33,37,41,45,48,52,54,57,59,61,62,63,63,
        63,63,62,60,58,56,53,50,47,43,39,35,32,28,24,20,
        16,13,10,7,5,3,1,0,0,0,0,1,2,4,6,9,
        11,15,18,22,26,30,33,37,41,45,48,52,54,57,59,61,
        62,63,63,63,63,62,60,58,56,53,50,47,43,39,35,32,
};

uint8_t cos[256] = {
        0,0,1,4,7,11,15,20,25,31,36,42,47,51,55,59,
        61,63,63,63,62,60,57,53,49,44,39,33,28,22,17,13,
        8,5,2,0,0,0,1,3,5,9,13,18,23,29,34,39,
        45,50,54,57,60,62,63,63,63,61,58,55,51,46,41,36,
        30,25,19,14,10,6,3,1,0,0,0,2,4,7,11,16,
        21,26,32,37,43,47,52,56,59,61,63,63,63,62,60,56,
        53,48,43,38,32,27,22,17,12,8,5,2,0,0,0,1,
        3,6,10,14,19,24,29,35,40,45,50,54,58,61,62,63,
        63,62,61,58,54,50,45,40,35,29,24,19,14,10,6,3,
        1,0,0,0,2,5,8,12,17,22,27,32,38,43,48,53,
        56,60,62,63,63,63,61,59,56,52,48,43,37,32,26,21,
        16,11,7,4,2,0,0,0,1,3,6,10,14,19,25,30,
        36,41,46,51,55,58,61,63,63,63,62,60,57,54,50,45,
        39,34,29,23,18,13,9,5,3,1,0,0,0,2,5,8,
        13,17,22,28,33,39,44,49,53,57,60,62,63,63,63,61,
        59,55,51,47,42,36,31,25,20,15,11,7,4,1,0,0,
};

uint8_t sinecosine[ROWS+COLUMNS];

uint8_t mmu_page_current;
const __sfr __banked __at(0xF0) mmu_page0_ro;
__sfr __at(0xF2) mmu_page2;
uint8_t __at(0x8000) SCR_TEXT[SCREEN_COL80_HEIGHT][SCREEN_COL80_WIDTH];
uint8_t __at(0x9000) SCR_COLOR[SCREEN_COL80_HEIGHT][SCREEN_COL80_WIDTH];

__sfr __banked __at(0x9d) vid_ctrl_status;

static inline void text_map_vram(void)
{
    mmu_page_current = mmu_page0_ro;
    __asm__("di");
    mmu_page2 = VID_MEM_PHYS_ADDR_START >> 14;
}

static inline void text_demap_vram(void)
{
    __asm__("ei");
    mmu_page2 = mmu_page_current;
}

/* start */
static zos_err_t err;
static uint8_t sin_offset = 0;
static uint8_t cos_offset = 0;

void main(void) {
    uint8_t *ptr = NULL;
    uint8_t i = 0, j = 0, k = 0, v = 0;

    // disable cursor
    zvb_peri_text_curs_time = 0;
    err = ioctl(DEV_STDOUT, CMD_CLEAR_SCREEN, (void *)NULL);
    if(err != ERR_SUCCESS) exit(err);

    // generate charcode table
    ptr = &charcode[255];
    for(i = 0; i < 16; i++) {
        k = charcodes[i];
        for(j = 0; j < 16; j++) {
            *ptr = k;
            ptr--;
        }
    }

    // // generate colorcode table
    ptr = &colorcode[255];
    for(i = 0; i < 16; i++) {
        k = colorcodes[i];
        for(j = 0; j < 16; j++) {
            *ptr = k;
            ptr--;
        }
    }

    text_map_vram();

    while(1) {
        // start
        for(i = 0; i < ROWS+COLUMNS; i++) {
            j = cos[cos_offset];
            k = sin[sin_offset];
            sinecosine[i] = j + k;

            sin_offset++;
            cos_offset--;
        }

        // plot
        for(i = 0; i < COLUMNS; i++) {
            k = sinecosine[i];
            ptr = &sinecosine[COLUMNS];
            for(j = 0; j < ROWS; j++) {
                v = k + *ptr;
                SCR_TEXT[j][i] = charcode[v];
                SCR_COLOR[j][i] = colorcode[v];
                ptr++;
            }
        }
    }
}