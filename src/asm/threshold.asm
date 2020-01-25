    section .rodata
    low_intensity: db 127
    high_intensity: db 255

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

.process_batch:                             ; Max reduction over 32 byte batche
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
    and     ebx, 0xff                       ; Zero everything but low byte in ebx

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
