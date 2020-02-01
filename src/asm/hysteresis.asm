    section .text
    global hysteresis

    extern malloc
    extern free

; Track edges based on hysteresis
; Params:
;     rdi: byte ptr to data, overwritten with output
;     esi: width in pixels
;     edx: height in pixels
; Return:
;     eax: 0 on success, 1 on malloc failure, 2 on unsuitable dims
hysteresis:
.data       equ 0
.width      equ 8
.height     equ 12
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 16

    mov     eax, 2
    cmp     esi, 15                         ; Verify dimensions
    jl      .epi
    cmp     edx, 3
    jl      .epi

    mov     qword [rsp + .data], rdi        ; Data to stack
    mov     dword [rsp + .width], esi
    mov     dword [rsp + .height], edx

    mov     edi, esi                        ; Number of bytes to allocate
    imul    edi, edx

    call    malloc

    cmp     rax, 0
    jne     .malloc_succ

    inc     eax
    jmp     .epi

.malloc_succ:
    mov     r8, rax                         ; Address of tmp array to r8
    mov     r14, qword [rsp + .data]
    mov     r11, r14                        ; Data address to r11
    mov     esi, dword [rsp + .width]       ; Width and height to esi and edx
    mov     edx, dword [rsp + .height]

    mov     ecx, 13                         ; First 13 cols handled separately
    mov     ebx, esi
    sub     ebx, 13                         ; Last 13 cols handled separately

    mov     r9, r8                          ; Address of tmp array
    lea     r12, [r11 + rsi]                ; Address of first byte in second row

    pcmpeqd xmm10, xmm10                    ; All 1's

; Upper left corner
    movdqu  xmm3, [r11]                     ; Load 16 bytes from row 0
    movdqa  xmm4, xmm3                      ; Bytes 0,...,15 in row 0
    movdqa  xmm5, xmm3

    pslldq  xmm3, 1                         ; Duplicate byte 0
    pextrb  eax, xmm3, 1
    pinsrb  xmm3, eax, 0                    ; Bytes 0,0,1,2,3,...,13,14 in row 0

    psrldq  xmm5, 1                         ; Bytes 1,...,15 in row 0

    movdqu  xmm6, [r12]                     ; Load bytes from row 1
    movdqa  xmm7, xmm6                      ; Bytes 0,...,15 in row 1
    movdqa  xmm8, xmm6

    pslldq  xmm6, 1                         ; Duplicate byte 0
    pextrb  eax, xmm6, 1
    pinsrb  xmm6, eax, 0                    ; Bytes 0,0,1,2,3,...,13,14 in row 1

    psrldq  xmm8, 1                         ; Bytes 1,...,15 in row 1

    pmaxub  xmm3, xmm4
    pmaxub  xmm3, xmm5
    pmaxub  xmm6, xmm7
    pmaxub  xmm6, xmm8
    pmaxub  xmm3, xmm6                      ; Max intensities over first 13 bytes in rows 0 and 1

    pxor    xmm9, xmm9                      ; Clear bits
    
    pcmpeqb xmm4, xmm9                      ; All bits to 1 if byte is 0
    pandn   xmm4, xmm10                     ; One's complement => all bits 1 if byte was non-zero

    pand    xmm3, xmm4                      ; Bytes 255 iff they should be kept

    pcmpgtb xmm9, xmm3                      ; Byte 255 when unsigned => sign bit set when signed
                                            ; All bits for bytes that should not be kept 0

    movdqu  [r9], xmm9                      ; Write to tmp address

