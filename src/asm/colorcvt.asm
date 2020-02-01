    section .rodata
    align 16
    threes: dd 3.0, 3.0, 3.0, 3.0

    section .text
    global rgb2grayscale

; Convert rgb image to grayscale
; Params:
;     rdi: byte ptr to data, overwritten with output
;     esi: width of image (in pixels)
;     edx: height of image (in pixels)
;     rcx: dword pointer to number of channels
; Return:
;     eax: 0 on success, 1 on failure (image has 4 channels)
rgb2grayscale:
    push    rbx

    mov     ebx, dword [rcx]                ; Number of channels

    xor     eax, eax
    cmp     ebx, 1                          ; Already grayscale?
    je      .done

    cmp     ebx, 3
    je      .cvt

    inc     eax                             ; 4 channels, return 1
    jmp     .epi

.cvt:
    mov     dword [rcx], 1                  ; Set number of channels

    mov     r8, rdi                         ; Data pointer to r8
    mov     r9d, edx

    pxor    xmm7, xmm7

    movdqa  xmm14, [threes]
    pxor    xmm15, xmm15

    imul    esi, edx                        ; Number of pixels
    mov     eax, esi
    xor     edx, edx
    mov     ebx, 4
    idiv    ebx

    xor     ecx, ecx
    xor     esi, esi

.cvt_batch:
    movdqu  xmm0, [r8 + rcx]
    movdqa  xmm1, xmm0
    movdqa  xmm2, xmm0
    psrldq  xmm1, 1
    psrldq  xmm2, 2

    movdqa  xmm3, xmm0                      ; Preserve data
    movdqa  xmm4, xmm1
    movdqa  xmm5, xmm2

    punpcklbw   xmm0, xmm15                 ; Low bytes to words
    punpcklbw   xmm1, xmm15
    punpcklbw   xmm2, xmm15

    paddw   xmm0, xmm1
    paddw   xmm0, xmm2

    movdqa  xmm6, xmm0                      ; Preserve data

    punpcklwd   xmm0, xmm15                 ; Low words to single precision float
    cvtdq2ps    xmm0, xmm0

    divps   xmm0, xmm14
    cvtps2dq    xmm0, xmm0                  ; Back to dword

    pextrb  ebx, xmm0, 0                    ; First two bytes to lower bytes in xmm7
    pinsrb  xmm7, ebx, 0

    pextrb  ebx, xmm0, 12
    pinsrb  xmm7, ebx, 1

    movdqa  xmm0, xmm6                      ; Restore words
    punpckhwd   xmm0, xmm15                 ; High words to single precision float
    cvtdq2ps    xmm0, xmm0

    divps   xmm0, xmm14
    cvtps2dq    xmm0, xmm0                  ; To dword

    pextrb  ebx, xmm0, 8
    pinsrb  xmm7, ebx, 2                    ; Next byte to byte 3 in xmm7

    movdqa  xmm0, xmm3                      ; Restore bytes
    movdqa  xmm1, xmm4
    movdqa  xmm2, xmm5

    punpckhbw   xmm0, xmm15                 ; Low bytes to words
    punpckhbw   xmm1, xmm15
    punpckhbw   xmm2, xmm15

    paddw   xmm0, xmm1
    paddw   xmm0, xmm2

    punpcklwd   xmm0, xmm15                 ; To single precision float
    cvtdq2ps    xmm0, xmm0

    divps   xmm0, xmm14
    cvtps2dq    xmm0, xmm0                  ; Divide and back to dword

    pextrb  ebx, xmm0, 4                    ; Extract byte and store in byte 3 in xmm7
    pinsrb  xmm7, ebx, 3

    movd    ebx, xmm7

    mov     dword [r8 + rsi], ebx           ; Write to memory

    add     esi, 4
    add     ecx, 12
    dec     eax
    jnz     .cvt_batch

    cmp     edx, 0                          ; Done if there is no remainder
    je      .done

    mov     edi, edx
    mov     r10d, 3

.cvt_bytes:
    xor     ax, ax
    mov     al, byte [r8 + rcx]
    mov     bl, byte [r8 + rcx + 1]
    mov     dl, byte [r8 + rcx + 2]

    add     ax, bx
    add     ax, dx
    xor     edx, edx
    idiv    r10d
    mov     byte [r8 + rsi], al

    inc     esi
    add     ecx, 3
    dec     edi
    jnz     .cvt_bytes

.done:
    xor     eax, eax
.epi:
    pop     rbx
    ret
