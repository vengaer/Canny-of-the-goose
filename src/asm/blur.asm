    section .rodata

    align 16
    wout: dd 0.153388, 0.153388, 0.153388, 0.153388
    wmid: dd 0.221461, 0.221461, 0.221461, 0.221461
    wcen: dd 0.250301, 0.250301, 0.250301, 0.250301

    section .text
    global gaussblur

    extern malloc
    extern free

; Gaussian blur using 5x5 filter kernel
; Params:
;     rdi: byte ptr to data, overwritten with output
;     esi: width in pixels
;     edx: height in pixels
; Return:
;     eax: 0 on success, 1 on malloc failure, 2 on unsuitable dims
gaussblur:
.data       equ 0
.width      equ 8
.height     equ 12
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 16

    mov     eax, 2

    cmp     esi, 16                         ; Must be at least 16 pixels wide
    jl      .epi

    cmp     edx, 5                          ; At least 5 pixels tall
    jl      .epi

    mov     qword [rsp + .data], rdi        ; Data to stack
    mov     dword [rsp + .width], esi
    mov     dword [rsp + .height], edx

    mov     edi, esi                        ; Number of bytes
    imul    edi, edx

    call    malloc

    cmp     eax, 0
    jne     .malloc_succ

    inc     eax
    jmp     .epi

.malloc_succ:
    mov     r9, rax                         ; Address of tmp array to r9

    mov     r8, qword [rsp + .data]         ; Data back to registers
    mov     esi, dword [rsp + .width]
    mov     edx, dword [rsp + .height]

    mov     r11, r9

    movaps  xmm12, [wout]
    movaps  xmm13, [wmid]
    movaps  xmm14, [wcen]

    pxor        xmm15, xmm15

; Horizontal pass
    mov     r10, r8
    mov     ebx, edx                        ; Counter for number of rows

    mov     r12d, esi
    sub     r12d, 8                         ; 8 last bytes handled separately

.hloop:
    movdqu  xmm0, [r10]                     ; First 8 bytes
    movdqa  xmm1, xmm0
    movdqa  xmm2, xmm0                      ; Third col of filter
    movdqa  xmm3, xmm0
    movdqa  xmm4, xmm0
    pslldq  xmm0, 2                         ; First col of filter
    pslldq  xmm1, 1                         ; Second col of filter
    psrldq  xmm3, 1                         ; Fourth col of filter
    psrldq  xmm4, 2                         ; Fifth col of filter

    pextrb  eax, xmm0, 2                    ; Duplicate first byte (clamp)
    pinsrb  xmm0, eax, 0
    pinsrb  xmm0, eax, 1
    pinsrb  xmm1, eax, 0

    mov     rdi, r11

    call    process_horizontal_batch

    mov     ecx, 12                         ; 12 bytes already processed

.hinner_loop:                               ; Middle part of line
    movdqu  xmm0, [r10 + rcx - 2]           ; First col of filter
    movdqa  xmm1, xmm0
    movdqa  xmm2, xmm0
    movdqa  xmm3, xmm0
    movdqa  xmm4, xmm0
    psrldq  xmm1, 1                         ; Second col of filter
    psrldq  xmm2, 2                         ; Third col of filter
    psrldq  xmm3, 3                         ; Fourth col of filter
    psrldq  xmm4, 4                         ; Fifth col of filter

    lea     rdi, [r11 + rcx]

    call    process_horizontal_batch

    add     ecx, 12                         ; Processing 12 bytes per iteration
    cmp     ecx, r12d
    jl      .hinner_loop

    mov     ecx, esi
    sub     ecx, 16                         ; Exactly 16 bytes until end of line

    movdqu  xmm0, [r10 + rcx]               ; 16 last bytes of line
    movdqa  xmm1, xmm0
    movdqa  xmm2, xmm0
    movdqa  xmm3, xmm0
    movdqa  xmm4, xmm0
    psrldq  xmm0, 2                         ; 14th byte from end of line
    psrldq  xmm1, 3                         ; 13th byte from end of line
    psrldq  xmm2, 4                         ; 12th byte from end of line
    psrldq  xmm3, 5                         ; 11th byte from end of line
    psrldq  xmm4, 6                         ; 10th byte from end of line

    add     ecx, 4                          ; Increase ecx to correct write offset

    pextrb  eax, xmm4, 9                    ; Duplicate last byte on line
    pinsrb  xmm3, eax, 11
    pinsrb  xmm4, eax, 10
    pinsrb  xmm4, eax, 11

    lea     rdi, [r11 + rcx]

    call    process_horizontal_batch

    add     r10, rsi                        ; Advance to next row
    add     r11, rsi
    dec     ebx
    jnz     .hloop