; Center part of top row
.tr_batch:
    movdqu  xmm3, [r11 + rcx - 1]           ; Bytes -1,0,1...,14 in batch
    movdqa  xmm4, xmm3
    movdqa  xmm5, xmm3
    psrldq  xmm4, 1                         ; Bytes 0,...,14 in lower 15 bits
    psrldq  xmm5, 2                         ; Bytes 1,...,14 in lower 14 bits

    movdqu  xmm6, [r12 + rcx - 1]           ; Bytes -1,0,1,...,14
    movdqa  xmm7, xmm6
    movdqa  xmm8, xmm6
    psrldq  xmm7, 1                         ; Bytes 0,...,14 in lower 15 bits
    psrldq  xmm8, 2                         ; Bytes 1,...,14 in lower 14 bits

    pmaxub  xmm3, xmm4
    pmaxub  xmm3, xmm5
    pmaxub  xmm6, xmm7
    pmaxub  xmm6, xmm8
    pmaxub  xmm3, xmm6                      ; Max intensities over batch

    pxor    xmm9, xmm9                      ; Clear bits
    
    pcmpeqb xmm4, xmm9
    pandn   xmm4, xmm10                     ; All 1's if byte should be kept

    pand    xmm3, xmm4                      ; Bytes 255 iff they should be kept

    pcmpgtb xmm9, xmm3                      ; Zero the bits in bytes not to keep

    movdqu  [r9 + rcx], xmm9                ; Write to tmp address

    add     ecx, 12                         ; Processing 12 pixels per iteration
    cmp     ecx, ebx
    jl      .tr_batch

; Upper right corner
    mov     eax, esi
    sub     eax, ecx                        ; Remaining number of bytes on row
    mov     r13d, 13
    sub     r13d, eax                       ; Bytes to go back in order to have exactly 13 bytes left in row
    sub     ecx, r13d                       ; Now ebx - ecx = 13

    movdqu  xmm3, [r11 + rcx - 1]           ; Bytes -1,0,1,...,14
    movdqa  xmm4, xmm3
    movdqa  xmm5, xmm3
    psrldq  xmm4, 1                         ; Bytes 0,...,14 in lower 15 bytes
    psrldq  xmm5, 2                         ; Bytes 1,...,14 in lower 14 bytes
    pextrb  eax, xmm5, 14                   ; Duplicate byte 14
    pinsrb  xmm5, eax, 15                   ; Bytes 1,2,...,13,14,14 in lower 15 bytes

    movdqu  xmm6, [r12 + rcx - 1]           ; Bytes -1,0,1,...,14
    movdqa  xmm7, xmm6
    movdqa  xmm8, xmm6
    psrldq  xmm7, 1                         ; Bytes 0,...,14 in lower 15 bytes
    psrldq  xmm8, 2                         ; Bytes 1,...,14 in lower 14 bytes
    pextrb  eax, xmm8, 14                   ; Duplicate byte 14
    pinsrb  xmm8, eax, 15                   ; Bytes 1,2,...,13,14,14 in lower 15 bytes

    pmaxub  xmm3, xmm4
    pmaxub  xmm3, xmm5
    pmaxub  xmm6, xmm7
    pmaxub  xmm6, xmm8
    pmaxub  xmm3, xmm6                      ; Max intensities over batch
    
    pxor    xmm9, xmm9                      ; Clear bits

    pcmpeqb xmm4, xmm9                      ; All bits to 1 if byte is 0
    pandn   xmm4, xmm10                     ; One's complement

    pand    xmm3, xmm4                      ; Bytes 255 iff they should be kept

    pcmpgtb xmm9, xmm3                      ; Zero the bits in bytes not to keep

    movdqu  [r9 + rcx], xmm9                ; Write to tmp address
    
    mov     r10, r11                        ; Advance to next set of rows
    add     r11, rsi
    add     r12, rsi
    add     r9, rsi

    sub     edx, 2                          ; Number of iterations for row loop

