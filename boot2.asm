; =============================================================================
; boot2.asm -- Stage2 pour FAT32 + debug
; =============================================================================
[org 0x8000]
bits 16

%define KERNEL_LOAD   0x100000
%define STACK_16      0x9000
%define STACK_32      0x200000

%define CODE32_SEL    0x08
%define DATA32_SEL    0x10

; Nom de fichier 8.3
KernelName db "KERNEL  BIN"

; Offsets BPB FAT32
%define BPB_BytsPerSec 0x0B
%define BPB_SecPerClus 0x0D
%define BPB_RsvdSecCnt 0x0E
%define BPB_NumFATs    0x10
%define BPB_FATSz32    0x24
%define BPB_RootClus   0x2C

; Variables
bpbBytesPerSec dw 0
bpbSecPerClus  db 0
bpbRsvdSecCnt  dw 0
bpbNumFATs     db 0
bpbFATSize     dd 0
bpbRootClus    dd 0
KernelStartClus dd 0

SectorBuf  times 512 db 0
FatSector  times 512 db 0

%define GDT_START (0x8000 + 0x0F00)
GDT: times 30 db 0

; ----------------------------------------------------------------------------
; Entrée principale
; ----------------------------------------------------------------------------
_start2:
    cli
    mov ax, 0
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, STACK_16
    sti

    call print_stage2

    ; 1) Lire la BPB
    call read_bpb
    call print_bpb_ok

    ; 2) Trouver KERNEL.BIN
    call find_kernel
    cmp dword [KernelStartClus], 0
    jne .found
    call print_nokernel
    jmp .halt

.found:
    call print_found

    ; 3) Charger le fichier
    mov edx, [KernelStartClus]
    call load_file_clusters

    ; 4) Mode protégé
    cli
    call setup_gdt
    mov cr0, eax
    jmp CODE32_SEL:pm_entry

.halt:
    hlt
    jmp .halt

; ----------------------------------------------------------------------------
; pm_entry
; ----------------------------------------------------------------------------
[bits 32]
pm_entry:
    mov ax, DATA32_SEL
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, STACK_32
    jmp KERNEL_LOAD

; ----------------------------------------------------------------------------
; On repasse en 16 bits pour le bas-level
; ----------------------------------------------------------------------------
[bits 16]

; ----------------------------------------------------------------------------
; Fonctions debug
; ----------------------------------------------------------------------------
print_stage2:
    mov si, msg_stage2
    call print_str
    ret

print_bpb_ok:
    mov si, msg_bpb_ok
    call print_str
    ret

print_nokernel:
    mov si, msg_nokernel
    call print_str
    ret

print_found:
    mov si, msg_found
    call print_str
    ret

print_str:
.ps_loop:
    lodsb
    cmp al,0
    je .done
    mov ah, 0x0E
    mov bh, 0
    mov bl, 0x07
    int 0x10
    jmp .ps_loop
.done:
    ret

msg_stage2   db "Stage2: Hello from Stage2!",0
msg_bpb_ok   db "Stage2: BPB read OK!",0
msg_nokernel db "Stage2: KERNEL.BIN not found!",0
msg_found    db "Stage2: Found KERNEL.BIN, loading...",0

; ----------------------------------------------------------------------------
; read_bpb, find_kernel, load_file_clusters, read_cluster, next_cluster_in_fat
; Identiques à ton code, ajoutés ci-dessous
; ----------------------------------------------------------------------------

read_bpb:
    pusha
    xor eax,eax
    call bios_read_one_sector  ; LBA=0 => SectorBuf
    mov ax, [SectorBuf + BPB_BytsPerSec]
    mov [bpbBytesPerSec], ax

    mov al, [SectorBuf + BPB_SecPerClus]
    mov [bpbSecPerClus], al

    mov ax, [SectorBuf + BPB_RsvdSecCnt]
    mov [bpbRsvdSecCnt], ax

    mov dl, [SectorBuf + BPB_NumFATs]
    mov [bpbNumFATs], dl

    xor edx, edx
    mov dx, [SectorBuf + BPB_FATSz32]
    mov cx, [SectorBuf + BPB_FATSz32+2]
    shl ecx,16
    or edx,ecx
    mov [bpbFATSize], edx

    xor edx,edx
    mov dx, [SectorBuf + BPB_RootClus]
    mov cx, [SectorBuf + BPB_RootClus+2]
    shl ecx,16
    or edx,ecx
    mov [bpbRootClus], edx

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
    xor cx,cx
    mov cl, [bpbSecPerClus]
    mul cx
    mov cx,32
    div cx
    mov si, SectorBuf