; Vertical pass
    mov     r10, r8                         ; Address of output
    mov     r11, r9                         ; First row of filter
    mov     r12, r9                         ; Second row of filter
    mov     r13, r9                         ; Third row of filter
    lea     r14, [r9 + rsi]                 ; Fourth row of filter
    lea     r15, [r9 + 2 * rsi]             ; Fifth row of filter

    xor     ecx, ecx
.tr_loop:                                   ; Top row
    movdqu  xmm0, [r11 + rcx]
    movdqa  xmm1, xmm0                      ; r11, r12 and r13 same address
    movdqa  xmm2, xmm0
    movdqu  xmm3, [r14 + rcx]
    movdqu  xmm4, [r15 + rcx]

    lea     rdi, [r10 + rcx]

    call    process_vertical_batch

    add     ecx, 16                         ; Processing 16 bytes per iteration
    cmp     ecx, esi
    jl      .tr_loop

    add     r10, rsi                        ; Advance to next row
    add     r13, rsi
    add     r14, rsi
    add     r15, rsi

    xor     ecx, ecx
.str_loop:                                  ; Second row from top
    movdqu  xmm0, [r11 + rcx]
    movdqa  xmm1, xmm0                      ; r11 and r12 same address
    movdqu  xmm2, [r13 + rcx]
    movdqu  xmm3, [r14 + rcx]
    movdqu  xmm4, [r15 + rcx]

    lea     rdi, [r10 + rcx]

    call    process_vertical_batch

    add     ecx, 16                         ; Processing 16 bytes per iteration
    cmp     ecx, esi
    jl      .str_loop

    add     r10, rsi                        ; Advance to next row
    add     r12, rsi
    add     r13, rsi
    add     r14, rsi
    add     r15, rsi

    sub     edx, 4                          ; 2 top and 2 bottom rows handled separately

.vloop:
    xor     ecx, ecx
.vinner_loop:                               ; Third to third from last rows
    movdqu  xmm0, [r11 + rcx]
    movdqu  xmm1, [r12 + rcx]
    movdqu  xmm2, [r13 + rcx]
    movdqu  xmm3, [r14 + rcx]
    movdqu  xmm4, [r15 + rcx]

    lea     rdi, [r10 + rcx]

    call    process_vertical_batch

    add     ecx, 16                         ; Processing 16 bytes per iteration
    cmp     ecx, esi
    jl      .vinner_loop

    add     r10, rsi                        ; Advance to next row
    add     r11, rsi
    add     r12, rsi
    add     r13, rsi
    add     r14, rsi
    add     r15, rsi
    dec     edx
    jnz     .vloop

    xor     ecx, ecx
.slr_loop:                                  ; Second row from bottom
    movdqu  xmm0, [r11 + rcx]
    movdqu  xmm1, [r12 + rcx]
    movdqu  xmm2, [r13 + rcx]
    movdqu  xmm3, [r14 + rcx]
    movdqa  xmm4, xmm3                      ; xmm3 and xmm4 same address

    lea     rdi, [r10 + rcx]

    call    process_vertical_batch

    add     ecx, 16                         ; Processing 16 bytes per iteration
    cmp     ecx, esi
    jl      .slr_loop

    add     r10, rsi                        ; Advance to next row

    sub     esi, 16                         ; Prevent out-of-bounds access
    xor     ecx, ecx
