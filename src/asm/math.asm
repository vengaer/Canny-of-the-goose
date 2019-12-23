    section .text
    global arctan2
    global imax
    global imin

; Compute arctan(y/x)
; Params:
;     xmm0: y
;     xmm1: x
; Return:
;     xmm0: result of the computation
arctan2:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 16                         ; Local storage
    fninit                                  ; Initialize fp unit

    movlps  qword [rbp - 8], xmm0
    movlps  qword [rbp - 16], xmm1

    fld     qword [rbp - 8]                 ; Push to stack
    fld     qword [rbp - 16]

    fpatan                                  ; atan(st(1) / st(0)), pop
    fstp    qword [rbp - 16]                ; Store result on stack
    movlps  xmm0, qword [rbp - 16]

    mov     rsp, rbp
    pop     rbp
    ret

; Compute max of two signed integers
; Params:
;     rdi: integer x
;     rsi: integer y
; Return:
;     rax: max(x,y)
imax:
    push    rbp
    mov     rbp, rsp

    mov     rax, rdi
    cmp     rax, rsi
    cmovl   rax, rsi

    mov     rsp, rbp
    pop     rbp
    ret

; Compute min of two signed integers
; Params:
;     rdi: integer x
;     rsi: integer y
; Return:
;     rax: min(x,y)
imin:
    push    rbp
    mov     rbp, rsp

    mov     rax, rdi
    cmp     rsi, rax
    cmovl   rax, rsi

    mov     rsp, rbp
    pop     rbp
    ret
