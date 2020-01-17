    section .rodata

    align 16
    gauss_weights: dd 0.06136, 0.24477, 0.38774, 0.24477

    section .text
    global rgb2grayscale
    global gaussblur

    extern malloc
    extern free

; Convert rgb image to grayscale
; Params:
;     rdi: byte ptr to data, overwritten with output
;     esi: width of image (in pixels)
;     edx: height of image (in pixels)
;     rcx: dword pointer to number of channels
; Return:
;     eax: 0 on success, 1 on failure (if image has 4 channels)
rgb2grayscale:
    push    rbx

    mov     eax, dword [rcx]
    cmp     eax, 1                          ; Single channel, no work to be done
    je      .done

    cmp     eax, 3
    je      .cvt_rgb

    mov     eax, 1                          ; Not a 3-channel image, return 1
    jmp     .epi

.cvt_rgb:
    mov     r8, rdi                         ; Data ptr to r8

    mov     dword [rcx], 1                  ; Set number of channels to 1

    xor     ecx, ecx                        ; Loop counter

    mov     r9d, edx                        ; r9d upper bound for loop
    imul    r9d, esi
.cvt_pxls:
    mov     rbx, rcx                        ; 3 channels => multiply pixel offset by 3
    imul    rbx, 3

    mov     dil, byte [r8 + rbx]            ; Compute pixel mean
    mov     sil, byte [r8 + rbx + 1]
    mov     dl,  byte [r8 + rbx + 2]

    call    mean3
    mov     byte [r8 + rcx], al             ; Write byte

    inc     ecx
    cmp     ecx, r9d
    jl      .cvt_pxls

.done:
    xor     eax, eax
.epi:
    pop     rbx
    ret


; Gaussian blur using 5x5 convolution kernel
; Params:
;     rdi: byte ptr to data, overwritten with output
;     esi: width in pixels
;     edx: height in pixels
; Return:
;     eax: 0 on success, 1 on failure
gaussblur:
.data       equ 0
.width      equ 8
.height     equ 12
.bvec       equ 16

    push    rbx
    push    r12                             ; r12-15 used for preserving rsi, rdx, rcx and rax,
    push    r13                             ; respectively, accross function calls
    push    r14
    push    r15
    sub     rsp, 32

    mov     qword [rsp + .data], rdi        ; Store data on stack
    mov     dword [rsp + .width], esi
    mov     dword [rsp + .height], edx

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
    mov     esi, dword [rsp + .width]       ; width back to esi
    mov     edx, dword [rsp + .height]      ; height back to edx

; Horizontal pass
    xor     ecx, ecx                        ; ecx counter for outer loop (rows)
    mov     ebx, esi                        ; ebx upper bound for inner loop (cols)
    sub     ebx, 2                          ; Avoid out-of-bounds access

.hloop:
    mov     r12d, esi
    mov     r13d, edx
    mov     r14d, ecx

    mov     rdi, r8                         ; Setup call (ecx already row idx)
    mov     edx, esi
    mov     rsi, r9

    call    filter_outermost_cols

    mov     ecx, r14d
    mov     edx, r13d
    mov     esi, r12d

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
    mov     r12d, esi                       ; Preserve registers
    mov     r13d, edx
    mov     r14d, ecx
    mov     r15, r8

    mov     rdi, r9                         ; Setup call
    mov     r11d, esi
    mov     rsi, r8
    mov     r8d, ecx
    mov     ecx, edx
    mov     edx, r11d

    call    filter_outermost_rows

    mov     r8, r15                         ; Restore registers
    mov     ecx, r14d
    mov     edx, r13d
    mov     esi, r12d

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

    mov     r13d, edx
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
    mov     edx, r13d

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

