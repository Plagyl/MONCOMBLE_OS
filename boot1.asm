; ============================================================================
; boot1.asm -- Stage1 minimal (boot sector de la partition FAT32)
; Conserve la BPB (octets 0..93) et la signature (octets 510..511)
; depuis bootsector_original.bin, et charge Stage2 à partir du secteur 1.
; ============================================================================
[org 0]
bits 16

; Inclure les 94 premiers octets du bootsector original (BPB)
incbin "bootsector_original.bin", 0, 94

start:
    cli
    ; Configuration minimale des segments
    mov ax, 0x07C0
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti

    ; Préparer le Disk Address Packet (DAP) pour lire 8 secteurs
    mov byte [dap_size], 16
    mov byte [dap+1], 0
    mov word [dap+2], 8         ; Lire 8 secteurs
    mov word [dap+4], 0x8000     ; Charger à l'adresse 0x8000
    mov word [dap+6], 0          ; Segment = 0x0000 (physique = 0x8000)
    mov dword [dap+8], 1        ; LBA = 1 (Stage2 se trouve à partir du secteur 1)
    mov dword [dap+12], 0
    mov ah, 0x42
    mov dl, 0x80
    lea si, [dap]
    int 0x13

    ; Sauter vers Stage2 chargé à 0x8000
    jmp 0x0000:0x8000

; Structure DAP
dap_size db 0
dap: times 16 db 0

; Remplissage jusqu'à l'octet 510
times 510 - ($ - $$) db 0

; Inclure la signature (2 octets) depuis bootsector_original.bin
incbin "bootsector_original.bin", 510, 2

