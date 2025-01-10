    ; Include the Zeal 8-bit OS header file, containing all the syscalls macros.
    INCLUDE "zos_sys.asm"
    INCLUDE "zos_video.asm"

    ; Make the code start at 0x4000, as requested by the kernel
    ORG 0x4000

DEFC VRAM_TEXT  = 0x8000    ; Location of screen chars
; DEFC VRAM_COLOR = 0x1000    ; offset from VRAM_TEXT

DEFC COLUMNS    = 80
DEFC ROWS       = 40

; ZVB Constants
DEFC VID_MEM_PHYS_ADDR_START    = 0x100000
DEFC VID_MEM_LAYER0_ADDR        = VID_MEM_PHYS_ADDR_START
DEFC VID_MEM_LAYER1_ADDR        = VID_MEM_PHYS_ADDR_START + 0x1000

DEFC VID_IO_CTRL_STAT           = 0x90
DEFC IO_CTRL_VID_MODE           = VID_IO_CTRL_STAT + 0xc
DEFC IO_CTRL_STATUS_REG         = VID_IO_CTRL_STAT + 0xd

DEFC VID_IO_BANKED_ADDR = 0xA0
DEFC BANK_IO_TEXT_NUM   = 0 ; Text control module, usable in text mode (640x480 or 320x240)
DEFC IO_TEXT_PRINT_CHAR = VID_IO_BANKED_ADDR + 0x0
DEFC IO_TEXT_CURS_Y     = VID_IO_BANKED_ADDR + 0x1 ; Cursor Y position (in characters count)
DEFC IO_TEXT_CURS_X     = VID_IO_BANKED_ADDR + 0x2 ; Cursor X position (in characters count)
DEFC IO_TEXT_SCROLL_Y   = VID_IO_BANKED_ADDR + 0x3 ; Scroll Y
DEFC IO_TEXT_SCROLL_X   = VID_IO_BANKED_ADDR + 0x4 ; Scroll X
DEFC IO_TEXT_COLOR      = VID_IO_BANKED_ADDR + 0x5 ; Current character color
DEFC IO_TEXT_CURS_TIME  = VID_IO_BANKED_ADDR + 0x6 ; Blink time, in frames, for the cursor
DEFC IO_TEXT_CURS_CHAR  = VID_IO_BANKED_ADDR + 0x7 ; Blink time, in frames, for the cursor
DEFC IO_TEXT_CURS_COLOR = VID_IO_BANKED_ADDR + 0x8 ; Blink time, in frames, for the cursor

; first step is to create a table with sine + cosine values
; The addition is performed on a proportionate basis
; the table is changed on every frame
_start:
    ld h, DEV_STDOUT
    ld c, CMD_CLEAR_SCREEN          ; clear screen
    IOCTL()

    ;
    ; TODO:  kb_mode(KB_READ_NON_BLOCK | KB_MODE_RAW)
    ;

    ld a, 0
    out (IO_TEXT_CURS_TIME), a     ; disable cursor

    ld de, VRAM_TEXT
    ld h, 0x10
    ld bc, 0x0000                   ; Map VRAM on Page 2: 0x8000
    MAP()

loop:
    ld a, ROWS+COLUMNS
hl_addr:
    ld hl, tbl_sin          ; self modifiying
bc_addr:
    ld bc, tbl_cos          ; self modifying
    ld de, sinecosine
sincos_loop:
    push af
    ld a, (bc)
    add (hl)
    ld (de), a
    inc e
    inc l
    inc c
    pop af
    dec a
    jp nz, sincos_loop

    ; modify the table offsets
    ld hl, hl_addr + 1
    inc (hl)
    ld hl, bc_addr + 1
    dec (hl)

    ld hl, rowoffset
    ld (hl), 0
    inc hl
    ld (hl), 0
;

;
    ld bc, ROWS-1     ; for(row = ROWS; row > 0; row--)
row_loop:
    ld de, COLUMNS-1  ; for(col = COLUMNS; col > 0; col--)
