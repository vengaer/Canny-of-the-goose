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


; Gaussian blur
; Params:
;     rdi: byte ptr to data, overwritten with output
;     esi: width in pixels
;     edx: height in pixels
; Return:
;     eax: 0 on success, 1 on failure
gblur:
.dta equ    0
    push    rbp
    mov     rbp, rsp

    and     rsp, -0x10                      ; 16-byte align rsp
    sub     rsp, 16

    mov     qword [rsp + .dta], rdi         ; Store data ptr on stack

    mov     edi, esi                        ; Number of bytes to allocate
    imul    edi, edx

    push    rsi                             ; Preserve rsi and rdx for malloc call
    push    rdx

    call    malloc

    pop     rdx
    pop     rsi

    cmp     rax, 0                          ; Check for NULL

    jne     .malloc_succ

    mov     eax, 1                          ; malloc failed, return 1
    jmp     .epi

.malloc_succ:
    mov     r9, rax                         ; Store pointer in r9

; Horizontal pass
    mov     rdi, qword [rsp + .dta]         ; Move data back to rdi

    xor     ecx, ecx
    push    rbx                             ; ebx for upper bound in column loop
    mov     ebx, esi
    sub     ebx, 2                          ; Avoid out-of-bounds access for filter (edges handled separately)

.hloop:                                     ; Loop over rows
    mov     eax, 2                          ; eax counter for inner loop

.hinner_loop:                               ; Loop over cols 2,...,width - 3 (inclusive)

    mov     r8d, ecx                        ; Compute data idx
    imul    r8d, esi
    add     r8d, eax

    push    rax                             ; Preserve registers
    push    rsi
    push    rdx
    push    rcx

    pxor    xmm0, xmm0
    pxor    xmm1, xmm1

    add     rdi, r8                         ; Address for center pixel
    add     rdi, 2                          ; Advance to 4th pixel for filter
    call    byte2ss
    movss   xmm1, xmm0                      ; xmm1 holds pixel 4 for filter

    sub     rdi, 4                          ; Address for 0th pixel for filter
    call    bytes2ps                        ; xmm0 holds pixels 0, 1, 2 and 3 for filter

    add     rdi, 2                          ; Restore rdi
    sub     rdi, r8

    call    apply_kernel

    mov     byte [r9 + r8], al              ; Write to tmp array

    pop     rcx
    pop     rdx
    pop     rsi
    pop     rax

    inc     eax
    cmp     eax, ebx
    jl      .hinner_loop

    inc     ecx
    cmp     ecx, edx
    jl      .hloop

    pop     rbx

    mov     ecx, esi
    imul    ecx, edx
.loop:
    dec     ecx
    mov     al, byte [r9 + rcx]
    mov     byte [rdi + rcx], al
    jnz     .loop                           ; safe since mov doesn't affect flags

.free:
    mov     rdi, r9                         ; Free malloc'd memory
    call    free

    xor     eax, eax                        ; Return 0
.epi:
    mov     rsp, rbp
    pop     rbp
    ret

; Convert 4 consecutive bytes to packed single precision floating point
; Params:
;     rdi: byte pointer to data (at least 4 bytes)
; Return:
;     xmm0 (packed single precision): zero extended data converted to packed single precision float
; Prerequisites:
;     rsp 16-byte aligned
bytes2ps:
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

    add     rsp, 16
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

    add     rsp, 16
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