; Filter 2 leftmost and 2 rightmost pixels in row
; Params:
;     rdi: data pointer (first pixel in pixel array)
;     rsi: destination pointer (first pixel in pixel array)
;     edx: width in pixels
;     ecx: row index
; Return:
;     -
filter_outermost_cols:
.src        equ 0
.dst        equ 8
.width      equ 16
.row        equ 20
.bvec       equ 24
.pxls       equ 28
    sub     rsp, 32

    mov     dword [rsp + .width], edx       ; Write width and height to stack
    mov     dword [rsp + .row], ecx

    imul    edx, ecx                        ; ecx has address offset to first pixel in row
    add     rdi, rdx                        ; Address of first pixel in row in src
    add     rsi, rdx                        ; Address of first pixel on row in dst

    mov     qword [rsp + .src], rdi         ; Write addresses to stack
    mov     qword [rsp + .dst], rsi

; First pixel
    mov     cx, word [rdi]                  ; Only 2 pixels used for first 4 bytes in kernel
    mov     byte [rsp + .bvec], ch
    mov     byte [rsp + .bvec + 1], ch
    mov     word [rsp + .bvec + 2], cx

    add     rdi, 2                          ; Pixel 4 for filter
    mov     cl, byte [rdi]
    mov     byte [rsp + .pxls + 3], cl      ; Store pixel value on stack (use last byte of pxls since it's not used yet)

    pxor    xmm0, xmm0
    pxor    xmm1, xmm1
    call    byte2ss
    movss   xmm1, xmm0                      ; xmm1 has  pixel 4

    lea     rdi, [rsp + .bvec]
    call    bvec2ps                         ; xmm0 has pixels 0, 1, 2 and 3

    call    apply_kernel                    ; al has resulting byte

    mov     byte [rsp + .pxls], al          ; Write result to stack for now

; Second pixel
    mov     ecx, dword [rsp + .bvec]        ; Shift byte array 1 byte to the left
    shl     ecx, 8
    mov     cl, byte [rsp + .pxls + 3]      ; byte 3 for filter
    mov     dword [rsp + .bvec], ecx        ; Write back to stack

    mov     rdi, qword [rsp + .src]
    add     rdi, 3                          ; Pixel 4 for filter

    pxor    xmm0, xmm0
    call    byte2ss
    movss   xmm1, xmm0                      ; xmm1 has pixel 4

    lea     rdi, [rsp + .bvec]
    call    bvec2ps                         ; xmm0 has pixels 0, 1, 2 and 3

    call    apply_kernel
    mov     byte [rsp + .pxls + 1], al      ; Write to stack

; Second to last pixel
    mov     rsi, qword [rsp + .src]         ; First byte in row
    mov     edx, dword [rsp + .width]
    lea     rdi, [rsi + rdx - 1]            ; Address of last pixel on row

    mov     qword [rsp + .src], rdi         ; Write pixel address to stack

    pxor    xmm0, xmm0
    call    byte2ss
    movss   xmm1, xmm0                      ; xmm1 has pixel 4

    sub     rdi, 3                          ; rdi first pixel to be filtered

    mov     edx, dword [rdi]                ; Copy 4 bytes to stack
    mov     dword [rsp + .bvec], edx

    lea     rdi, [rsp + .bvec]

    call    bvec2ps

    call    apply_kernel
    mov     byte [rsp + .pxls + 2], al

; Last pixel
    mov     rdi, qword [rsp + .src]         ; Last pixel to rdi
    pxor    xmm0, xmm0
    call    byte2ss
    movss   xmm1, xmm0                      ; xmm1 has pixel 4

    mov     edx, dword [rsp + .bvec]        ; load bytes to edx
    mov     cl, dl                          ; Preserve rightmost byte over shift
    shl     edx, 8                          ; Shift out most significant byte
    mov     dl, cl                          ; Write back least significant byte
    mov     dword [rsp + .bvec], edx

    lea     rdi, [rsp + .bvec]              ; Address of byte array

    call    bvec2ps

    call    apply_kernel

; Write to dst
    mov     rsi, qword [rsp + .dst]         ; Load dst pointer

    mov     cx, word [rsp + .pxls]          ; Write two leftmost pixels
    mov     word [rsi], cx

    mov     edx, dword [rsp + .width]       ; Load width
    add     rsi, rdx
    lea     rdi, [rsi + rdx - 2]            ; Address of second to last pixel on line
    mov     ah, byte [rsp + .pxls + 2]      ; Second to last pixel to ah, al still has last byte
    mov     word [rdi], ax                  ; Write two leftmost bytes

    add     rsp, 32
    ret

; Filter 2 topmost and 2 bottommost pixels in column
; Params:
;     rdi: data pointer (first pixel in pixel array)
;     rsi: destination pointer (first pixel in pixel array)
;     edx: width in pixels
;     ecx: height in pixels
;     r8d: column index
; Return:
;     -
filter_outermost_rows:
.src        equ 0
.dst        equ 8
.width      equ 16
.height     equ 20
.bvec       equ 24
.pxls       equ 28
    sub     rsp, 32

    mov     dword [rsp + .width], edx
    mov     dword [rsp + .height], ecx

    add     rdi, r8
    mov     qword [rsp + .src], rdi         ; Address of pixel on first row in input

    add     rsi, r8
    mov     qword [rsp + .dst], rsi         ; Address of pixel on first row in output

; First pixel
    mov     ch, byte [rdi]                  ; Pixel in first row
    mov     cl, byte [rdi + rdx]            ; Pixel in second row
    mov     byte [rsp + .bvec], ch          ; Pixel from first row to first, second and third
    mov     byte [rsp + .bvec + 1], ch      ; values for kernel, second row to fourth
    mov     word [rsp + .bvec + 2], cx

    lea     rdi, [rdi + 2 * rdx]            ; Address of 3rd row from the top

    mov     cl, byte [rdi]
    mov     byte [rsp + .pxls + 3], cl      ; Store pixel 4 on stack

    pxor    xmm0, xmm0
    pxor    xmm1, xmm1
    call    byte2ss
    movss   xmm1, xmm0                      ; Pixel 4 in xmm1

    lea     rdi, [rsp + .bvec]

    call    bvec2ps

    call    apply_kernel

    mov     byte [rsp + .pxls], al          ; First resulting byte to stack

; Second pixel
    mov     ecx, dword [rsp + .bvec]        ; Shift kernel one step down
    shl     ecx, 8
    mov     cl, byte [rsp + .pxls + 3]      ; Fourth pixel
    mov     dword [rsp + .bvec], ecx        ; Write back to stack

    mov     rdi, qword [rsp + .src]
    mov     edx, dword [rsp + .width]

    imul    edx, 3
    lea     rdi, [rdi + rdx]                ; Address to pixel 4
    pxor    xmm0, xmm0
    call    byte2ss
    movss   xmm1, xmm0                      ; xmm1 has pixel 4

    lea     rdi, [rsp + .bvec]
    call    bvec2ps

    call    apply_kernel

    mov    byte [rsp + .pxls + 1], al       ; Write resulting byte to stack

; Second to last pixel

    mov     rdi, qword [rsp + .src]
    mov     edx, dword [rsp + .width]
    mov     ecx, dword [rsp + .height]
    sub     ecx, 4
    imul    ecx, edx                        ; Offset of pixel on first row of kernel
    add     rdi, rcx                        ; Address of pixel on first row of kernel

    xor     r8d, r8d

    mov     r8b, byte [rdi]                 ; Move bytes in column to r8d
    shl     r8d, 8
    mov     r8b, byte [rdi + rdx]
    shl     r8d, 8
    mov     r8b, byte [rdi + 2 * rdx]
    shl     r8d, 8
    imul    rdx, 3                          ; Advance rdi 3 lines
    add     rdi, rdx
    mov     r8b, byte [rdi]                 ; Move last byte to r8d

    mov     dword [rsp + .bvec], r8d        ; Write bytes to stack

    mov     qword [rsp + .src], rdi         ; Address of pixel in last row to stack

    pxor    xmm0, xmm0
    call    byte2ss
    movss   xmm1, xmm0                      ; Pixel 4 in xmm1


    lea     rdi, [rsp + .bvec]
    call    bvec2ps

    call    apply_kernel

    mov     byte [rsp + .pxls + 2], al      ; Result to stack

; Last pixel
    mov     rdi, qword [rsp + .src]         ; Address of pixel in last row

    pxor    xmm0, xmm0
    call    byte2ss
    movss   xmm1, xmm0                      ; Pixel 4 in xmm1

    mov     edx, dword [rsp + .bvec]
    mov     cl, dl                          ; Preserve lowest byte over shift
    shl     edx, 8                          ; Move kernel to the right
    mov     dl, cl                          ; Restore lowest byte
    mov     dword [rsp + .bvec], edx

    lea     rdi, [rsp + .bvec]              ; Address of byte array

    call    bvec2ps

    call    apply_kernel

    mov     ah, [rsp + .pxls + 2]           ; al already has last byte

    mov     rsi, qword [rsp + .dst]
    mov     edx, dword [rsp + .width]
    mov     edi, dword [rsp + .height]

    mov     cx, word [rsp + .pxls]
    mov     byte [rsi], ch                  ; Byte to first row
    mov     byte[rsi + rdx], cl             ; Byte to second row

    sub     edi, 2
    imul    edi, edx
    add     rsi, rdi                        ; Address of pixel in second to last row
    mov     byte [rsi], ah                  ; Byte to second to last row
    mov     byte [rsi + rdx], al            ; Byte to last row

    add     rsp, 32
    ret

; Convert 4 consecutive bytes to packed single precision floating point
; Params:
;     rdi: byte pointer to data (at least 4 bytes)
; Return:
;     xmm0 (packed single precision): zero extended data converted to packed single precision float
bvec2ps:
    pxor    xmm0, xmm0                      ; Zero out xmm0
    movzx   esi, byte [rdi]                 ; Zero extend first byte to dword
    cvtsi2ss    xmm0, esi                   ; Convert and write to lower 4 bytes of xmm0
    pslldq  xmm0, 4                         ; Shift left 4 bytes

    movzx   esi, byte [rdi + 1]             ; Zero extend second byte
    cvtsi2ss    xmm0, esi                   ; Convert and write to lower 4 bytes
    pslldq  xmm0, 4                         ; Shift left 4 bytes

    movzx   esi, byte [rdi + 2]             ; Zero extend third byte
    cvtsi2ss    xmm0, esi                   ; Convert and write to lower 4 bytes
    pslldq  xmm0, 4                         ; Shift left 4 bytes

    movzx   esi, byte [rdi + 3]             ; Zero extend fourth byte
    cvtsi2ss    xmm0, esi                   ; Convert and write ot lower 4 bytes, xmm0, now packed

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
apply_kernel:
    mulps   xmm0, [gauss_weights]           ; Multiply pixels 0-3 (SSE)

    pxor    xmm2, xmm2
    movss   xmm2, dword [gauss_weights]     ; Load only first weight to xmm2
    mulss   xmm1, xmm2                      ; Multiply pixel 4 with weight 4 (weight 4 == weight 0)

    movaps  xmm2, xmm0                      ; Copy xmm0 to xmm2 and shift right 8 bytes
    psrldq  xmm2, 8

    addps   xmm0, xmm2                      ; Add upper half of xmm0 (now in xmm2) to lower half

    addss   xmm1, xmm0                      ; Accumulate in xmm1
    psrldq  xmm0, 4
    addss   xmm1, xmm0

    cvtss2si    eax, xmm1
    ret

; Compute the mean of 3 bytes
; Params:
;     dil: byte 1
;     sil: byte 2
;     dl:  byte 3
; Return:
;     al: mean of the inputs
mean3:
    xor     eax, eax                        ; Prepare eax

    movzx   di, dil                         ; Zero extend (8-bit => 16-bit)
    movzx   si, sil
    movzx   dx, dl

    mov     ax, di                          ; Compute mean
    add     ax, si
    add     ax, dx
    xor     edx, edx                        ; Zero out rdx for division
    mov     di, 3
    div     di

    ret
