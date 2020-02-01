    section .rodata
    pi_half: dd 1.57079632679

    section .text
    global edgedetect

    extern arctan2pckd
    extern tangent
    extern lerp
    extern rad2deg
    extern malloc
    extern free

; Edge detection with non-maximum suppression
; Params:
;     rdi: byte ptr to data, overwritten with output
;     rsi: dword ptr to width in pixels
;     rdx: dword ptr to height in pixels
; Return:
;     eax: 0 on success, 1 on failure, 2 if dims are unsuitable
edgedetect:
.data       equ 0
.waddr      equ 8
.haddr      equ 16
.angles     equ 24
.rval       equ 32
    sub     rsp, 64

    mov     qword [rsp + .data], rdi
    mov     qword [rsp + .waddr], rsi
    mov     qword [rsp + .haddr], rdx

    mov     edi, dword [rsi]                ; Number of bytes for angle array
    imul    edi, dword [rdx]
    imul    edi, 4

    call    malloc

    cmp     eax, 0
    jne     .malloc_succ

    inc     eax
    jmp     .epi

.malloc_succ:
    mov     qword [rsp + .angles], rax
    mov     rdi, qword [rsp + .data]
    mov     rsi, qword [rsp + .waddr]
    mov     rdx, qword [rsp + .haddr]
    mov     rcx, rax

    call    sobel

    mov     dword [rsp + .rval], eax

    cmp     eax, 0                          ; sobel failed, exit
    jne     .free

    mov     rsi, qword [rsp + .waddr]       ; Width to esi
    mov     esi, dword [rsi]

    mov     rdx, qword [rsp + .haddr]       ; Height to edx
    mov     edx, dword [rdx]

    mov     rdi, qword [rsp + .data]        ; Data ptr to rdi
    mov     rcx, qword [rsp + .angles]      ; Angle ptr to rcx

    call    non_max_suppression

    mov     dword [rsp + .rval], eax        ; Preserve return value past free

.free:
    mov     rdi, qword [rsp + .angles]
    call    free

    mov     eax, dword [rsp + .rval]
.epi:
    add     rsp, 64
    ret

; Apply sobel kernels
; Params:
;     rdi: byte ptr to data, overwritten with output
;     rsi: dword ptr to width in pixels
;     rdx: dword ptr to height in pixels
;     rcx: single precision float ptr to which to write gradient angles
; Return:
;     eax: 0 on success, 1 on malloc failure, 2 if dims are unsuitable
sobel:
.data       equ 0
.width      equ 8
.height     equ 12
.waddr      equ 16
.haddr      equ 24
.f2b        equ 32                          ; Used for compressing single precision float to byte
.angles     equ 48
.fstride    equ 56                          ; Number of bytes in a row for float array
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
    mov     qword [rsp + .angles], rcx

    mov     esi, dword [rsi]                ; Read width and height
    mov     edx, dword [rdx]

    mov     dword [rsp + .width], esi
    mov     dword [rsp +.height], edx

    mov     eax, 2                          ; Return 2 if dims are unsuitable
    cmp     esi, 14                         ; Image must have at least 14 cols
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

    mov     r10, qword [rsp + .data]        ; Address of first byte in first row
    mov     r11, r10
    add     r11, rsi                        ; Address of first byte in second row
    mov     r12, r11
    add     r12, rsi                        ; Address of first byte in third row
    mov     r13, r9                         ; tmp ptr to r13

    mov     r14, qword [rsp + .angles]

    pxor    xmm15, xmm15

    mov     ecx, edx                        ; Number of rows to process
    sub     ecx, 2

    mov     ebx, esi                        ; Number of cols to process
    sub     ebx, 2

    mov     r15d, ebx
    imul    r15d, 4

    mov     qword [rsp + .fstride], r15

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

    punpckhbw   xmm0, xmm15                 ; Convert high 8 bytes to words
    punpckhbw   xmm1, xmm15
    punpckhbw   xmm2, xmm15

    psubw   xmm8, xmm0                      ; Horizontal kernel: subtract first col
    paddw   xmm8, xmm2                      ; Add third col

    psubw   xmm9, xmm0                      ; Vertical kernel: subtract first col
    psubw   xmm9, xmm1                      ; Subtract second col twice
    psubw   xmm9, xmm1
    psubw   xmm9, xmm2                      ; Subtract third col

; Second row
    movdqu  xmm0, [r11 + rax]               ; Center pixel used in neither horizontal nor
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

