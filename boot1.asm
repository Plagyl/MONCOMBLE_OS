; ============================================================================
; boot1.asm -- Stage1 pour "partitionless FAT32"
; Conserve BPB (0..93) + signature (510..511) depuis bootsector_original.bin.
; Charge 8 secteurs depuis LBA=100 vers 0x8000, puis y saute.
; ============================================================================
[org 0]
bits 16

; 1) Inclure les 94 premiers octets du bootsector original (BPB)
incbin "bootsector_original.bin", 0, 94

start:
    cli
    ; Configurer les segments
    mov ax, 0x07C0
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti

    ; Préparer le Disk Address Packet pour lire 8 secteurs (Stage2)
    mov byte [dap_size], 16
    mov byte [dap+1], 0
    mov word [dap+2], 8        ; 8 secteurs
    mov word [dap+4], 0x8000   ; offset de chargement
    mov word [dap+6], 0x0000   ; segment 0x0000 => linéaire 0x00000:0x8000
    mov dword [dap+8], 100     ; LBA=100 (où on a écrit boot2.bin)
    mov dword [dap+12], 0
    mov ah, 0x42
    mov dl, 0x80
    lea si, [dap]
    int 0x13

    ; Sauter à 0x0000:0x8000
    jmp 0x0000:0x8000

; Disk Address Packet
dap_size db 0
dap: times 16 db 0

; Remplir jusqu'à l'octet 510
times 510 - ($ - $$) db 0

; 2) Inclure la signature (2 octets) depuis bootsector_original.bin
incbin "bootsector_original.bin", 510, 2

