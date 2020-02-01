    section .rodata
    pi: dd 3.14159265359

    section .text
    global arctan2
    global arctan2pckd
    global tangent
    global sine
    global cosine
    global rad2deg
    global deg2rad
    global lerp

; Compute arctan(y/x)
; Params:
;     xmm0 (scalar single precision): y
;     xmm1 (scalar single precision): x
; Return:
;     xmm0 (scalar single precision): result of the computation
arctan2:
.y  equ     4
.x  equ     0
    sub     rsp, 16                         ; Local storage

    movss   dword [rsp + .y], xmm0
    movss   dword [rsp + .x], xmm1

    fld     dword [rsp + .y]                ; Push to fp stack
    fst     st1                             ; Copy st0 to st1
    fld     dword [rsp + .x]

    fpatan                                  ; atan(st1 / st0), pop
    fstp    dword [rsp + .x]                ; Pop result to stack
    movss   xmm0, dword [rsp + .x]

    add     rsp, 16                         ; Restore rsp
    ret

; Compute arctan(y/x) for packed registers for convenience
; Params:
;     xmm0 (packed single precision): ys
;     xmm1 (packed single precision): xs
; Return:
;     xmm0 (packed single precision): results of the computations
arctan2pckd:
    pxor    xmm14, xmm14
    movaps  xmm12, xmm0                     ; Preserve data
    movaps  xmm13, xmm1

    psrldq  xmm0, 12                        ; Compute atan of 4 most significant bytes
    psrldq  xmm1, 12

    call    arctan2

    movss   xmm14, xmm0                     ; Store in xmm14 and shift out of the way
    pslldq  xmm14, 4

    movaps  xmm0, xmm12                     ; Restore
    movaps  xmm1, xmm13

    psrldq  xmm0, 8                         ; Next 4 bytes
    psrldq  xmm1, 8

    call    arctan2

    movss   xmm14, xmm0                     ; Store in lower 4 bytes of xmm14
    pslldq  xmm14, 4

    movaps  xmm0, xmm12                     ; Restore
    movaps  xmm1, xmm13

    psrldq  xmm0, 4                         ; Next 4 bytes
    psrldq  xmm1, 4

    call    arctan2

    movss   xmm14, xmm0                     ; Store in xmm14
    pslldq  xmm14, 4

    movaps  xmm0, xmm12                     ; Restore
    movaps  xmm1, xmm13

    call    arctan2

    movss   xmm14, xmm0                     ; Store in xmm14
    movaps  xmm0, xmm14                     ; Result to xmm0

    ret

; Compute tan(x)
; Params:
;     xmm0 (scalar single precision): x
; Return:
;     xmm0 (scalar single precision): tan(x)
tangent:
.x          equ 0
    sub     rsp, 16
    movss   dword [rsp + .x], xmm0

    fld     dword [rsp + .x]
    fptan
    fstp    dword [rsp + .x]

    movss   xmm0, dword [rsp + .x]

    add     rsp, 16
    ret

; Compute sin(x)
; Params:
;     xmm0 (scalar single precision): x
; Return:
;     xmm0 (scalar single precision): sin(x)
sine:
.x          equ 0
    sub     rsp, 16
    movss   dword [rsp + .x], xmm0

    fld     dword [rsp + .x]
    fsin
    fstp    dword [rsp + .x]

    movss   xmm0, dword [rsp + .x]

    add     rsp, 16
    ret

; Compute cos(x)
; Params:
;     xmm0 (scalar single precision): x
; Return:
;     xmm0 (scalar single precision): cos(x)
cosine:
.x          equ 0
    sub     rsp, 16
    movss   dword [rsp + .x], xmm0

    fld     dword [rsp + .x]
    fcos
    fstp    dword [rsp + .x]

    movss   xmm0, dword [rsp + .x]

    add     rsp, 16
    ret

; Convert radians to degrees
; Params:
;     xmm0 (scalar single precision): angle in radians
; Return:
;     eax: angle in degrees
rad2deg:
    mov     eax, 180                        ; degree = rax * 180 / PI
    cvtsi2ss    xmm1, eax
    divss   xmm1, [pi]
    mulss   xmm0, xmm1
    cvtss2si    eax, xmm0
    ret

; Convert degrees to radians
; Params:
;     edi: angle in degrees
; Return:
;     xmm0 (scalar single precision): angle in radians
deg2rad:
    pxor        xmm0, xmm0
    pxor        xmm1, xmm1
    mov     eax, 180
    cvtsi2ss    xmm1, eax
    cvtsi2ss    xmm0, edi
    mulss   xmm0, [pi]
    divss   xmm0, xmm1
    ret

; Linear interpolation of dwords
; Params:
;     edi: value of lower pixel
;     esi: value of upper pixel
;     xmm0 (scalar single precision): fraction of distance between edi and esi
; Return:
;     eax: interpolated value
lerp:
    pxor    xmm1, xmm1
    pxor    xmm2, xmm2

    cvtsi2ss    xmm1, edi
    cvtsi2ss    xmm2, esi

    subss   xmm2, xmm1                      ; Difference between pixels
    mulss   xmm2, xmm0                      ; Multiply by fraction
    addss   xmm2, xmm1                      ; Add value of lower pixel

    cvtss2si    eax, xmm2                   ; Result to eax

    ret
