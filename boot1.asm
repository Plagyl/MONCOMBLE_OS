; ============================================================================
; boot1.asm – Stage1 Hybride (512 octets), pas de double org
; Utilise [absolute 0x5E] pour insérer le code en offset 94..509
; ============================================================================
[org 0]
bits 16

; 1) Inclure les 512 octets originaux du secteur
;    (extrait via `dd if=/dev/loop0p1 of=bootsector_original.bin bs=512 count=1`)
incbin "bootsector_original.bin"   ; Fichier EXACTEMENT 512 octets

; Après ce incbin, on est “virtuellement” à offset 512 dans la sortie. 
; Mais on veut au contraire modifier la zone 94..509 du contenu incbin. 
; => On va “absolument” pointer l’emplacement 0x5E (94)
; => Les instructions suivantes écraseront l’offset 94.. du buffer
; => On NE touche pas 0x00..0x5D (BPB) ni 0x1FE..0x1FF (signature).

[absolute 0x5E]         ; Force l’offset à 94 dans ce fichier de 512 octets

start:
    cli

    ; -- Afficher un message de debug --
    mov si, msg_stage1
.print_loop:
    lodsb
    cmp al, 0
    je .print_done
    mov ah, 0x0E
    mov bh, 0
    mov bl, 0x07  ; blanc/noir
    int 0x10
    jmp .print_loop

.print_done:

    ; Segment setup
    mov ax, 0x07C0
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti

    ; Lire 8 secteurs => Stage2
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

; DAP
dap: times 16 db 0
dap_lba: dd 0, 0

; IMPORTANT: On NE touche pas offset 510..511 (0x55AA) => c’est déjà dans bootsector_original.bin
; Pas de times(...) ni dw 0xAA55

