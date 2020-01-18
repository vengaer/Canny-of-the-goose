    section .text
    global sobel

    extern malloc
    extern free

; Apply sobel kernels
; Params:
;     rdi: byte ptr to data, overwritten with output
;     rsi: dword ptr to width in pixels
;     rdx: dword ptr to height in pixels
; Return:
;     eax: 0 on success, 1 on malloc failure, 2 if dims are unacceptable
sobel:
.data       equ 0
.width      equ 8
.height     equ 12
.waddr      equ 16
.haddr      equ 24
.f2b        equ 32                          ; Used for compressing single precision float to byte
    push    rbp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbp, rsp
    and     rsp, -0x10
    sub     rsp, 64

    mov     qword [rsp + .data], rdi        ; Data to stack
    mov     qword [rsp + .waddr], rsi
    mov     qword [rsp + .haddr], rdx

    mov     esi, dword [rsi]                ; Read width and height
    mov     edx, dword [rdx]

    mov     dword [rsp + .width], esi
    mov     dword [rsp +.height], edx

    mov     eax, 2                          ; Return 2 if dims are unsuitable
    cmp     esi, 3                          ; Image must have at least 3 cols
    jl      .epi
    cmp     edx, 3                          ; Image must have at least 3 rows
    jl      .epi

    mov     edi, esi                        ; Number of bytes to allocate
    imul    edi, edx

    call    malloc

    cmp     eax, 0
    jne     .malloc_succ

    inc     eax                             ; return 1
    jmp     .epi

.malloc_succ:
    mov     r9, rax                         ; tmp ptr to r9

    mov     r8, qword [rsp + .data]         ; data to r8
    mov     esi, dword [rsp + .width]       ; width and height back to esi and edx
    mov     edx, dword [rsp + .height]

    mov     r10, r8                         ; Address of first byte in first row
    mov     r11, r10
    add     r11, rsi                        ; Address of first byte in second row
    mov     r12, r11
    add     r12, rsi                        ; Address of first byte in third row
    mov     r13, r9                         ; tmp ptr to r13

    pxor    xmm15, xmm15

    mov     ecx, edx                        ; Number of rows to process
    sub     ecx, 2

    mov     ebx, esi                        ; Number of cols to process
    sub     ebx, 2

.row_loop:
    xor     eax, eax                        ; eax counter for inner loop (cols)

.col_loop:

; First row
    movdqu  xmm0, [r10 + rax]
    movdqa  xmm1, xmm0
    movdqa  xmm2, xmm0
    psrldq  xmm1, 1                         ; Shift one byte right
    psrldq  xmm2, 2                         ; Shift 2 bytes right

                                            ; Respective bytes in xmm0, xmm1 and xmm2 now
                                            ; hold enough data for 14 applications of the
                                            ; filter kernel

    movdqa  xmm3, xmm0                      ; Preserve xmm0, xmm1 and xmm2
    movdqa  xmm4, xmm1
    movdqa  xmm5, xmm2

    punpcklbw   xmm3, xmm15                 ; Zero extend low 8 bytes (need more than 8 bits
    punpcklbw   xmm4, xmm15                 ; for the computations), xmm3-5 account for 8
    punpcklbw   xmm5, xmm15                 ; first of the 14 kernel applications

    pxor    xmm6, xmm6                      ; Horizontal kernel, first 8 bytes
    pxor    xmm7, xmm7                      ; Vertical kernel, first 8 bytes

    psubw   xmm6, xmm3                      ; Horizontal kernel: subtract first col
    paddw   xmm6, xmm5                      ; Add third

    psubw   xmm7, xmm3                      ; Vertical kernel: subtract first col
    psubw   xmm7, xmm4                      ; Subtract second col twice
    psubw   xmm7, xmm4
    psubw   xmm7, xmm5                      ; Subtract third col

    pxor    xmm8, xmm8                      ; Horizontal kernel, remaining 6 bytes
    pxor    xmm9, xmm9                      ; Vertical kernel, remaining 6 bytes

    punpckhbw   xmm0, xmm15                 ; Convert high 8 bytes to word
    punpckhbw   xmm1, xmm15
    punpckhbw   xmm2, xmm15

    psubw   xmm8, xmm0                      ; Horizontal kernel: subtract first col
    paddw   xmm8, xmm2                      ; Add third col

    psubw   xmm9, xmm0                      ; Vertical kernel: subtract first col
    psubw   xmm9, xmm1                      ; Subtract second col twice
    psubw   xmm9, xmm1
    psubw   xmm9, xmm2                      ; Subtract third col

