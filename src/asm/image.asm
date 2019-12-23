global rgb2grayscale

section .text

; Convert rgb image to grayscale
; Params: 
;     rdi: byte ptr to data, overwritten with output
;     esi: width of image (in pixels)
;     edx: height of image (in pixels)
;     rcx: dword pointer to number of channels
; Return:
;     -
rgb2grayscale:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 8                          ; Allocate local storage

    push    rcx                             ; rcx used in loop
    xor     rcx, rcx

    mov     rax, rdi

    push    rbx                             ; Preserve rbx
    mov     rbx, rsi                        ; Total number of pixels
    imul    rbx, rdx
.loop:
    push    rbx

    mov     rbx, rcx                        ; Calculate byte offset (iter_num * 3)
    mov     qword [rbp - 8], 3
    imul    rbx, qword [rbp - 8]
    
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
    movzx   di, dil         ; Zero extend (8-bit => 16-bit)
    movzx   si, sil
    movzx   dx, dl

    mov     ax, di          ; Compute mean
    add     ax, si
    add     ax, dx
    xor     rdx, rdx
    mov     di, 3
    div     di

    mov     rsp, rbp
    pop     rbp
    ret
