    global rgb2grayscale

    section .text

; Convert rgb image to grayscale
; Params: 
;     rdi: byte ptr to data
;     rsi: width of image (in pixels)
;     rdx: height of image (in pixels)
;     rcx:  dword pointer to number of channels
rgb2grayscale:
    push    rbp
    mov     rbp, rsp

    mov     rax, rdx
    mov     dword [rcx], 1

    mov     rsp, rbp
    pop     rbp
    ret