; Second row
    movdqu  xmm0, [r11 + rax]               ; Center pixel used in neigther horizontal or
    movdqa  xmm2, xmm0                      ; vertical kernel, no need for xmm1

    psrldq  xmm2, 2

    movdqa  xmm3, xmm0
    movdqa  xmm5, xmm2

    punpcklbw   xmm3, xmm15
    punpcklbw   xmm5, xmm15

    psubw   xmm6, xmm3                      ; Horizontal kernel, subtract first col twice
    psubw   xmm6, xmm3
    paddw   xmm6, xmm5                      ; Subtract third col twice
    paddw   xmm6, xmm5

                                            ; Nothing to do with vertical kernel

    punpckhbw   xmm0, xmm15                 ; Same for 6 high bytes
    punpckhbw   xmm2, xmm15

    psubw   xmm8, xmm0
    psubw   xmm8, xmm0
    paddw   xmm8, xmm2
    paddw   xmm8, xmm2

; Third row
    movdqu  xmm0, [r12 + rax]
    movdqa  xmm1, xmm0
    movdqa  xmm2, xmm0
    psrldq  xmm1, 1
    psrldq  xmm2, 2

    movdqa  xmm3, xmm0
    movdqa  xmm4, xmm1
    movdqa  xmm5, xmm2

    punpcklbw   xmm3, xmm15
    punpcklbw   xmm4, xmm15
    punpcklbw   xmm5, xmm15

    psubw   xmm6, xmm3                      ; Horizontal kernel, subtract first col
    paddw   xmm6, xmm5                      ; Add third col

    paddw   xmm7, xmm3                      ; Vertical kernel, add first col
    paddw   xmm7, xmm4                      ; Add second col twice
    paddw   xmm7, xmm4
    paddw   xmm7, xmm5                      ; Add third col

    punpckhbw   xmm0, xmm15                 ; Same for high 6 bytes
    punpckhbw   xmm1, xmm15
    punpckhbw   xmm2, xmm15

    psubw   xmm8, xmm0
    paddw   xmm8, xmm2

    paddw   xmm9, xmm0
    paddw   xmm9, xmm1
    paddw   xmm9, xmm2
    paddw   xmm9, xmm2

