    section .text
    global arctan2
    global lerp
    global imax
    global imin

; Compute arctan(y/x)
; Params:
;     xmm0 (scalar double precision): y
;     xmm1 (scalar double precision): x
; Return:
;     xmm0 (scalar double precision): result of the computation
arctan2:
.y  equ     8
.x  equ     0
    sub     rsp, 16                         ; Local storage

    movsd   qword [rsp + .y], xmm0
    movsd   qword [rsp + .x], xmm1

    fld     qword [rsp + .y]                ; Push to fp stack
    fst     st1                             ; Copy st0 to st1
    fld     qword [rsp + .x]

    fpatan                                  ; atan(st1 / st0), pop
    fstp    qword [rsp + .x]                ; Pop result to stack
    movsd   xmm0, qword [rsp + .x]

    add     rsp, 16                         ; Restore rsp
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

; Compute max of two signed integers
; Params:
;     rdi: integer x
;     rsi: integer y
; Return:
;     rax: max(x,y)
imax:
    mov     rax, rdi
    cmp     rax, rsi
    cmovl   rax, rsi

    ret

; Compute min of two signed integers
; Params:
;     rdi: integer x
;     rsi: integer y
; Return:
;     rax: min(x,y)
imin:
    mov     rax, rdi
    cmp     rsi, rax
    cmovl   rax, rsi

    ret
