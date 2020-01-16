    section .rodata

    align 16
    gauss_weights: dd 0.06136, 0.24477, 0.38774, 0.24477

    section .text
    global rgb2grayscale
    global gblur

    extern malloc
    extern free

; Convert rgb image to grayscale
; Params:
;     rdi: byte ptr to data, overwritten with output
;     esi: width of image (in pixels)
;     edx: height of image (in pixels)
;     rcx: dword pointer to number of channels
; Return:
;     -
rgb2grayscale:
.m  equ     8
    push    rbp
    mov     rbp, rsp
    sub     rsp, 16                         ; Reserve local storage

    push    rcx                             ; rcx used in loop
    xor     ecx, ecx

    mov     rax, rdi

    push    rbx                             ; Preserve rbx
    mov     rbx, rsi                        ; Total number of pixels
    imul    rbx, rdx
.loop:
    push    rbx

    mov     rbx, rcx                        ; Calculate byte offset (iter_num * 3)
    mov     qword [rsp + .m], 3
    imul    rbx, qword [rsp + .m]

    mov     dil, byte [rax + rbx]           ; Setup call to mean3
    mov     sil, byte [rax + rbx + 1]
    mov     dl,  byte [rax + rbx + 2]

    pop     rbx
    push rax                                ; Make space for return value

    call    mean3
    mov     dl, al                          ; Store grayscale value

    pop rax
    mov     byte [rax + rcx], dl            ; Write grayscale value

    inc     rcx
    cmp     rcx, rbx
    jl      .loop

    pop     rbx
    pop     rcx
    mov     dword [rcx], 1                  ; Set number of channels to 1

    mov     rsp, rbp
    pop     rbp
    ret


; Gaussian blur using 5x5 convolution kernel
; Params:
;     rdi: byte ptr to data, overwritten with output
;     esi: width in pixels
;     edx: height in pixels
; Return:
;     eax: 0 on success, 1 on failure
gblur:
.data       equ 0
.w          equ 8
.h          equ 12
.bvec       equ 16

    push    rbx
    push    r12                             ; r12-15 used for preserving rsi, rdx, rcx and rax,
    push    r13                             ; respectively, accross function calls
    push    r14
    push    r15
    sub     rsp, 32

    mov     qword [rsp + .data], rdi        ; Store data on stack
    mov     dword [rsp + .w], esi
    mov     dword [rsp + .h], edx

    mov     edi, esi                        ; Number of bytes to allocate
    imul    edi, edx

    call    malloc

    cmp     rax, 0
    jne     .malloc_succ

    mov     eax, 1                          ; malloc failed, return 1
    jmp     .epi

.malloc_succ:
    mov     r9, rax                         ; tmp pointer to r9

    mov     r8, qword [rsp + .data]         ; data pointer to r8
    mov     esi, dword [rsp + .w]           ; width back to esi
    mov     edx, dword [rsp + .h]           ; height back to edx

; Horizontal pass
    xor     ecx, ecx                        ; ecx counter for outer loop (rows)
    mov     ebx, esi                        ; ebx upper bound for inner loop (cols)
    sub     ebx, 2                          ; Avoid out-of-bounds access

.hloop:
    mov     eax, 2                          ; eax counter for inner loop

.hinner_loop:
    mov     r10d, ecx                       ; Row idx
    imul    r10d, esi                       ; Address offset of first pixel on current row
    add     r10d, eax                       ; Address offset of current pixel

    mov     r12d, esi                       ; Preserve register values
    mov     r13d, edx
    mov     r14d, ecx
    mov     r15d, eax

    pxor    xmm0, xmm0
    pxor    xmm1, xmm1

    lea     rdi, [r8 + r10 + 2]             ; Pixel number 4 to be filtered
    call    byte2ss
    movss   xmm1, xmm0                      ; Pixel 4 in xmm1

    sub     rdi, 4                          ; Pixel 0 for filter
    call    bvec2ps                         ; Pixels 0, 1, 2 and 3 in xmm0

    call    apply_kernel                    ; al has pixel value

    mov     byte [r9 + r10], al             ; Write byte to tmp array

    mov     eax, r15d                       ; Restore registers
    mov     ecx, r14d
    mov     edx, r13d
    mov     esi, r12d

    inc     eax
    cmp     eax, ebx                        ; ebx (cols - 2) upper limit for inner loop
    jl      .hinner_loop

    inc     ecx
    cmp     ecx, edx                        ; edx (rows) upper limit for outer loop
    jl      .hloop

; Vertical pass
    xor     ecx, ecx                        ; ecx counter for outer loop (cols)
    mov     ebx, edx                        ; ebx upper bound for inner loop (rows)
    sub     ebx, 2

.vloop:
    mov     eax, 2                          ; eax counter for inner loop

