#!/usr/bin/env bash
set -e

echo "[+] Nettoyage des loop devices pour disk.img..."
LOOPDEV=$(losetup -j disk.img | cut -d: -f1)
if [ -n "$LOOPDEV" ]; then
    echo "[+] Detaching existing loop device $LOOPDEV for disk.img"
    sudo losetup -d "$LOOPDEV"
fi

echo "[+] Nettoyage général..."
rm -f disk.img boot1.bin boot2.bin KERNEL.BIN bootsector_original.bin

echo "[+] Création de disk.img (32 Mo)..."
dd if=/dev/zero of=disk.img bs=1M count=32

echo "[+] Partitionnement MBR..."
parted -s disk.img mklabel msdos
parted -s disk.img mkpart primary fat32 2048s 100%
parted -s disk.img set 1 boot on

echo "[+] Association du loop device..."
LOOPDEV=$(sudo losetup -f)
echo "[+] Associating loop device $LOOPDEV with disk.img..."
sudo losetup --partscan "$LOOPDEV" disk.img

echo "[+] Formatage de la partition FAT32..."
sudo mkfs.fat -F 32 "${LOOPDEV}p1"

echo "[+] Montage de la partition..."
sudo mkdir -p /mnt/os
sudo mount "${LOOPDEV}p1" /mnt/os

echo "[+] Compilation du kernel Rust..."
cargo rustc -Z build-std=core,compiler_builtins --target=i686-none.json --release
cp target/i686-none/release/MONCOMBLE_OS KERNEL.BIN

echo "[+] Assemblage de boot2.asm (Stage2)..."
nasm -f bin boot2.asm -o boot2.bin

echo "[+] Installation de BOOT2.BIN à partir du secteur 1..."
# Charger Stage2 directement dans le disque (8 secteurs, à partir de secteur 1)
sudo dd if=boot2.bin of="${LOOPDEV}p1" bs=512 seek=1 count=8 conv=notrunc

echo "[+] Copie de KERNEL.BIN dans la partition FAT32..."
sudo cp KERNEL.BIN /mnt/os/KERNEL.BIN

echo "[+] Extraction du boot sector FAT32 (bootsector_original.bin)..."
sudo dd if="${LOOPDEV}p1" of=bootsector_original.bin bs=512 count=1

echo "[+] Assemblage de boot1.asm (Stage1)..."
nasm -f bin boot1.asm -o boot1.bin

echo "[+] Installation de Stage1 dans le boot sector de la partition..."
sudo dd if=boot1.bin of="${LOOPDEV}p1" bs=512 count=1 conv=notrunc

echo "[+] Démontage et libération du loop device..."
sudo umount /mnt/os
sudo losetup -d "$LOOPDEV"

echo "[+] Build terminé !"
echo "[+] Pour lancer QEMU :"
echo "    qemu-system-i386 -drive format=raw,file=disk.img"