.vloop:                                     ; Rows 1 to height - 1
; 13 leftmost cols
    movdqu  xmm0, [r10]                     ; First row in batch
    movdqa  xmm1, xmm0                      ; Bytes 0,...,15
    movdqa  xmm2, xmm0

    pslldq  xmm0, 1
    pextrb  eax, xmm0, 1
    pinsrb  xmm0, eax, 0                    ; Bytes 0,0,1,...,14

    psrldq  xmm2, 1                         ; Bytes 1,...,15 in lower 15 bytes

    movdqu  xmm3, [r11]                     ; Second row in batch
    movdqa  xmm4, xmm3                      ; Bytes 0,...,15
    movdqa  xmm5, xmm3

    pslldq  xmm3, 1
    pextrb  eax, xmm3, 1
    pinsrb  xmm3, eax, 0                    ; Bytes 0,0,1,...,14

    psrldq  xmm5, 1                         ; Bytes 1,...,15 in lower 15 bytes

    movdqu  xmm6, [r12]                     ; Third row in batch
    movdqa  xmm7, xmm6                      ; Bytes 0,...,15
    movdqa  xmm8, xmm6

    pslldq  xmm6, 1
    pextrb  eax, xmm6, 1
    pinsrb  xmm6, eax, 0                    ; Bytes 0,0,1,...,14

    psrldq  xmm8, 1                         ; Bytes 1,...,15 in lower 15 bytes

    pmaxub  xmm0, xmm1
    pmaxub  xmm0, xmm2
    pmaxub  xmm3, xmm4
    pmaxub  xmm3, xmm5
    pmaxub  xmm6, xmm7
    pmaxub  xmm6, xmm8
    pmaxub  xmm0, xmm3
    pmaxub  xmm0, xmm6                      ; Max bytes of neighborhoods in batch

    pxor    xmm9, xmm9                      ; Clear bits

    pcmpeqb xmm4, xmm9
    pandn   xmm4, xmm10                     ; Set bits of non-zero

    pand    xmm0, xmm4                      ; Bytes 255 iff they should be kept

    pcmpgtb xmm9, xmm0                      ; Zero bits for bytes not to keep

    movdqu  [r9], xmm9                      ; Write to tmp address

; Middle part
    mov     ecx, 13                         ; First 13 bytes already handled

.m_batch:
    movdqu  xmm0, [r10 + rcx - 1]           ; Bytes -1,0,1,...,14
    movdqa  xmm1, xmm0
    movdqa  xmm2, xmm0
    psrldq  xmm1, 1                         ; Bytes 0,...,14 in lower 15 bytes
    psrldq  xmm2, 2                         ; Bytes 1,...,14 in lower 14 bytes

    movdqu  xmm3, [r11 + rcx - 1]           ; Bytes -1,0,1,...,14
    movdqa  xmm4, xmm3
    movdqa  xmm5, xmm3
    psrldq  xmm4, 1                         ; Bytes 0,...,14 in lower 15 bytes
    psrldq  xmm5, 2                         ; Bytes 1,...,14 in lower 14 bytes

    movdqu  xmm6, [r12 + rcx - 1]           ; Bytes -1,0,1,...,14
    movdqa  xmm7, xmm6
    movdqa  xmm8, xmm6
    psrldq  xmm7, 1                         ; Bytes 0,...,14 in lower 15 bytes
    psrldq  xmm8, 2                         ; Bytes 1,...,14 in lower 14 byts

    pmaxub  xmm0, xmm1
    pmaxub  xmm0, xmm2
    pmaxub  xmm3, xmm4
    pmaxub  xmm3, xmm5
    pmaxub  xmm6, xmm7
    pmaxub  xmm6, xmm8
    pmaxub  xmm0, xmm3
    pmaxub  xmm0, xmm6                      ; Max intensities over batch

    pxor    xmm9, xmm9                      ; Clear bits
    
    pcmpeqb xmm4, xmm9
    pandn   xmm4, xmm10                     ; Set bits for bytes to keep

    pand    xmm0, xmm4                      ; Bytes 255 iff they should be kept

    pcmpgtb xmm9, xmm0                      ; Zero bits for bytes not to keep

    movdqu  [r9 + rcx], xmm9                ; Write to tmp address

    add     ecx, 12                         ; Processing 12 pixels per iteration
    cmp     ecx, ebx
    jl      .m_batch

