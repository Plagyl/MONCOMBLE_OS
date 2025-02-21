#!/bin/bash
set -e

echo "Nettoyage des fichiers précédents..."
rm -f boot1.bin boot2.bin KERNEL.BIN disk.img

echo "Assemblage de boot1.asm..."
nasm -f bin boot1.asm -o boot1.bin

echo "Assemblage de boot2.asm..."
nasm -f bin boot2.asm -o boot2.bin

echo "Compilation du kernel Rust..."
cargo rustc -Z build-std=core,compiler_builtins --target=i686-none.json --release

echo "Copie du kernel dans KERNEL.BIN..."
cp target/i686-none/release/MONCOMBLE_OS KERNEL.BIN

# Création de l'image disque :
echo "Création de l'image disque..."
dd if=boot1.bin of=disk.img bs=512 count=1 conv=notrunc
dd if=boot2.bin of=disk.img bs=512 count=8 seek=1 conv=notrunc

echo "Build terminé. Vous pouvez démarrer QEMU avec :"
echo "  qemu-system-i386 -drive format=raw,file=disk.img"