.lr_loop:                                   ; Last row
    movdqu  xmm0, [r12 + rcx]
    movdqu  xmm1, [r13 + rcx]
    movdqu  xmm2, [r14 + rcx]               ; xmm2, xmm3 and xmm4 same address
    movdqa  xmm3, xmm2
    movdqa  xmm4, xmm3

    lea     rdi, [r10 + rcx]

    call    process_vertical_batch

    add     ecx, 16                         ; Processing 16 bytes per iteration
    cmp     ecx, esi
    jl      .lr_loop

    mov     ecx, esi                        ; Exactly 16 bytes left on row
    movdqu  xmm0, [r12 + rcx]
    movdqu  xmm1, [r13 + rcx]
    movdqu  xmm2, [r14 + rcx]               ; xmm2, xmm3 and xmm4 same address
    movdqa  xmm3, xmm2
    movdqa  xmm4, xmm3

    lea     rdi, [r10 + rcx]

    call    process_vertical_batch

.free:
    mov     rdi, r9
    call    free

    xor     eax, eax
.epi:
    add     rsp, 16
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; Process 12 bytes for horizontal filter and write to 
; address in rdi
; Params:
;     rdi: address to write to
;     xmm0(packed bytes): first column
;     xmm1(packed bytes): second column
;     xmm2(packed bytes): third column
;     xmm3(packed bytes): fourth column
;     xmm4(packed bytes): fifth column
; Return:
;     -
process_horizontal_batch:
; First col
    movdqa  xmm5, xmm0                      ; Backup high bytes
    punpcklbw   xmm0, xmm15                 ; Low bytes to words
    movdqa  xmm6, xmm0                      ; Backup high words

    punpcklwd   xmm0, xmm15                 ; Low words to dwords
    cvtdq2ps    xmm0, xmm0                  ; To single precision float
    mulps   xmm0, xmm12                     ; Multiply by weights
    movaps  xmm7, xmm0                      ; Sum bytes 0-3 in xmm7

    punpckhwd   xmm6, xmm15                 ; High words to dwords
    cvtdq2ps    xmm6, xmm6                  ; To single precision float
    mulps   xmm6, xmm12                     ; Multiply by weights
    movaps  xmm8, xmm6                      ; Sum bytes 4-7 in xmm8

    punpckhbw   xmm5, xmm15                 ; High bytes to words
    punpcklwd   xmm5, xmm15                 ; Low words to dwords
    cvtdq2ps    xmm5, xmm5                  ; To single precision floats
    mulps   xmm5, xmm12                     ; Multiply by weights
    movaps  xmm9, xmm5                      ; Sum bytes 8-11 in xmm9

; Second col
    movdqa  xmm5, xmm1                      ; Backup high bytes
    punpcklbw   xmm1, xmm15                 ; Low bytes to words
    movdqa  xmm6, xmm1                      ; Backup high words

    punpcklwd   xmm1, xmm15                 ; Low words to dwords
    cvtdq2ps    xmm1, xmm1                  ; To single precision float
    mulps   xmm1, xmm13                     ; Multiply by weights
    addps   xmm7, xmm1                      ; Sum bytes 0-3 in xmm7

    punpckhwd   xmm6, xmm15                 ; High words to dwords
    cvtdq2ps    xmm6, xmm6                  ; To single precision float
    mulps   xmm6, xmm13                     ; Multiply by weights
    addps   xmm8, xmm6                      ; Sum bytes 4-7 in xmm8

    punpckhbw   xmm5, xmm15                 ; High bytes to words
    punpcklwd   xmm5, xmm15                 ; Low words to dwords
    cvtdq2ps    xmm5, xmm5                  ; To single precision floats
    mulps   xmm5, xmm13                     ; Multiply by weights
    addps   xmm9, xmm5                      ; Sum bytes 8-11 in xmm9

