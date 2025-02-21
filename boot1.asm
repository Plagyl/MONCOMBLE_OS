; ============================================================================
; boot1.asm – Stage1 Hybride (512 octets) corrigé
; On veut laisser intacts les 94 premiers octets (BPB) et les 2 derniers (signature)
; et remplacer la zone 94..509 par notre code.
; ============================================================================
[org 0]

; 1) Inclure les 94 premiers octets du bootsector original (BPB)
;    (Assurez-vous que votre NASM supporte cette syntaxe ou préparez un fichier "bpb.bin" de 94 octets.)
incbin "bootsector_original.bin", 0, 94

; 2) Zone de code qui va remplacer les octets 94..509.
; La zone disponible est de 509 - 94 + 1 = 416 octets maximum.
start:
    cli

    ; Affichage d'un message de debug
    mov si, msg_stage1
.print_loop:
    lodsb
    cmp al, 0
    je .print_done
    mov ah, 0x0E
    mov bh, 0
    mov bl, 0x07  ; attributs : blanc sur noir
    int 0x10
    jmp .print_loop
.print_done:

    ; Configuration des segments
    mov ax, 0x07C0
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti

    ; Préparation du DAP pour lire 8 secteurs (Stage2)
    mov word [dap+0], 0x0010
    mov byte [dap+2], 0
    mov byte [dap+3], 8
    mov word [dap+4], 0x8000
    mov word [dap+6], 0x0000
    xor eax, eax
    inc eax
    mov [dap_lba], eax
    mov [dap_lba+4], eax
    mov dword [dap+8], eax
    mov dword [dap+12], 0

    mov ax, cs
    mov es, ax
    lea si, [dap]
    mov ah, 0x42
    mov dl, 0x80
    int 0x13

    jmp 0x0000:0x8000

msg_stage1 db "Stage1: Hello from Stage1!",0

; DAP et données associées
dap:       times 16 db 0
dap_lba:   dd 0, 0

; 3) Remplir (avec des zéros) jusqu'à atteindre l'octet 510
times 510 - ($ - $$) db 0

; 4) Inclure la signature de boot (2 octets) depuis bootsector_original.bin.
; Ici, on extrait les 2 derniers octets (offset 510, longueur 2).
incbin "bootsector_original.bin", 510, 2

