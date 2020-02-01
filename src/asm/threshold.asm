    section .rodata
    align 16
    low_intens: dw 50, 50, 50, 50, 50, 50, 50, 50
    high_intens: dw 255, 255, 255, 255, 255, 255, 255, 255

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
    push    rbx
    sub     rsp, 16

    mov     qword [rsp + .data], rdi        ; Data to stack
    mov     dword [rsp + .width], esi
    mov     dword [rsp + .height], edx

    mov     r8, rdi                         ; Data pointer to r8

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

    movq    xmm0, r9
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

    movq    xmm1, r10
    punpcklbw   xmm1, xmm15                 ; Each word in xmm1 has high threshold

    mov     esi, dword [rsp + .width]       ; Width and height from stack
    mov     edx, dword [rsp + .height]
    movdqa  xmm6, [low_intens]              ; Intensity values to xmm6 and xmm7
    movdqa  xmm7, [high_intens]

    imul    esi, edx                        ; Total number of bytes
    mov     eax, esi
    xor     edx, edx
    mov     ecx, 8                          ; Process 8 pixels per iteration
    idiv    ecx                             ; eax number of iterations
                                            ; edx remaining bytes

    movdqa  xmm3, xmm0                     ; Preserve xmm0 and xmm1
    movdqa  xmm4, xmm1

.process_batch:
    movq    xmm2, [r8]                      ; Load 8 bytes
    punpcklbw   xmm2, xmm15                 ; To words

    movdqa  xmm0, xmm3
    movdqa  xmm1, xmm4

    movdqa  xmm5, xmm2                      ; Preserve xmm2

    pcmpgtw xmm2, xmm0                      ; 0 if word is less than low threshold, all 1's otherwise
    movdqa  xmm0, xmm2                      ; xmm0 mask for low threshold

    movdqa  xmm2, xmm5
    pcmpgtw xmm2, xmm1                      ; 0 if word is less than high threshold, all 1's otherwise
    movdqa  xmm1, xmm2                      ; xmm1 mask for high threshold

    pxor    xmm0, xmm1                      ; xmm0 all ones if value larger than low and smaller than high

    movdqa  xmm2, xmm5
    movdqa  xmm2, xmm0                      ; Weak pixel mask
    pand    xmm2, xmm6                      ; Set to low_intens values (effectively)

    movdqa  xmm5, xmm1                      ; Mask strong pixels
    pand    xmm5, xmm7                      ; Set to high_intens values

    por     xmm2, xmm5                      ; Combine high and low values

    xor     ecx, ecx
    pextrb  ebx, xmm2, 14                   ; Low byte of each word in xmm2 to rcx
    mov     cl, bl
    shl     ecx, 8
    pextrb  ebx, xmm2, 12
    mov     cl, bl
    shl     ecx, 8
    pextrb  ebx, xmm2, 10
    mov     cl, bl
    shl     ecx, 8
    pextrb  ebx, xmm2, 8
    mov     cl, bl
    shl     rcx, 8
    pextrb  ebx, xmm2, 6
    mov     cl, bl
    shl     rcx, 8
    pextrb  ebx, xmm2, 4
    mov     cl, bl
    shl     rcx, 8
    pextrb  ebx, xmm2, 2
    mov     cl, bl
    shl     rcx, 8
    pextrb  ebx, xmm2, 0
    mov     cl, bl

    mov     qword [r8], rcx                 ; Write to memory

    add     r8, 8                           ; Processing 8 bytes per iteration
    dec     eax
    jnz     .process_batch

    cmp     edx, 0                          ; If no remaining bytes, jump to epilogue
    je      .epi

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
    add     rsp, 16
    pop     rbx
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

    cmp     edx, 0                          ; Bytes multiple of 32, no more work
    je      .done

.process_single:                            ; Process remaining bytes (< 32)
    mov     bl, byte [rdi]

    cmp     cl, bl
    cmovb   cx, bx

    inc     rdi
    dec     edx
    jnz     .process_single

.done:
    mov     al, cl
.epi:
    pop     rbx
    ret