; Third col
    movdqa  xmm5, xmm2                      ; Backup high bytes
    punpcklbw   xmm2, xmm15                 ; Low bytes to words
    movdqa  xmm6, xmm2                      ; Backup high words

    punpcklwd   xmm2, xmm15                 ; Low words to dwords
    cvtdq2ps    xmm2, xmm2                  ; To single precision float
    mulps   xmm2, xmm14                     ; Multiply by weights
    addps   xmm7, xmm2                      ; Sum bytes 0-3 in xmm7

    punpckhwd   xmm6, xmm15                 ; High words to dwords
    cvtdq2ps    xmm6, xmm6                  ; To single precision float
    mulps   xmm6, xmm14                     ; Multiply by weights
    addps   xmm8, xmm6                      ; Sum bytes 4-7 in xmm8

    punpckhbw   xmm5, xmm15                 ; High bytes to words
    punpcklwd   xmm5, xmm15                 ; Low words to dwords
    cvtdq2ps    xmm5, xmm5                  ; To single precision floats
    mulps   xmm5, xmm14                     ; Multiply by weights
    addps   xmm9, xmm5                      ; Sum bytes 8-11 in xmm9

; Fourth col
    movdqa  xmm5, xmm3                      ; Backup high bytes
    punpcklbw   xmm3, xmm15                 ; Low bytes to words
    movdqa  xmm6, xmm3                      ; Backup high words

    punpcklwd   xmm3, xmm15                 ; Low words to dwords
    cvtdq2ps    xmm3, xmm3                  ; To single precision float
    mulps   xmm3, xmm13                     ; Multiply by weights
    addps   xmm7, xmm3                      ; Sum bytes 0-3 in xmm7

    punpckhwd   xmm6, xmm15                 ; High words to dwords
    cvtdq2ps    xmm6, xmm6                  ; To single precision float
    mulps   xmm6, xmm13                     ; Multiply by weights
    addps   xmm8, xmm6                      ; Sum bytes 4-7 in xmm8

    punpckhbw   xmm5, xmm15                 ; High bytes to words
    punpcklwd   xmm5, xmm15                 ; Low words to dwords
    cvtdq2ps    xmm5, xmm5                  ; To single precision floats
    mulps   xmm5, xmm13                     ; Multiply by weights
    addps   xmm9, xmm5                      ; Sum bytes 8-11 in xmm9

; Fifth col
    movdqa  xmm5, xmm4                      ; Backup high bytes
    punpcklbw   xmm4, xmm15                 ; Low bytes to words
    movdqa  xmm6, xmm4                      ; Backup high words

    punpcklwd   xmm4, xmm15                 ; Low words to dwords
    cvtdq2ps    xmm4, xmm4                  ; To single precision float
    mulps   xmm4, xmm12                     ; Multiply by weights
    addps   xmm7, xmm4                      ; Sum bytes 0-3 in xmm7

    punpckhwd   xmm6, xmm15                 ; High words to dwords
    cvtdq2ps    xmm6, xmm6                  ; To single precision float
    mulps   xmm6, xmm12                     ; Multiply by weights
    addps   xmm8, xmm6                      ; Sum bytes 4-7 in xmm8

    punpckhbw   xmm5, xmm15                 ; High bytes to words
    punpcklwd   xmm5, xmm15                 ; Low words to dwords
    cvtdq2ps    xmm5, xmm5                  ; To single precision floats
    mulps   xmm5, xmm12                     ; Multiply by weights
    addps   xmm9, xmm5                      ; Sum bytes 8-11 in xmm9

    cvtps2dq    xmm0, xmm7
    cvtps2dq    xmm1, xmm8
    cvtps2dq    xmm2, xmm9

    call    compressd2b_and_write12

    ret