.vinner_loop:
    mov     r10d, eax
    add     r10d, 2                         ; Row idx of pixel 4 in filter
    imul    r10d, esi                       ; Address offset of first pixel of row of pixel 4
    add     r10d, ecx                       ; Address offset of pixel 4

    mov     r12d, esi                       ; Preserve esi accross call

    pxor    xmm0, xmm0
    pxor    xmm1, xmm1

    lea     rdi, [r9 + r10]                 ; Address of pixel 4
    call    byte2ss
    movss   xmm1, xmm0                      ; xmm1 holds pixel 4

    mov     esi, r12d                       ; Restore esi

    xor     r11d, r11d
    mov     r14d, 4
.read_byte:                                 ; Read 4 bytes in column, store in 4 lowest bytes of r11
    shl     r11d, 8                         ; Shift existing bytes out of the way
    sub     r10d, esi                       ; Subtract width to get next pixel
    mov     r11b, byte [r9 + r10]           ; Read into lower 8 bits

    dec     r14d
    jnz     .read_byte

    mov     dword [rsp + .bvec], r11d       ; Write all 4 bytes to stack at once

    lea     rdi, [rsp + .bvec]              ; Address of byte array on stack

    mov     r14d, ecx                       ; Preserve registers
    mov     r15d, eax

    mov     r12d, esi                       ; Preserve esi

    call    bvec2ps                         ; xmm0 has pixels 0, 1, 2 and 3

    call    apply_kernel                    ; al has pixel value


    mov     esi, r12d                       ; Restore esi

    add     r10d, esi                       ; Compute address offset of pixel
    add     r10d, esi

    mov     byte [r8 + r10], al             ; Write byte

    mov     eax, r15d                       ; Restore registers
    mov     ecx, r14d

    inc     eax
    cmp     eax, ebx                        ; ebx (rows - 2) upper bound for inner loop
    jl      .vinner_loop

    inc     ecx
    cmp     ecx, esi                        ; esi (width) upper bound for outer loop
    jl      .vloop

.free:
    mov     rdi, r9                         ; Free malloc'd memory
    call    free

    xor     eax, eax                        ; Return 0
.epi:
    add     rsp, 32
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; Convert 4 consecutive bytes to packed single precision floating point
; Params:
;     rdi: byte pointer to data (at least 4 bytes)
; Return:
;     xmm0 (packed single precision): zero extended data converted to packed single precision float
bvec2ps:
    push    rbp
    mov     rbp, rsp
    and     rsp, -0x10
    sub     rsp, 16
    xor     ecx, ecx
    mov     edx, 4

    pxor    xmm0, xmm0

.loop:
    movzx   esi, byte [rdi + rcx]           ; Read byte and zero extend
    cvtsi2ss    xmm0, esi                   ; Convert to single precision float
    movss   dword [rsp + rcx * 4], xmm0     ; Write to stack

    inc     ecx
    cmp     ecx, edx
    jl      .loop

    movaps  xmm0, [rsp]

    mov     rsp, rbp
    pop     rbp
    ret

; Convert single byte to scalar single precision floating point
; Params:
;     rdi: byte pointer to data (at least one byte)
; Return:
;     xmm0 (scalar single precision): zero extended data converted to scalar single precision float
byte2ss:
    movzx   esi, byte [rdi]                 ; Read byte and zero extend
    pxor    xmm0, xmm0
    cvtsi2ss    xmm0, esi
    ret

; Apply gaussian kernel
; Params:
;     xmm0 (packed single precision): pixels 0, 1, 2, and 3
;     xmm1 (scalar single precision): pixel 4
; Return:
;     al: value returned from kernel
; Prerequisites:
;     rsp 16-byte aligned
apply_kernel:
    push    rbp
    mov     rbp, rsp
    and     rsp, -0x10                      ; 16-byte align rsp
    sub     rsp, 16
    mulps   xmm0, [gauss_weights]           ; Multiply pixels 0-3 (SSE)

    pxor    xmm2, xmm2
    movss   xmm2, dword [gauss_weights]     ; Load only first weight to xmm2
    mulss   xmm1, xmm2                      ; Multiply pixel 4 with weight 4 (weight 4 == weight 0)

    movaps  [rsp], xmm0                     ; Store on stack

    xor     ecx, ecx
    mov     edx, 4
.loop:
    addss   xmm1, dword [rsp + rcx * 4]     ; Accumulate in xmm1

    inc     ecx
    cmp     ecx, edx
    jl      .loop

    cvtss2si    eax, xmm1

    mov     rsp, rbp
    pop     rbp
    ret

; Compute the mean of 3 bytes
; Params:
;     dil: byte 1
;     sil: byte 2
;     dl:  byte 3
; Return:
;     al: mean of the inputs
mean3:
    push    rbp
    mov     rbp, rsp
    movzx   di, dil                         ; Zero extend (8-bit => 16-bit)
    movzx   si, sil
    movzx   dx, dl

    mov     ax, di                          ; Compute mean
    add     ax, si
    add     ax, dx
    xor     edx, edx                        ; Zero out rdx for division
    mov     di, 3
    div     di

    mov     rsp, rbp
    pop     rbp
    ret