; Compute values
    pmullw  xmm6, xmm6                      ; Square
    pmullw  xmm7, xmm7
    pmullw  xmm8, xmm8
    pmullw  xmm9, xmm9

    paddw   xmm6, xmm7                      ; Sum of squares
    paddw   xmm8, xmm9

    movdqa  xmm1, xmm6
    movdqa  xmm3, xmm8

    punpcklwd   xmm6, xmm15                 ; Low 4 words to dwords
    punpcklwd   xmm8, xmm15

    punpckhwd   xmm1, xmm15                 ; High 4 words to dwords
    punpckhwd   xmm3, xmm15

    cvtdq2ps    xmm0, xmm6                  ; Convert to packed single precision float
    cvtdq2ps    xmm1, xmm1
    cvtdq2ps    xmm2, xmm8
    cvtdq2ps    xmm3, xmm3

    sqrtps      xmm0, xmm0                  ; Compute sqrt
    sqrtps      xmm1, xmm1
    sqrtps      xmm2, xmm2
    sqrtps      xmm3, xmm3

    cvtps2dq    xmm0, xmm0                  ; Convert back to packed integers
    cvtps2dq    xmm1, xmm1
    cvtps2dq    xmm2, xmm2
    cvtps2dq    xmm3, xmm3

    movdqa  [rsp + .f2b], xmm0              ; 4 values on stack, each 32 bits
    mov     r14, qword [rsp + .f2b]         ; 8 least significant bytes to r14
    mov     byte [r13 + rax + 1], r14b      ; Write first byte
    shr     r14, 32                         ; Shift out lower 32 bits
    mov     byte [r13 + rax + 2], r14b      ; Write second byte and shift out lower 32 bits

    mov     r14, qword [rsp + .f2b + 8]     ; 8 most significant bytes to r14
    mov     byte [r13 + rax + 3], r14b      ; Write bytes
    shr     r14, 32
    mov     byte [r13 + rax + 4], r14b

    movdqa  [rsp + .f2b], xmm1              ; 4 values on stack, each 32 bits
    mov     r14, qword [rsp + .f2b]         ; 8 least significant bytes to r14
    mov     byte [r13 + rax + 5], r14b      ; Write first byte
    shr     r14, 32                         ; Shift out lower 32 bits
    mov     byte [r13 + rax + 6], r14b      ; Write second byte and shift out lower 32 bits

    mov     r14, qword [rsp + .f2b + 8]     ; 8 most significant bytes to r14
    mov     byte [r13 + rax + 7], r14b      ; Write bytes
    shr     r14, 32
    mov     byte [r13 + rax + 8], r14b

    movdqa  [rsp + .f2b], xmm2              ; 4 values on stack, each 32 bits
    mov     r14, qword [rsp + .f2b]         ; 8 least significant bytes to r14
    mov     byte [r13 + rax + 9], r14b      ; Write first byte
    shr     r14, 32                         ; Shift out lower 32 bits
    mov     byte [r13 + rax + 10], r14b     ; Write second byte and shift out lower 32 bits

    mov     r14, qword [rsp + .f2b + 8]     ; 8 most significant bytes to r14
    mov     byte [r13 + rax + 11], r14b     ; Write bytes
    shr     r14, 32
    mov     byte [r13 + rax + 12], r14b

    movq    [rsp + .f2b], xmm3
    mov     r14, qword [rsp + .f2b]         ; 8 least significant bytes to r14
    mov     byte [r13 + rax + 13], r14b     ; Write first byte
    shr     r14, 32                         ; Shift out lower 32 bits
    mov     byte [r13 + rax + 14], r14b     ; Write second byte and shift out lower 32 bits


    add     eax, 14                         ; 14 values processes in parallel
    cmp     eax, ebx
    jl      .col_loop

    add     r10, rsi                        ; Advance to next set of rows
    add     r11, rsi
    add     r12, rsi
    add     r13, rbx

    dec     ecx
    jnz     .row_loop

    sub     esi, 2
    sub     edx, 2
    mov     r15, qword [rsp + .waddr]
    mov     dword [r15], esi
    mov     r15, qword [rsp + .haddr]
    mov     dword [r15], edx

.write_result:
    mov     ecx, esi                        ; Number of bytes to ecx
    imul    ecx, edx

    xor     edx, edx                        ; Number of bytes multiple of 4?
    mov     eax, ecx
    mov     ebx, 4
    div     ebx
    cmp     edx, 0

    jnz     .copy_bytewise                  ; Not multiple of 4, copy byte by byte

    sub     ecx, 4                          ; Otherwise, multiple of 4, copy chunks of 32-bits
.write_dword:
    mov     ebx, dword [r9 + rcx]           ; Copy dwords
    mov     dword [r8 + rcx], ebx

    sub     ecx, 4
    jnz     .write_dword

    jmp     .free

.copy_bytewise:
.write_byte:
    mov     bl, byte [r9 + rcx]             ; Copy bytes
    mov     byte [r8 + rcx], bl

    dec     ecx
    jnz     .write_byte

.free:
    mov     rdi, r9                         ; Free malloc'd memory
    call    free

    xor     eax, eax                        ; Return 0
.epi:
    mov     rsp, rbp
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