.entryLoop:
    cmp ax,0
    je .nextCluster
    mov bl,[si]
    cmp bl,0
    je .notFound
    push si
    mov di, KernelName
    mov cx,11
    call compare_str
    pop si
    cmp cx,0
    jne .skip

    mov dx,[si+0x1A]
    mov ax,[si+0x14]
    shl eax,16
    or eax,edx
    mov [KernelStartClus], eax
    jmp .done

.skip:
    add si,32
    dec ax
    jmp .entryLoop

.nextCluster:
    call next_cluster_in_fat
    jmp .searchRoot

.notFound:
    mov dword [KernelStartClus],0
.done:
    popa
    ret

load_file_clusters:
    pusha
    mov edi, KERNEL_LOAD
.loadLoop:
    cmp edx,0x0FFFFFF8
    jae .done
    call read_cluster
    mov ax, [bpbBytesPerSec]
    xor cx,cx
    mov cl,[bpbSecPerClus]
    mul cx
    mov cx,ax
    mov esi, SectorBuf
    rep movsb
    call next_cluster_in_fat
    jmp .loadLoop
.done:
    popa
    ret

read_cluster:
    pusha
    mov ax,[bpbRsvdSecCnt]
    mov bx,[bpbNumFATs]
    mov edx,[bpbFATSize]
    mul bx
    add ax,ax
    mov cx,[bpbSecPerClus]
    push cx
    mov bx,[bpbBytesPerSec]
    sub edx,2
    add edx,eax
    pop cx
    mov si,0

.readLoop:
    push ax
    push bx
    push cx
    push dx
    call bios_read_one_sector
    pop dx
    inc edx
    add si,512
    cmp si,512*8
    ja .limitError
    pop cx
    loop .readLoop
    pop bx
    pop ax
    add edx,2
    popa
    ret

.limitError:
    hlt
    ret

next_cluster_in_fat:
    pusha
    mov eax,edx
    shl eax,2
    mov bx,[bpbBytesPerSec]
    xor edx,edx
    div ebx
    ; EAX=secteurFat, EDX=offsetInSector
    ; (Simplifié: on ne lit pas la FAT pour de vrai)
    popa
    ret

compare_str:
    push ax
.cmp_loop:
    cmp cx,0
    je .ok
    lodsb
    scasb
    jne .diff
    loop .cmp_loop
.ok:
    pop ax
    ret
.diff:
    mov cx,1
    pop ax
    ret

bios_read_one_sector:
    pusha
    mov word [dap+0],0x0010
    mov byte [dap+2],0
    mov byte [dap+3],1
    mov word [dap+4],si
    mov word [dap+6],ds
    mov [dapLBA],eax
    mov [dapLBA+4],dword 0
    mov dword [dap+8],0

    mov ax,cs
    mov es,ax
    lea si,[dap]
    mov ah,0x42
    mov dl,0x80
    int 0x13
    popa
    ret

dap: times 16 db 0
dapLBA: times 8 db 0

setup_gdt:
    xor eax,eax
    inc eax
    mov bx,GDT_START
    ; Null
    mov word [bx],0
    mov word [bx+2],0
    mov word [bx+4],0
    mov word [bx+6],0

    ; Code32
    mov word [bx+8],0xFFFF
    mov word [bx+10],0x0000
    mov byte [bx+12],0x00
    mov byte [bx+13],0x9A
    mov byte [bx+14],0xCF
    mov byte [bx+15],0x00

    ; Data32
    mov word [bx+16],0xFFFF
    mov word [bx+18],0x0000
    mov byte [bx+20],0x00
    mov byte [bx+21],0x92
    mov byte [bx+22],0xCF
    mov byte [bx+23],0x00

    mov word [bx+24],24-1
    mov word [bx+26],bx
    mov word [bx+28],0
    lgdt [bx+24]
    ret

times 4096 - ($-$$) db 0