col_loop:
    push bc ; columns
    push de ; rows


    ld hl, sinecosine   ; HL = &sinecosine
    add hl, de          ; HL = &sinecosine[COLUMN]
    ld a, (hl)          ; A = sinecosine[COLUMN]
    ld hl, sinecosine  ; HL = &sinecosine
    ; add hl, COLUMNS   ; HL = &sinecosine[COLUMNS]
    push de
    ld de, 0x50
    add hl, de
    pop de
    ; / add hl, COLUMNS
    add hl, bc  ; HL = &sinecosine[COLUMNS + ROW]

    adc a, (hl) ; A = sinecosine[COLUMN] + &sinecosine[COLUMNS + ROW]

    push af

    ld hl, charcode
    push de
    ld d, 0
    ld e, a
    add hl, de
    pop de
    ld a, (hl)
    ld b, a     ; charcode[offset]

    pop af

    ld hl, colorcode
    push de
    ld d, 0
    ld e, a
    add hl, de
    pop de
    ld a, (hl)
    ld c, a     ; charcode[offset]


    ; SCR_TEXT[row][col] = charcode[offset]
    ld hl, (rowoffset)  ; get the current (row * column) offset
    add hl, de;         ; add the current column
    ; add hl, VRAM_TEXT   ; VRAM_TEXT
    push de
    ld de, VRAM_TEXT
    add hl, de
    pop de
    ; / add hl, VRAM_TEXT
    ld (hl), b          ; put the charcode on screen

    ; SCR_COLOR[row][col] = colorcode[offset]
    set 4, h            ; offset for color
    ld (hl), c          ; set the color

    ; pop the row/column
    pop de  ; columns
    pop bc  ; rows

    ; column--
    dec e
    jp p, col_loop

    ; rowoffset += 80
    ld hl, rowoffset
    ld a, (hl)
    add a, 80
    ld (hl), a
    jr nc, next_row
    inc hl
    inc (hl)

next_row:
    ; row--
    dec c
    jp p, row_loop

    jp loop            ; infinite loop


_end:
    ; ld h, DEV_STDOUT
    ; ld c, CMD_RESET_SCREEN          ; reset screen
    ; IOCTL()

    ; TODO: remove this later
    ld a, 0 ; force a return 0

    ; We MUST execute EXIT() syscall at the end of any program.
    ; Exit code is stored in H, it is 0 if everything went fine.
    ld h, a
    EXIT()
;

rowoffset: DB 0,0

;
        ALIGN 0x100
charcode:
        DS 16,254 ;
        DS 16,249 ; number of bytes used will determine
        DS 16,250 ; the thickness of the layers pattern
        DS 16,46 ;

        DS 16,254 ;
        DS 16,249 ; number of bytes used will determine
        DS 16,250 ; the thickness of the layers pattern
        DS 16,46 ;

        DS 16,254 ;
        DS 16,249 ; number of bytes used will determine
        DS 16,250 ; the thickness of the layers pattern
        DS 16,46 ;

        DS 16,254 ;
        DS 16,249 ; number of bytes used will determine
        DS 16,250 ; the thickness of the layers pattern
        DS 16,46 ;
;

;
        ALIGN 0x100  ; here the code is aligned
                    ; so that the LB adress is at $00
colorcode:
        DS 16, 8    ; dark grey
        DS 16, 9    ; purple
        DS 16, 5    ; magenta
        DS 16, 7    ; light grey

        DS 16,00    ; black
        DS 16,11    ; teal
        DS 16,12    ; orange
        DS 16,15    ; white

        DS 16, 8    ; dark grey
        DS 16, 9    ; purple
        DS 16, 5    ; magenta
        DS 16, 7    ; light grey

        DS 16,00    ; black
        DS 16,11    ; teal
        DS 16,12    ; orange
        DS 16,15    ; white
;

;
        ALIGN 0x100 ; "sin 2*256" table is comprised of 512 bytes
                    ; with values between 0 and 63
                    ; they are based on frequency by 4 x 90 degrees
                    ; (=2*pi, ie a full circle)
