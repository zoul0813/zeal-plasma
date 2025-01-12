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

DEFC CHARCODE_OFFSET    = 0x000
DEFC COLORCODE_OFFSET   = 0x100
DEFC SINECOSINE_OFFSET  = 0x200

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
;

; generate charcode table
    ;
    ;   Generate the Charcode Table
    ;   repeat each byte in charcodes 16 times, generating a 256-byte table
    ;
    ld de, charcodes + 0x0F                 ; last charcode
    ld hl, TABLES + CHARCODE_OFFSET + 0xFF  ; end of table
next_charcode:
    ld a, (de)
    ld bc, 15               ; count down from
charcode_loop:
    ld (hl), a
    dec l   ; table_ptr--
    dec c   ; j--
    jp p, charcode_loop
    ld a, e
    and a, 0x0F
    dec a
    jp m, charcode_done
    dec e   ; i--
    jp next_charcode
charcode_done:
;

; generate colorcode table
    ;
    ;   Generate the Colorcode Table
    ;
    ld de, colorcodes + 0x0F
    ld hl, TABLES + COLORCODE_OFFSET + 0xFF
next_colorcode:
    ld a, (de)
    ld bc, 15
colorcode_loop:
    ld (hl), a
    dec l   ; -- table_ptr--
    dec c   ; j--
    jp p, colorcode_loop
    ld a, e
    and a, 0x0F
    dec a
    jp m, colorcode_done
    dec e   ; i--
    jp next_colorcode
colorcode_done:

loop:
    ld a, ROWS+COLUMNS
hl_addr:
    ld hl, tbl_sin          ; self modifiying
bc_addr:
    ld bc, tbl_cos          ; self modifying
    ld de, TABLES + SINECOSINE_OFFSET
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

;
    ld c, ROWS-1     ; for(row = ROWS; row > 0; row--)
    ld hl, VRAM_TEXT
    ; sinecosine[COLUMNS + row] will be preclaculated and decremented at eaach row iteraiton
    ld de, TABLES + SINECOSINE_OFFSET + COLUMNS + ROWS
row_loop:
    ; sinecosine is aligned on 256 bytes for sure
    dec e
    push de

    ld a, (de)
    ld d, a
    ld e, COLUMNS-1  ; for(col = COLUMNS; col > 0; col--)
col_loop:
    ; The code below doesn't modify DE, nor C !

    push hl
    ld h, TABLES + SINECOSINE_OFFSET >> 8           ; HL = &sinecosine
    ld l, e                         ; HL = &sinecosine[COLUMN]
    ld a, (hl)                      ; A = sinecosine[COLUMN]
    add d                           ; A += offset

    ; lsa a
    ; Since charcode is aligned on 256, its lower byte is 0x00 for sure.
    ; So HL + A is HA
    ld h, TABLES + CHARCODE_OFFSET >> 8
    ld l, a
    ld b, (hl)                      ; B = charcode[offset]

    ; Color code array is 256 bytes away from charcode, so silply increment H to access it
    inc h
    ld a, (hl)                      ; A = colorcode[offset]

    ; SCR_TEXT[row][col] = charcode[offset]
    pop hl
    ld (hl), b          ; put the charcode on screen
    ; SCR_COLOR[row][col] = colorcode[offset]
    set 4, h            ; HL = HL + 0x1000 (VRAM_COLOR)
    ld (hl), a          ; set the color
    res 4, h
    inc hl

    ; column--
    dec e
    jp p, col_loop

next_row:
    ; row--
    dec c
    pop de
    jp p, row_loop

;
;   OPTIONAL THINGS
;

; ; modulate the sin table
;     ld hl, tbl_sin
; sinmodloop:
;     inc (hl)  ; increment the value
;     rr (hl)   ; rotate the value to the right
;     inc l
;     jp nz, sinmodloop

; ; ; modulate the colorcode table
;     ld hl, colorcode
; colorcodeloop:
;     ld a, (hl)
;     inc a
;     and 0x0F    ; only adjust foreground color
;     ld (hl), a  ; increment the value
;     inc l
;     jp nz, colorcodeloop

; ; modulate the charcode table
;     ld hl, charcode
; charcodeloop:
;     inc (hl)
;     inc l
;     jp nz, charcodeloop

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

    ALIGN 0x10
charcodes:
    DB 254,249,250,46
    DB 254,249,250,46
    DB 254,249,250,46
    DB 254,249,250,46

colorcodes:
    DB 1,9,5,13
    DB 0,1,9,8
    DB 8,9,5,7
    DB 0,3,11,15

;
        ALIGN 0x100 ; "sin 256" table is comprised of 512 bytes
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
;

;
        ALIGN 0x100 ; "cos 256" frequency 6 x 90 degrees (=2,5*pi)
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
;

; this should already be aligned to 0x100
; ALIGN 0x100
TABLES:
