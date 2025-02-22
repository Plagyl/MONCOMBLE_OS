#!/usr/bin/env bash
set -e

echo "[+] Nettoyage..."
rm -f disk.img boot1.bin boot2.bin KERNEL.BIN bootsector_original.bin

echo "[+] Création de disk.img (32 Mo)..."
dd if=/dev/zero of=disk.img bs=1M count=32

echo "[+] Formatage en FAT32 'partitionless'..."
# -I force la création d'un FS sur un disque sans partition
mkfs.fat -F 32 -I disk.img

# Si vous avez mtools, vous pouvez monter l'image 'partitionless' via mtools
# pour y copier KERNEL.BIN. Sinon, on peut passer par un montage loop
# direct, mais la plupart des systèmes refusent de monter du FAT32 partitionless.
# On va utiliser mtools ici (il faut un ~/.mtoolsrc avec 'mtools_skip_check=1').

echo "[+] Compilation du kernel Rust..."
cargo rustc -Z build-std=core,compiler_builtins --target=i686-none.json --release
cp target/i686-none/release/MONCOMBLE_OS KERNEL.BIN

echo "[+] Copie de KERNEL.BIN dans l'image FAT32 (partitionless)..."
# Exige que mtools soit configuré pour ignorer les partitions
# ~/.mtoolsrc => mtools_skip_check=1
mcopy -i disk.img KERNEL.BIN ::/KERNEL.BIN

echo "[+] Extraction du boot sector pour bootsector_original.bin..."
dd if=disk.img of=bootsector_original.bin bs=512 count=1

echo "[+] Assemblage de Stage1 (boot1.asm)..."
nasm -f bin boot1.asm -o boot1.bin

echo "[+] Installation de Stage1 dans le secteur 0..."
dd if=boot1.bin of=disk.img bs=512 count=1 conv=notrunc

echo "[+] Assemblage de Stage2 (boot2.asm)..."
nasm -f bin boot2.asm -o boot2.bin

echo "[+] Écriture de Stage2 aux secteurs 100..107..."
# On écrit 8 secteurs à partir du LBA=100
dd if=boot2.bin of=disk.img bs=512 seek=100 count=8 conv=notrunc

echo "[+] Build terminé."
echo "Pour lancer QEMU :"
echo "  qemu-system-i386 -drive format=raw,file=disk.img"