; Compute gradient angles
    movdqa  xmm0, xmm7                      ; Vertical to xmm0
    movdqa  xmm1, xmm6                      ; Horizontal to xmm1

    punpcklwd   xmm0, xmm15                 ; Low 4 words to dwords
    punpcklwd   xmm1, xmm15

    cvtdq2ps    xmm0, xmm0                  ; Convert
    cvtdq2ps    xmm1, xmm1

    call    arctan2pckd

    movups  [r14 + rax * 4], xmm0           ; Write 4 32 bit floats to memory

    movdqa  xmm0, xmm7                      ; Same but with 4 high words
    movdqa  xmm1, xmm6

    punpckhwd   xmm0, xmm15
    punpckhwd   xmm1, xmm15

    cvtdq2ps    xmm0, xmm0
    cvtdq2ps    xmm1, xmm1

    call    arctan2pckd

    movups [r14 + rax * 4 + 16], xmm0       ; Write to memory

    movdqa  xmm0, xmm9                      ; 4 low words of xmm9 and xmm8
    movdqa  xmm1, xmm8

    punpcklwd   xmm0, xmm15
    punpcklwd   xmm1, xmm15

    cvtdq2ps    xmm0, xmm0
    cvtdq2ps    xmm1, xmm1

    call    arctan2pckd

    movups  [r14 + rax * 4 + 32], xmm0

    movdqa  xmm0, xmm9                      ; 2 high words of xmm9 and xmm8
    movdqa  xmm1, xmm8

    punpckhwd   xmm0, xmm15
    punpckhwd   xmm1, xmm15

    cvtdq2ps    xmm0, xmm0
    cvtdq2ps    xmm1, xmm1

    call    arctan2pckd

    movlps [r14 + rax * 4 + 48], xmm0       ; Write 2 single precision floats

; Compute gradient magnitude
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

    movdqa  [rsp + .f2b], xmm0              ; 4 values to stack, each 32 bits
    mov     r15, qword [rsp + .f2b]         ; 8 least significant bytes to r15
    mov     byte [r13 + rax + 1], r15b      ; Write first byte
    shr     r15, 32                         ; Shift out lower 32 bits
    mov     byte [r13 + rax + 2], r15b      ; Write second byte

    mov     r15, qword [rsp + .f2b + 8]     ; 8 most significant bytes to r15
    mov     byte [r13 + rax + 3], r15b      ; Write bytes
    shr     r15, 32
    mov     byte [r13 + rax + 4], r15b

    movdqa  [rsp + .f2b], xmm1              ; 4 values on stack, each 32 bits
    mov     r15, qword [rsp + .f2b]         ; 8 least significant bytes to r15
    mov     byte [r13 + rax + 5], r15b      ; Write first byte
    shr     r15, 32                         ; Shift out lower 32 bits
    mov     byte [r13 + rax + 6], r15b      ; Write second byte

    mov     r15, qword [rsp + .f2b + 8]     ; 8 most significant bytes to r15
    mov     byte [r13 + rax + 7], r15b      ; Write bytes
    shr     r15, 32
    mov     byte [r13 + rax + 8], r15b

    movdqa  [rsp + .f2b], xmm2              ; 4 values on stack, each 32 bits
    mov     r15, qword [rsp + .f2b]         ; 8 least significant bytes to r15
    mov     byte [r13 + rax + 9], r15b      ; Write first byte
    shr     r15, 32                         ; Shift out lower 32 bits
    mov     byte [r13 + rax + 10], r15b     ; Write second byte

    mov     r15, qword [rsp + .f2b + 8]     ; 8 most significant bytes to r15
    mov     byte [r13 + rax + 11], r15b     ; Write bytes
    shr     r15, 32
    mov     byte [r13 + rax + 12], r15b

    movq    [rsp + .f2b], xmm3
    mov     r15, qword [rsp + .f2b]         ; 8 least significant bytes to r15
    mov     byte [r13 + rax + 13], r15b     ; Write first byte
    shr     r15, 32                         ; Shift out lower 32 bits
    mov     byte [r13 + rax + 14], r15b     ; Write second byte


    add     eax, 14                         ; 14 values processesed per iteration
    cmp     eax, ebx
    jl      .col_loop

    add     r10, rsi                        ; Advance to next set of rows
    add     r11, rsi
    add     r12, rsi
    add     r13, rbx
    add     r14, qword [rsp + .fstride]

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
    mov     ebx, 8
    div     ebx

    mov     r10, r9
