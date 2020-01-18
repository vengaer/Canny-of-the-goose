    section .text
    global rgb2grayscale

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