; 13 rightmost cols
    mov     eax, esi
    sub     eax, ecx                        ; Remaining number of bytes on row
    mov     r13d, 13
    sub     r13d, eax                       ; Bytes to go back in order to have exactly 14 bytes left in row
    sub     ecx, r13d                       ; ebx - ecx = 13

    movdqu  xmm0, [r10 + rcx - 1]           ; Bytes -1,0,1,...,14 of first row in batch
    movdqa  xmm1, xmm0
    movdqa  xmm2, xmm0
    psrldq  xmm1, 1                         ; Bytes 0,...,14 in lower 15 bytes
    psrldq  xmm2, 2                         ; Bytes 1,...,14 in lower 14 bytes
    pextrb  eax, xmm2, 14                   ; Duplicate byte 14
    pinsrb  xmm2, eax, 15                   ; Bytes 0,1,2,...,13,14,14 in lower 15 bytes

    movdqu  xmm3, [r11 + rcx - 1]           ; Bytes -1,0,1,...,14 of first row in batch
    movdqa  xmm4, xmm3
    movdqa  xmm5, xmm3
    psrldq  xmm4, 1                         ; Bytes 0,...,14 in lower 15 bytes
    psrldq  xmm5, 2                         ; Bytes 1,...,14 in lower 14 bytes
    pextrb  eax, xmm5, 14                   ; Duplicate byte 14
    pinsrb  xmm5, eax, 15                   ; Bytes 0,1,2,...,13,14,14 in lower 15 bytes

    movdqu  xmm6, [r12 + rcx - 1]           ; Bytes -1,0,1,...,14
    movdqa  xmm7, xmm6
    movdqa  xmm8, xmm6
    psrldq  xmm7, 1                         ; Bytes 0,...,14 in lower 15 bytes
    psrldq  xmm8, 2                         ; Bytes 1,...,14 in lower 14 bytes
    pextrb  eax, xmm8, 14                   ; Duplicate byte 14
    pinsrb  xmm8, eax, 15                   ; Bytes 1,2,...,13,14,14 in lower 15 bytes

    pmaxub  xmm0, xmm1
    pmaxub  xmm0, xmm2
    pmaxub  xmm3, xmm4
    pmaxub  xmm3, xmm5
    pmaxub  xmm6, xmm7
    pmaxub  xmm6, xmm8
    pmaxub  xmm0, xmm3
    pmaxub  xmm0, xmm6                      ; Max intensities over batch

    pxor    xmm9, xmm9
    
    pcmpeqb xmm4, xmm9
    pandn   xmm4, xmm10                     ; Set bits for bytes to keep

    pand    xmm0, xmm4                      ; Bytes 255 iff they should be kept

    pcmpgtb xmm9, xmm0                      ; Zero bits not to keep

    movdqu  [r9 + rcx], xmm9                ; Write to tmp address

    add     r9, rsi                         ; Next set of rows
    add     r10, rsi
    add     r11, rsi
    add     r12, rsi
    dec     edx
    jnz     .vloop

; Lower left corner
    movdqu  xmm0, [r10]
    movdqa  xmm1, xmm0                      ; Bytes 0,...,15
    movdqa  xmm2, xmm0

    pslldq  xmm0, 1
    pextrb  eax, xmm0, 1
    pinsrb  xmm0, eax, 0                    ; Bytes 0,0,1,...,14

    psrldq  xmm2,1                          ; Bytes 1,...,15 in lower 15 bytes

    movdqu  xmm3, [r11]
    movdqa  xmm4, xmm3                      ; Bytes 0,...,15
    movdqa  xmm5, xmm3

    pslldq  xmm3, 1
    pextrb  eax, xmm3, 1
    pinsrb  xmm3, eax, 1                    ; Bytes 0,0,1,...,14

    psrldq  xmm5, 1                         ; Bytes 1,...,15 in lower 15 bytes

    pmaxub  xmm0, xmm1
    pmaxub  xmm0, xmm2
    pmaxub  xmm3, xmm4
    pmaxub  xmm3, xmm5
    pmaxub  xmm0, xmm3                      ; Max instensities of batch

    pxor    xmm9, xmm9                      ; Clear bits

    pcmpeqb xmm4, xmm9
    pandn   xmm4, xmm10                     ; Set bits to keep

    pand    xmm0, xmm4

    pcmpgtb xmm9, xmm0                      ; All 1's for bytes to be kept

    movdqu  [r9], xmm9

; Center part of bottom row
    mov     ecx, 13                         ; 13 bytes already processed