.copy_qwords:
    mov     rbx, qword [r10]
    mov     qword [r8], rbx
    add     r8, 8
    add     r10, 8

    dec     eax
    jnz     .copy_qwords

.copy_bytes:
    mov     bl, byte [r10]
    mov     byte [r8], bl
    inc     r8
    inc     r10

    dec     edx
    jnz     .copy_bytes

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

; Non-maximum suppression
; Params:
;     rdi: byte ptr to data, overwritten with result
;     esi: width of image in pixels
;     edx: height of image in pixels
;     rcx: single precision floating point ptr containing gradient angles
; Return:
;     eax: 0 on success, 1 on failure
non_max_suppression:
.data       equ 0
.width      equ 8
.height     equ 12
.angles     equ 16
.fstride    equ 24
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 32

    mov     qword [rsp + .data], rdi        ; Parameters to stack
    mov     dword [rsp + .width], esi
    mov     dword [rsp + .height], edx
    mov     qword [rsp + .angles], rcx

    mov     r8d, esi
    imul    r8d, 4
    mov     dword [rsp + .fstride], r8d     ; Number of bytes in a single row of floats

    mov     r9, rcx                         ; Address of first float in second row
    add     r9, r8

    mov     r10, rdi                        ; Address of first byte in first row of data
    mov     r11, r10
    add     r11, rsi                        ; Address of first byte in second row
    mov     r12, r11
    add     r12, rsi                        ; Address of first byte in third row

    mov     ecx, 1                          ; Counter for row loop
    sub     edx, 1                          ; Upper bound for row loop

    mov     r13d, esi                       ; Upper bound for col loop
    sub     r13d, 1

.row_loop:
    mov     ebx, 1                          ; Counter for col loop

