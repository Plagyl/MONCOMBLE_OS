; =============================================================================
; boot2.asm -- Stage2 (chargé depuis BOOT2.BIN)
; Cherche "KERNEL  BIN" dans la root directory, charge le fichier à 0x100000,
; passe en mode protégé et saute au kernel.
; =============================================================================
[org 0x8000]
bits 16

%define KERNEL_LOAD   0x100000
%define STACK_16      0x9000
%define STACK_32      0x200000

%define CODE32_SEL    0x08
%define DATA32_SEL    0x10

KernelName db "KERNEL  BIN"

%define BPB_BytsPerSec 0x0B
%define BPB_SecPerClus 0x0D
%define BPB_RsvdSecCnt 0x0E
%define BPB_NumFATs    0x10
%define BPB_FATSz32    0x24
%define BPB_RootClus   0x2C

bpbBytesPerSec dw 0
bpbSecPerClus  db 0
bpbRsvdSecCnt  dw 0
bpbNumFATs     db 0
bpbFATSize     dd 0
bpbRootClus    dd 0
KernelStartClus dd 0

SectorBuf times 512 db 0

GDT: times 30 db 0

_start2:
    cli
    mov ax, 0
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, STACK_16
    sti

    call read_bpb
    call find_kernel
    cmp dword [KernelStartClus], 0
    jne .found
    jmp .halt

.found:
    mov edx, [KernelStartClus]
    call load_file_clusters

    cli
    call setup_gdt
    mov cr0, eax
    jmp CODE32_SEL:pm_entry

.halt:
    hlt
    jmp .halt

[bits 32]
pm_entry:
    mov ax, DATA32_SEL
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, STACK_32
    jmp KERNEL_LOAD

[bits 16]

read_bpb:
    pusha
    xor eax,eax
    call bios_read_one_sector
    mov ax, [SectorBuf + BPB_BytsPerSec]
    mov [bpbBytesPerSec], ax
    mov al, [SectorBuf + BPB_SecPerClus]
    mov [bpbSecPerClus], al
    mov ax, [SectorBuf + BPB_RsvdSecCnt]
    mov [bpbRsvdSecCnt], ax
    mov al, [SectorBuf + BPB_NumFATs]
    mov [bpbNumFATs], al
    mov eax, [SectorBuf + BPB_FATSz32]
    mov [bpbFATSize], eax
    mov eax, [SectorBuf + BPB_RootClus]
    mov [bpbRootClus], eax
    popa
    ret

find_kernel:
    pusha
    mov edx, [bpbRootClus]
.searchRoot:
    cmp edx, 0x0FFFFFF8
    jae .notFound
    call read_cluster
    mov ax, [bpbBytesPerSec]
    movzx ecx, byte [bpbSecPerClus]
    mul ecx
    mov cx, 32
    div cx
    mov si, SectorBuf
.entryLoop:
    cmp ax, 0
    je .nextCluster
    cmp byte [si], 0
    je .notFound
    push cx
    push si
    mov di, KernelName
    mov cx, 11
    call compare_str
    pop si
    pop cx
    cmp cx, 0
    jne .skip
    movzx eax, word [si+0x14]
    movzx edx, word [si+0x1A]
    shl eax, 16
    or eax, edx
    mov [KernelStartClus], eax
    jmp .done
.skip:
    add si, 32
    dec ax
    jmp .entryLoop
.nextCluster:
    call next_cluster_in_fat
    mov edx, eax
    jmp .searchRoot
.notFound:
    mov dword [KernelStartClus], 0
.done:
    popa
    ret

load_file_clusters:
    pusha
    mov edi, KERNEL_LOAD
.loadLoop:
    cmp edx, 0x0FFFFFF8
    jae .done
    call read_cluster
    mov ax, [bpbBytesPerSec]
    movzx ecx, byte [bpbSecPerClus]
    mul ecx
    mov cx, ax
    mov esi, SectorBuf
    rep movsb
    call next_cluster_in_fat
    mov edx, eax
    jmp .loadLoop
.done:
    popa
    ret

read_cluster:
    pusha
    mov ax, [bpbRsvdSecCnt]
    movzx eax, ax
    movzx ecx, byte [bpbNumFATs]
    mov ebx, [bpbFATSize]
    imul ecx, ebx
    add eax, ecx
    mov ecx, edx
    sub ecx, 2
    movzx ebx, byte [bpbSecPerClus]
    imul ecx, ebx
    add eax, ecx
    movzx ecx, byte [bpbSecPerClus]
    mov edi, SectorBuf
.read_sector_loop:
    push eax
    call bios_read_one_sector
    pop eax
    add edi, 512
    inc eax
    loop .read_sector_loop
    popa
    ret

next_cluster_in_fat:
    pusha
    mov eax, edx
    mov ebx, 4
    imul eax, ebx
    mov esi, eax
    mov ax, [bpbBytesPerSec]
    movzx ebx, ax
    mov eax, esi
    xor edx, edx
    div ebx
    movzx ecx, word [bpbRsvdSecCnt]
    add ecx, eax
    mov eax, ecx
    call bios_read_one_sector2
    mov eax, dword [SectorBuf2 + edx]
    and eax, 0x0FFFFFFF
    popa
    ret

compare_str:
    push ax
.cmp_loop:
    cmp cx, 0
    je .cmp_done
    lodsb
    scasb
    jne .cmp_diff
    loop .cmp_loop
.cmp_done:
    pop ax
    ret
.cmp_diff:
    mov cx, 1
    pop ax
    ret

bios_read_one_sector:
    pusha
    mov byte [dap_size], 16
    mov byte [dap+1], 0
    mov word [dap+2], 1
    mov word [dap+4], SectorBuf
    mov word [dap+6], ds
    mov dword [dap+8], eax
    mov dword [dap+12], 0
    mov ah, 0x42
    mov dl, 0x80
    lea si, [dap]
    int 0x13
    popa
    ret

bios_read_one_sector2:
    pusha
    mov byte [dap_size], 16
    mov byte [dap+1], 0
    mov word [dap+2], 1
    mov word [dap+4], SectorBuf2
    mov word [dap+6], ds
    mov dword [dap+8], eax
    mov dword [dap+12], 0
    mov ah, 0x42
    mov dl, 0x80
    lea si, [dap]
    int 0x13
    popa
    ret

setup_gdt:
    xor eax,eax
    inc eax
    mov bx, GDT
    mov dword [bx+0], 0
    mov dword [bx+4], 0
    mov word [bx+8], 0xFFFF
    mov word [bx+10], 0x0000
    mov byte [bx+12], 0x00
    mov byte [bx+13], 0x9A
    mov byte [bx+14], 0xCF
    mov byte [bx+15], 0x00
    mov word [bx+16], 0xFFFF
    mov word [bx+18], 0x0000
    mov byte [bx+20], 0x00
    mov byte [bx+21], 0x92
    mov byte [bx+22], 0xCF
    mov byte [bx+23], 0x00
    mov word [bx+24], 24-1
    mov word [bx+26], bx
    mov dword [bx+28], 0
    lgdt [bx+24]
    ret

SectorBuf2 times 512 db 0
dap_size db 0
dap: times 16 db 0

times 4096 - ($ - $$) db 0