.br_batch:
    movdqu  xmm0, [r10 + rcx - 1]           ; Bytes -1,0,1,...,14
    movdqa  xmm1, xmm0
    movdqa  xmm2, xmm0
    psrldq  xmm1, 1                         ; Bytes 0,...,14 in lower 15 bytes
    psrldq  xmm2, 2                         ; Bytes 1,...,14 in lower 14 bytes

    movdqu  xmm3, [r11 + rcx - 1]           ; Bytes -1,0,1,...,14
    movdqa  xmm4, xmm3
    movdqa  xmm5, xmm3
    psrldq  xmm4, 1                         ; Bytes 0,...,14 in lower 15 bytes
    psrldq  xmm5, 2                         ; Bytes 1,...,14 in lower 14 bytes

    pmaxub  xmm0, xmm1
    pmaxub  xmm0, xmm2
    pmaxub  xmm3, xmm4
    pmaxub  xmm3, xmm5
    pmaxub  xmm0, xmm3                      ; Max intensities of batch

    pxor    xmm9, xmm9                      ; Clear bits
    
    pcmpeqb xmm4, xmm9
    pandn   xmm4, xmm10                     ; Set bits for bytes to keep

    pand    xmm0, xmm4                      ; Bytes 255 iff they should be kept

    pcmpgtb xmm9, xmm0                      ; Zero bits not to keep

    movdqu  [r9 + rcx], xmm9                ; Write to tmp address

    add     ecx, 12                         ; Processing 12 pixels per iteration
    cmp     ecx, ebx
    jl      .br_batch
    
; Lower right corner
    mov     eax, esi
    sub     eax, ecx                        ; Remaining number of bytes on row
    mov     r13d, 13
    sub     r13d, eax                       ; Bytes to go back in order to have exactly 13 bytes left in row
    sub     ecx, r13d                       ; ebx - ecx = 13

    movdqu  xmm0, [r10 + rcx - 1]           ; Bytes -1,0,1,...,14
    movdqa  xmm1, xmm0
    movdqa  xmm2, xmm0
    psrldq  xmm1, 1                         ; Bytes 0,...,14 in lower 15 bytes
    psrldq  xmm2, 2                         ; Bytes 1,...14 in lower 14 bytes
    pextrb  eax, xmm2, 14                   ; Duplicate byte 14
    pinsrb  xmm2, eax, 15                   ; Bytes 0,1,2,...,13,14,14 in lower 15 bytes

    movdqu  xmm3, [r11 + rcx - 1]           ; Bytes -1,0,1,...,14
    movdqa  xmm4, xmm3
    movdqa  xmm5, xmm3
    psrldq  xmm4, 1                         ; Bytes 0,...,14 in lower 15 bytes
    psrldq  xmm5, 2                         ; Bytes 1,...,14 in lower 14 bytes
    pextrb  eax, xmm5, 14                   ; Duplicate byte 14
    pinsrb  xmm5, eax, 15                   ; Bytes 1,2,...,13,14,14 in lower 15 bytes

    pmaxub  xmm0, xmm1
    pmaxub  xmm0, xmm2
    pmaxub  xmm3, xmm4
    pmaxub  xmm3, xmm5
    pmaxub  xmm0, xmm3                      ; Max intensities

    pxor    xmm9, xmm9
    
    pcmpeqb xmm4, xmm9
    pandn   xmm4, xmm10                     ; Set bits for bytes to keep

    pand    xmm0, xmm4                      ; Bytes 255 iff they should be kept

    pcmpgtb xmm9, xmm0                      ; Zero bits not to keep

    movdqu  [r9 + rcx], xmm9                ; Write to tmp address


    mov     eax, dword [rsp + .height]
    imul    eax, esi                        ; Total number of bytes
    xor     edx, edx
    mov     ecx, 8
    idiv    ecx

    mov     r9, r8

.copy_qwords:
    mov     rbx, qword [r9]
    mov     qword [r14], rbx
    add     r9, 8
    add     r14, 8

    dec     eax
    jnz     .copy_qwords

.copy_bytes:
    mov     bl, byte [r9]
    mov     byte [r14], bl
    inc     r9
    inc     r14

    dec     edx
    jnz     .copy_bytes

.free:
    mov     rdi, r8
    call    free

    xor     eax, eax
.epi:
    add     rsp, 16
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