; Process 16 bytes for vertical filter and write to 
; address in rdi
; Params:
;     rdi: address to write to
;     xmm0(packed bytes): first row
;     xmm1(packed bytes): second row
;     xmm2(packed bytes): third row
;     xmm3(packed bytes): fourth row
;     xmm4(packed bytes): fifth row
; Return:
;     -
process_vertical_batch:
; First row (counting clamped rows)
    movdqa  xmm5, xmm0                      ; Backup high bytes in first row
    punpcklbw   xmm0, xmm15                 ; Low bytes to words
    movdqa  xmm6, xmm0                      ; Backup high words

    punpcklwd   xmm0, xmm15                 ; Low words to dwords
    cvtdq2ps    xmm0, xmm0                  ; To single precision float
    mulps   xmm0, xmm12                     ; Multiply with weights
    movaps  xmm7, xmm0                      ; Sum bytes 0-3 in xmm7

    punpckhwd   xmm6, xmm15                 ; High words to dwords
    cvtdq2ps    xmm6, xmm6                  ; To single precision float
    mulps   xmm6, xmm12                     ; Multiply with weights
    movaps  xmm8, xmm6                      ; Sum of bytes 4-7 in xmm8

    movdqa  xmm0, xmm5                      ; Restore bytes
    punpckhbw   xmm0, xmm15                 ; High bytes to words
    movdqa  xmm6, xmm0                      ; Preserve high words

    punpcklwd   xmm0, xmm15                 ; Low words to dwords
    cvtdq2ps    xmm0, xmm0                  ; To single precision float
    mulps   xmm0, xmm12                     ; Multiply with weights
    movaps  xmm9, xmm0                      ; Sum of bytes 8-11 in xmm9

    punpckhwd   xmm6, xmm15                 ; High words to dwords
    cvtdq2ps    xmm6, xmm6                  ; To single precision float
    mulps   xmm6, xmm12                     ; Multiply with weights
    movaps  xmm10, xmm6                     ; Sum bytes 12-15 in xmm10

; Second row
    movdqa  xmm5, xmm1                      ; Backup high bytes in second row
    punpcklbw   xmm1, xmm15                 ; Low bytes to words
    movdqa  xmm6, xmm1                      ; Backup high words

    punpcklwd   xmm1, xmm15                 ; Low words to dwords
    cvtdq2ps    xmm1, xmm1                  ; To single precision float
    mulps   xmm1, xmm13                     ; Multiply with weights
    addps   xmm7, xmm1                      ; Sum bytes 0-3 in xmm7

    punpckhwd   xmm6, xmm15                 ; High words to dwords
    cvtdq2ps    xmm6, xmm6                  ; To single precision float
    mulps   xmm6, xmm13                     ; Multiply with weights
    addps   xmm8, xmm6                      ; Sum of bytes 4-7 in xmm8

    movdqa  xmm1, xmm5                      ; Restore bytes
    punpckhbw   xmm1, xmm15                 ; High bytes to words
    movdqa  xmm6, xmm1                      ; Preserve high words

    punpcklwd   xmm1, xmm15                 ; Low words to dwords
    cvtdq2ps    xmm1, xmm1                  ; To single precision float
    mulps   xmm1, xmm13                     ; Multiply with weights
    addps   xmm9, xmm1                      ; Sum of bytes 8-11 in xmm9

    punpckhwd   xmm6, xmm15                 ; High words to dwords
    cvtdq2ps    xmm6, xmm6                  ; To single precision float
    mulps   xmm6, xmm13                     ; Multiply with weights
    addps  xmm10, xmm6                      ; Sum bytes 12-15 in xmm10

