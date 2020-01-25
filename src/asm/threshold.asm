    section .rodata
    low_intens: dw 50, 50, 50, 50, 50, 50, 50, 50
    high_intens: dw 254, 254, 254, 254, 254, 254, 254, 254

    section .text
    global dbl_threshold

; Double threshold
; Params:
;     rdi: byte ptr to data, overwritten with output
;     esi: width in pixels
;     edx: height in pixels
;     xmm0 (scalar single precision): low threshold (in [0, 1])
;     xmm1 (scalar single precision): high threshold (in [0, 1])
; Return:
;     -
dbl_threshold:
.data       equ 0
.width      equ 8
.height     equ 12
.thres      equ 16
    push    rbp
    push    rbx
    mov     rbp, rsp
    and     rsp, -0x10
    sub     rsp, 32

    mov     qword [rsp + .data], rdi        ; Data to stack
    mov     dword [rsp + .width], esi
    mov     dword [rsp + .height], edx

    mov     r8, rdi                         ; Data pointer to r8

    pxor    xmm13, xmm13
    pxor    xmm14, xmm14

    movss   xmm13, xmm0                     ; Store thresholds
    movss   xmm14, xmm1

    xor     eax, eax

    call    find_maxpx                      ; Value of max pixel in al

    pxor    xmm0, xmm0
    pxor    xmm15, xmm15

    cvtsi2ss    xmm0, eax                   ; Max pixel value as single precision float
    movss   xmm1, xmm0

    mulss   xmm0, xmm13                     ; Low threshold in xmm0
    mulss   xmm1, xmm14                     ; High threshold in xmm1
    xor     r9d, r9d
    xor     r10d, r10d

    cvtss2si    r9d, xmm0                   ; Low threshold in r9d
    cvtss2si    r10d, xmm1                  ; High threshold in r10d

    xor     r11d, r11d

    mov     r11b, r9b                       ; Pack low threshold
    shl     r11w, 8
    or      r9w, r11w
    mov     r11w, r9w
    shl     r11d, 16
    or      r9d, r11d
    mov     r11d, r9d
    shl     r11, 32
    or      r9, r11                         ; Each byte in r9 has low threshold

    mov     qword [rsp + .thres], r9
    movq    xmm0, [rsp + .thres]            ; 8 low bytes of xmm0 have low threshold
    punpcklbw   xmm0, xmm15                 ; Each word in xmm0 has low threshold

    xor     r11d, r11d

    mov     r11b, r10b                      ; Pack high threshold
    shl     r11w, 8
    or      r10w, r11w
    mov     r11w, r10w
    shl     r11d, 16
    or      r10d, r11d
    mov     r11d, r10d
    shl     r11, 32
    or      r10, r11                        ; Each byte in r10 has high threshold

    mov     qword [rsp + .thres], r10
    movq    xmm1, [rsp + .thres]            ; 8 low bytes of xmm1 have high threshold
    punpcklbw   xmm1, xmm15                 ; Each word in xmm1 has high threshold

    mov     esi, dword [rsp + .width]       ; Width and height from stack
    mov     edx, dword [rsp + .height]

    imul    esi, edx                        ; Total number of bytes
    mov     eax, esi
    xor     edx, edx
    mov     ecx, 8                          ; Process 8 pixels per iteration
    idiv    ecx                             ; eax number of iterations
                                            ; edx remaining bytes

    movdqa  xmm4, xmm0                     ; Preserve xmm0 and xmm1
    movdqa  xmm5, xmm1