tbl_sin:
        DB 32,28,24,20,16,13,10,7,5,3,1,0,0,0,0,1
        DB 2,4,6,9,11,15,18,22,26,30,33,37,41,45,48,52
        DB 54,57,59,61,62,63,63,63,63,62,60,58,56,53,50,47
        DB 43,39,35,32,28,24,20,16,13,10,7,5,3,1,0,0
        DB 0,0,1,2,4,6,9,11,15,18,22,26,30,33,37,41
        DB 45,48,52,54,57,59,61,62,63,63,63,63,62,60,58,56
        DB 53,50,47,43,39,35,32,28,24,20,16,13,10,7,5,3
        DB 1,0,0,0,0,1,2,4,6,9,11,15,18,22,26,30
        DB 33,37,41,45,48,52,54,57,59,61,62,63,63,63,63,62
        DB 60,58,56,53,50,47,43,39,35,32,28,24,20,16,13,10
        DB 7,5,3,1,0,0,0,0,1,2,4,6,9,11,15,18
        DB 22,26,30,33,37,41,45,48,52,54,57,59,61,62,63,63
        DB 63,63,62,60,58,56,53,50,47,43,39,35,32,28,24,20
        DB 16,13,10,7,5,3,1,0,0,0,0,1,2,4,6,9
        DB 11,15,18,22,26,30,33,37,41,45,48,52,54,57,59,61
        DB 62,63,63,63,63,62,60,58,56,53,50,47,43,39,35,32

        DB 32,28,24,20,16,13,10,7,5,3,1,0,0,0,0,1
        DB 2,4,6,9,11,15,18,22,26,30,33,37,41,45,48,52
        DB 54,57,59,61,62,63,63,63,63,62,60,58,56,53,50,47
        DB 43,39,35,32,28,24,20,16,13,10,7,5,3,1,0,0
        DB 0,0,1,2,4,6,9,11,15,18,22,26,30,33,37,41
        DB 45,48,52,54,57,59,61,62,63,63,63,63,62,60,58,56
        DB 53,50,47,43,39,35,32,28,24,20,16,13,10,7,5,3
        DB 1,0,0,0,0,1,2,4,6,9,11,15,18,22,26,30
        DB 33,37,41,45,48,52,54,57,59,61,62,63,63,63,63,62
        DB 60,58,56,53,50,47,43,39,35,32,28,24,20,16,13,10
        DB 7,5,3,1,0,0,0,0,1,2,4,6,9,11,15,18
        DB 22,26,30,33,37,41,45,48,52,54,57,59,61,62,63,63
        DB 63,63,62,60,58,56,53,50,47,43,39,35,32,28,24,20
        DB 16,13,10,7,5,3,1,0,0,0,0,1,2,4,6,9
        DB 11,15,18,22,26,30,33,37,41,45,48,52,54,57,59,61
        DB 62,63,63,63,63,62,60,58,56,53,50,47,43,39,35,32
;

;
        ALIGN 0x100 ; "cos 2*256" frequency 6 x 90 degrees (=2,5*pi)  
tbl_cos:
        DB 0,0,1,4,7,11,15,20,25,31,36,42,47,51,55,59
        DB 61,63,63,63,62,60,57,53,49,44,39,33,28,22,17,13
        DB 8,5,2,0,0,0,1,3,5,9,13,18,23,29,34,39
        DB 45,50,54,57,60,62,63,63,63,61,58,55,51,46,41,36
        DB 30,25,19,14,10,6,3,1,0,0,0,2,4,7,11,16
        DB 21,26,32,37,43,47,52,56,59,61,63,63,63,62,60,56
        DB 53,48,43,38,32,27,22,17,12,8,5,2,0,0,0,1
        DB 3,6,10,14,19,24,29,35,40,45,50,54,58,61,62,63
        DB 63,62,61,58,54,50,45,40,35,29,24,19,14,10,6,3
        DB 1,0,0,0,2,5,8,12,17,22,27,32,38,43,48,53
        DB 56,60,62,63,63,63,61,59,56,52,48,43,37,32,26,21
        DB 16,11,7,4,2,0,0,0,1,3,6,10,14,19,25,30
        DB 36,41,46,51,55,58,61,63,63,63,62,60,57,54,50,45
        DB 39,34,29,23,18,13,9,5,3,1,0,0,0,2,5,8
        DB 13,17,22,28,33,39,44,49,53,57,60,62,63,63,63,61
        DB 59,55,51,47,42,36,31,25,20,15,11,7,4,1,0,0

        DB 0,0,1,4,7,11,15,20,25,31,36,42,47,51,55,59
        DB 61,63,63,63,62,60,57,53,49,44,39,33,28,22,17,13
        DB 8,5,2,0,0,0,1,3,5,9,13,18,23,29,34,39
        DB 45,50,54,57,60,62,63,63,63,61,58,55,51,46,41,36
        DB 30,25,19,14,10,6,3,1,0,0,0,2,4,7,11,16
        DB 21,26,32,37,43,47,52,56,59,61,63,63,63,62,60,56
        DB 53,48,43,38,32,27,22,17,12,8,5,2,0,0,0,1
        DB 3,6,10,14,19,24,29,35,40,45,50,54,58,61,62,63
        DB 63,62,61,58,54,50,45,40,35,29,24,19,14,10,6,3
        DB 1,0,0,0,2,5,8,12,17,22,27,32,38,43,48,53
        DB 56,60,62,63,63,63,61,59,56,52,48,43,37,32,26,21
        DB 16,11,7,4,2,0,0,0,1,3,6,10,14,19,25,30
        DB 36,41,46,51,55,58,61,63,63,63,62,60,57,54,50,45
        DB 39,34,29,23,18,13,9,5,3,1,0,0,0,2,5,8
        DB 13,17,22,28,33,39,44,49,53,57,60,62,63,63,63,61
        DB 59,55,51,47,42,36,31,25,20,15,11,7,4,1,0,0
;

;
        ALIGN 0x100
sinecosine:
        DB 65,0 ; max value in sinecosine is 63+63=126 (x 2 =252)