; Third row
    movdqa  xmm5, xmm2                      ; Backup high bytes in third row
    punpcklbw   xmm2, xmm15                 ; Low bytes to words
    movdqa  xmm6, xmm2                      ; Backup high words

    punpcklwd   xmm2, xmm15                 ; Low words to dwords
    cvtdq2ps    xmm2, xmm2                  ; To single precision float
    mulps   xmm2, xmm14                     ; Multiply with weights
    addps   xmm7, xmm2                      ; Sum bytes 0-3 in xmm7

    punpckhwd   xmm6, xmm15                 ; High words to dwords
    cvtdq2ps    xmm6, xmm6                  ; To single precision float
    mulps   xmm6, xmm14                     ; Multiply with weights
    addps   xmm8, xmm6                      ; Sum of bytes 4-7 in xmm8

    movdqa  xmm2, xmm5                      ; Restore bytes
    punpckhbw   xmm2, xmm15                 ; High bytes to words
    movdqa  xmm6, xmm2                      ; Preserve high words

    punpcklwd   xmm2, xmm15                 ; Low words to dwords
    cvtdq2ps    xmm2, xmm2                  ; To single precision float
    mulps   xmm2, xmm14                     ; Multiply with weights
    addps   xmm9, xmm2                      ; Sum of bytes 8-11 in xmm9

    punpckhwd   xmm6, xmm15                 ; High words to dwords
    cvtdq2ps    xmm6, xmm6                  ; To single precision float
    mulps   xmm6, xmm14                     ; Multiply with weights
    addps  xmm10, xmm6                      ; Sum bytes 12-15 in xmm10

; Fourth row
    movdqa  xmm5, xmm3                      ; Backup high bytes in fourth row
    punpcklbw   xmm3, xmm15                 ; Low bytes to words
    movdqa  xmm6, xmm3                      ; Backup high words

    punpcklwd   xmm3, xmm15                 ; Low words to dwords
    cvtdq2ps    xmm3, xmm3                  ; To single precision float
    mulps   xmm3, xmm13                     ; Multiply with weights
    addps   xmm7, xmm3                      ; Sum bytes 0-3 in xmm7

    punpckhwd   xmm6, xmm15                 ; High words to dwords
    cvtdq2ps    xmm6, xmm6                  ; To single precision float
    mulps   xmm6, xmm13                     ; Multiply with weights
    addps   xmm8, xmm6                      ; Sum of bytes 4-7 in xmm8

    movdqa  xmm3, xmm5                      ; Restore bytes
    punpckhbw   xmm3, xmm15                 ; High bytes to words
    movdqa  xmm6, xmm3                      ; Preserve high words

    punpcklwd   xmm3, xmm15                 ; Low words to dwords
    cvtdq2ps    xmm3, xmm3                  ; To single precision float
    mulps   xmm3, xmm13                     ; Multiply with weights
    addps   xmm9, xmm3                      ; Sum of bytes 8-11 in xmm9

    punpckhwd   xmm6, xmm15                 ; High words to dwords
    cvtdq2ps    xmm6, xmm6                  ; To single precision float
    mulps   xmm6, xmm13                     ; Multiply with weights
    addps  xmm10, xmm6                      ; Sum bytes 12-15 in xmm10

; Fifth row
    movdqa  xmm5, xmm4                      ; Backup high bytes in fourth row
    punpcklbw   xmm4, xmm15                 ; Low bytes to words
    movdqa  xmm6, xmm4                      ; Backup high words

    punpcklwd   xmm4, xmm15                 ; Low words to dwords
    cvtdq2ps    xmm4, xmm4                  ; To single precision float
    mulps   xmm4, xmm12                     ; Multiply with weights
    addps   xmm7, xmm4                      ; Sum bytes 0-3 in xmm7

    punpckhwd   xmm6, xmm15                 ; High words to dwords
    cvtdq2ps    xmm6, xmm6                  ; To single precision float
    mulps   xmm6, xmm12                     ; Multiply with weights
    addps   xmm8, xmm6                      ; Sum of bytes 4-7 in xmm8

    movdqa  xmm4, xmm5                      ; Restore bytes
    punpckhbw   xmm4, xmm15                 ; High bytes to words
    movdqa  xmm6, xmm4                      ; Preserve high words

    punpcklwd   xmm4, xmm15                 ; Low words to dwords
    cvtdq2ps    xmm4, xmm4                  ; To single precision float
    mulps   xmm4, xmm12                     ; Multiply with weights
    addps   xmm9, xmm4                      ; Sum of bytes 8-11 in xmm9

    punpckhwd   xmm6, xmm15                 ; High words to dwords
    cvtdq2ps    xmm6, xmm6                  ; To single precision float
    mulps   xmm6, xmm12                     ; Multiply with weights
    addps  xmm10, xmm6                      ; Sum bytes 12-15 in xmm10

    cvtps2dq    xmm0, xmm7
    cvtps2dq    xmm1, xmm8
    cvtps2dq    xmm2, xmm9
    cvtps2dq    xmm3, xmm10

    call    compressd2b_and_write16

    ret