.process_batch:
    movq    xmm3, [r8]                      ; Load 8 bytes
    punpcklbw   xmm3, xmm15                 ; To words

    movdqa  xmm0, xmm4
    movdqa  xmm1, xmm5

    movdqa  xmm6, xmm3                      ; Preserve xmm3

    pcmpgtw xmm3, xmm0                      ; xmm0 mask for low threshold
    movdqa  xmm0, xmm3                      ; 0 if word is greater than low threshold, all 1's otherwise

    movdqa  xmm3, xmm6
    pcmpgtw xmm3, xmm1                      ; xmm1 mask for high threshold
    movdqa  xmm1, xmm3                      ; 0 if word is greater than high threshold, all 1's otherwise

    pxor    xmm0, xmm1                      ; xmm0 all ones if value larger than low and smaller than high

    movdqa  xmm3, xmm6
    movdqa  xmm3, xmm0                      ; Weak pixel mask
    pand    xmm3, [low_intens]              ; Set to low_intens values (effectively)

    movdqa  xmm6, xmm1                      ; Mask strong pixels
    pand    xmm6, [high_intens]             ; Set to high_intens values

    por    xmm3, xmm6                       ; Combine high and low values

    movq    rcx, xmm3                       ; 4 words to rcx, want low byte of each
    mov     byte [r8], cl                   ; Write to memory
    shr     rcx, 16
    mov     byte [r8 + 1], cl
    shr     rcx, 16
    mov     byte [r8 + 2], cl
    shr     rcx, 16
    mov     byte [r8 + 3], cl

    psrldq  xmm3, 8                         ; Shift out low 8 bytes
    movq    rcx, xmm3                       ; 8 words to rcx, want low byte of each
    mov     byte [r8 + 4], cl               ; Write to memory
    shr     rcx, 16
    mov     byte [r8 + 5], cl
    shr     rcx, 16
    mov     byte [r8 + 6], cl
    shr     rcx, 16
    mov     byte [r8 + 7], cl

    add     r8, 8                           ; Processing 8 bytes per iteration
    dec     eax
    jnz     .process_batch

.process_single:                            ; Process remaining bytes (< 8)
    mov     bl, byte [r8]
    mov     cl, bl

    cmp     bl, r9b
    cmova   cx, word [low_intens]
    cmp     bl, r10b
    cmova   cx, word [high_intens]

    mov     byte [r8], cl

    inc     r8
    dec     edx
    jnz     .process_single

.epi:
    mov     rsp, rbp
    pop     rbx
    pop     rbp
    ret

; Find max intensity in image
; Params:
;     rdi: byte ptr to data
;     esi: width in pixels
;     edi: height in pixels
; Return:
;     al: max intensity
find_maxpx:
    push    rbx

    imul    esi, edx                        ; Total size in bytes

    mov     eax, esi
    xor     edx, edx
    mov     ecx, 32
    idiv    ecx                             ; eax number of iterations
                                            ; edx remaining bytes to handle after loop
    pxor    xmm0, xmm0
    pxor    xmm1, xmm1

    xor     ecx, ecx                        ; ecx to hold max value

.process_batch:                             ; Max reduction over 32 byte batch
    movdqu  xmm0, [rdi]
    movdqu  xmm1, [rdi + 16]

    pmaxub  xmm0, xmm1                      ; xmm0 contains 16 max values of current 32 bytes

    movdqu  xmm1, xmm0
    psrldq  xmm1, 8                         ; High 8 bytes from xmm0 now in low 8 of xmm1

    pmaxub  xmm0, xmm1                      ; Low 8 bytes of xmm0 8 max values of current 32 bytes

    movq    xmm1, xmm0
    psrldq  xmm1, 4                         ; Bytes 4-7 (0-indexed) of xmm0 now in low 4 bytes of xmm1

    pmaxub  xmm0, xmm1                      ; Low 4 bytes of xmm0 4 max values of current 32 bytes

    movq    xmm1, xmm0
    psrldq  xmm1, 2                         ; Bytes 2 and 3 (0-indexed) of xmm0 now in low 2 bytes of xmm1

    pmaxub  xmm0, xmm1                      ; Low 2 bytes of xmm0 2 max values of current 32 bytes

    movq    xmm1, xmm0
    psrldq  xmm1, 1                         ; Byte 1 (0-indexed) of xmm0 now in low byte of xmm1

    pmaxub  xmm0, xmm1

    movd    ebx, xmm0
    and     bx, 0xff                        ; Zero everything but low byte in bx

    cmp     cl, bl
    cmovb   cx, bx                          ; New max to ecx if cl less than bl

    add     rdi, 32                         ; Processing 32 bytes per loop
    dec     eax
    jnz     .process_batch

    xor     ebx, ebx
.process_single:                            ; Process remaining bytes (< 32)
    mov     bl, byte [rdi]

    cmp     cl, bl
    cmovb   cx, bx

    inc     rdi
    dec     edx
    jnz     .process_single

    mov     al, cl
    pop     rbx
    ret