.col_loop:
    movss   xmm0, dword [r9 + rbx * 4]
    movss   xmm15, xmm0                     ; Preserve xmm0

    call    rad2deg

    cmp     eax, -90
    je      .vertical                       ; Edge is vertical

    cmp     eax, -45
    jl      .interp_vert_nw2se              ; Edge has angle ]-90, -45[, interpolate
    je      .nw2se                          ; Edge has angle -45, check diagonal

    cmp     eax, 0
    jl      .interp_hor_nw2se               ; Edge has angle ]-45, 0[, interpolate
    je      .horizontal                     ; Edge is horizontal

    cmp     eax, 45
    jl      .interp_hor_sw2ne               ; Edge has angle ]0, 45[, interpolate
    je      .sw2ne                          ; Edge has angle 45, check diagonal

    cmp     eax, 90
    jl      .interp_vert_sw2ne              ; Edge has angle ]45, 90[, interpolate
    je      .vertical                       ; Edge is vertical


.horizontal:
    ;  #-----#-----#
    ;  |     |     |
    ;  |     |     |
    ;  x-----x-----x
    ;  |     |     |
    ;  |     |     |
    ;  #-----#-----#

    mov     r14b, byte [r11 + rbx - 1]
    mov     al, byte [r11 + rbx]
    mov     r15b, byte [r11 + rbx + 1]

    jmp     .compare_bytes
.vertical:
    ;  #-----x-----#
    ;  |     |     |
    ;  |     |     |
    ;  #-----x-----#
    ;  |     |     |
    ;  |     |     |
    ;  #-----x-----#

    mov     r14b, byte [r10 + rbx]
    mov     al, byte [r11 + rbx]
    mov     r15b, byte [r12 + rbx]

    jmp     .compare_bytes

.nw2se:
    ;  x-----#-----#
    ;  |     |     |
    ;  |     |     |
    ;  #-----x-----#
    ;  |     |     |
    ;  |     |     |
    ;  #-----#-----x

    mov     r14b, byte [r10 + rbx - 1]
    mov     al, byte [r11 + rbx]
    mov     r15b, byte [r12 + rbx + 1]

    jmp     .compare_bytes

.sw2ne:
    ;  #-----#-----x
    ;  |     |     |
    ;  |     |     |
    ;  #-----x-----#
    ;  |     |     |
    ;  |     |     |
    ;  x-----#-----#

    mov     r14b, byte [r10 + rbx + 1]
    mov     al, byte [r11 + rbx]
    mov     r15b, byte [r12 + rbx - 1]
    jmp     .compare_bytes

.interp_hor_nw2se:
    ;  #-----#-----#
    ;  x     |     |
    ;  |     |     |
    ;  #-----x-----#
    ;  |     |     |
    ;  |     |     x
    ;  #-----#-----#

    movss   xmm0, xmm15                     ; Angle in radians

    mulss   xmm0, xmm0                      ; Absolute value of angle
    sqrtss  xmm0, xmm0

    call    tangent

    mov     r15d, esi                       ; Preserve esi

    mov     dil, byte [r11 + rbx - 1]       ; Interpolate between western and north-western pixels
    mov     sil, byte [r10 + rbx - 1]

    call    lerp

    mov     r14b, al

    mov     dil, byte [r11 + rbx + 1]       ; Interpolate between eastern and south-eastern pixels
    mov     sil, byte [r12 + rbx + 1]

    call    lerp

    mov     esi, r15d                       ; Restore esi

    mov     r15b, al
    mov     al, byte [r11 + rbx]

    jmp     .compare_bytes

.interp_hor_sw2ne:
    ;  #-----#-----#
    ;  |     |     x
    ;  |     |     |
    ;  #-----x-----#
    ;  |     |     |
    ;  x     |     |
    ;  #-----#-----#

    movss   xmm0, xmm15                     ; Angle in radians

    call    tangent

    mov     r15d, esi                       ; Preserve esi

    mov     sil, byte [r11 + rbx - 1]       ; Interpolate between western and south-western pixels
    mov     dil, byte [r12 + rbx - 1]

    call    lerp

    mov     r14b, al

    mov     dil, byte [r11 + rbx + 1]       ; Interpolate between eastern and south-eastern pixels
    mov     sil, byte [r10 + rbx + 1]

    call    lerp

    mov     esi, r15d                       ; Restore esi

    mov     r15b, al
    mov     al, byte [r11 + rbx]

    jmp     .compare_bytes

.interp_vert_nw2se:

    ;  #-x---#-----#
    ;  |     |     |
    ;  |     |     |
    ;  #-----x-----#
    ;  |     |     |
    ;  |     |     |
    ;  #-----#---x-#
    ;        |---|
    ;          d

    movss   xmm0, xmm15                     ; Angle in radians
    addss   xmm0, [pi_half]                 ; Add pi/2 to angle

    call    tangent                         ; Tangent computes distance d in figure

    mov     r15d, esi                       ; Preserve esi

    mov     dil, byte [r10 + rbx]           ; Interpolate between north-western and northern pixels
    mov     sil, byte [r10 + rbx - 1]

    call    lerp

    mov     r14b, al

    mov     dil, byte [r12 + rbx]           ; Interpolate between south-eastern and southern pixels
    mov     sil, byte [r12 + rbx + 1]

    call    lerp

    mov     esi, r15d                       ; Restore esi

    jmp     .compare_bytes


.interp_vert_sw2ne:

    ;          d
    ;        |---|
    ;  #-----#---x-#
    ;  |     |     |
    ;  |     |     |
    ;  #-----x-----#
    ;  |     |     |
    ;  |     |     |
    ;  #-x---#-----#

    movss   xmm0, xmm15
    addss   xmm0, [pi_half]                 ; Add pi/2

    call    tangent                         ; tangent computes distance d in figure

    mov     r15d, esi                       ; Preserve esi

    mov     dil, byte [r12 + rbx]           ; Interpolate between southern and south-western pixels
    mov     sil, byte [r12 + rbx - 1]

    call    lerp

    mov     r14b, al

    mov     dil, byte [r10 + rbx]           ; Interpolate between northern and north-eastern pixels
    mov     sil, byte [r10 + rbx + 1]

    call    lerp

    mov     esi, r15d                       ; Restore esi

    mov     r15b, al
    mov     al, byte [r11 + rbx]

.compare_bytes:
    cmp     al, r14b
    jl      .suppress

    cmp     al, r15b
    jl      .suppress

    jmp     .deg_cmp_done

.suppress:
    mov     byte [r11 + rbx], 0             ; Current pixel not max among neighbors on its edge, suppress

.deg_cmp_done:

    inc     ebx
    cmp     ebx, r13d
    jl      .col_loop

    add     r10, rsi                        ; Move to next row
    add     r11, rsi
    add     r12, rsi
    add     r9, r8                          ; Next row in float array

    inc     ecx
    cmp     ecx, edx
    jl      .row_loop

    xor     eax, eax
.epi:
    add     rsp, 32
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