; Compress 12 dwords stored in xmm0:xmm1:xmm2 to bytes and write to address in rdi
; Params:
;     rdi: address to which data should be written
;     xmm0(packed dwords): dwords 0-3
;     xmm1(packed dwords): dwords 4-7
;     xmm2(packed dwords): dwords 8-11
; Return:
;     -
compressd2b_and_write12:
    pextrb  eax, xmm0, 0
    pinsrb  xmm3, eax, 0

    pextrb  eax, xmm0, 4
    pinsrb  xmm3, eax, 1

    pextrb  eax, xmm0, 8
    pinsrb  xmm3, eax, 2

    pextrb  eax, xmm0, 12
    pinsrb  xmm3, eax, 3

    pextrb  eax, xmm1, 0
    pinsrb  xmm3, eax, 4

    pextrb  eax, xmm1, 4
    pinsrb  xmm3, eax, 5

    pextrb  eax, xmm1, 8
    pinsrb  xmm3, eax, 6

    pextrb  eax, xmm1, 12
    pinsrb  xmm3, eax, 7

    pextrb  eax, xmm2, 0
    pinsrb  xmm3, eax, 8

    pextrb  eax, xmm2, 4
    pinsrb  xmm3, eax, 9

    pextrb  eax, xmm2, 8
    pinsrb  xmm3, eax, 10

    pextrb  eax, xmm2, 12
    pinsrb  xmm3, eax, 11

    movq    qword [rdi], xmm3
    psrldq  xmm3, 8
    movd    dword [rdi + 8], xmm3

    ret

; Compress 16 dwords stored in xmm0:xmm1:xmm2:xmm3 to bytes and write to address in rdi
; Params:
;     rdi: address to which data should be written
;     xmm0(packed dwords): dwords 0-3
;     xmm1(packed dwords): dwords 4-7
;     xmm2(packed dwords): dwords 8-11
;     xmm3(packed dwords): dwords 12-15
; Return:
;     -
compressd2b_and_write16:
    pextrb  eax, xmm0, 0
    pinsrb  xmm4, eax, 0

    pextrb  eax, xmm0, 4
    pinsrb  xmm4, eax, 1

    pextrb  eax, xmm0, 8
    pinsrb  xmm4, eax, 2

    pextrb  eax, xmm0, 12
    pinsrb  xmm4, eax, 3

    pextrb  eax, xmm1, 0
    pinsrb  xmm4, eax, 4

    pextrb  eax, xmm1, 4
    pinsrb  xmm4, eax, 5

    pextrb  eax, xmm1, 8
    pinsrb  xmm4, eax, 6

    pextrb  eax, xmm1, 12
    pinsrb  xmm4, eax, 7

    pextrb  eax, xmm2, 0
    pinsrb  xmm4, eax, 8

    pextrb  eax, xmm2, 4
    pinsrb  xmm4, eax, 9

    pextrb  eax, xmm2, 8
    pinsrb  xmm4, eax, 10

    pextrb  eax, xmm2, 12
    pinsrb  xmm4, eax, 11

    pextrb  eax, xmm3, 0
    pinsrb  xmm4, eax, 12

    pextrb  eax, xmm3, 4
    pinsrb  xmm4, eax, 13

    pextrb  eax, xmm3, 8
    pinsrb  xmm4, eax, 14

    pextrb  eax, xmm3, 12
    pinsrb  xmm4, eax, 15

    movdqu  [rdi], xmm4

    ret
