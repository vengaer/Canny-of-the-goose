global arctan2

section .text

; Compute arctan(y/x)
; Params:
;     xmm0: y
;     xmm1: x
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

