**README – Projet MONCOMBLE_OS**

Vous trouverez le rapport complet dans les fichiers sous le format word.

Ce dépôt contient le code et les scripts nécessaires pour compiler un système d’exploitation minimal écrit en Rust no_std, accompagné d’un bootloader (Stage1 et Stage2) pour charger le kernel depuis une partition FAT32. Le but est de démontrer un enchaînement complet : création d’une image disque, partitionnement, formatage, insertion du code d’amorçage et compilation du noyau, puis exécution dans QEMU.

---

## 1. Cloner le dépôt

```bash
git clone https://github.com/username/MONCOMBLE_OS.git
cd MONCOMBLE_OS
```

---

## 2. Exécution des opérations (en root)

Assurez-vous d’être superutilisateur (root) ou d’utiliser `sudo` pour accéder aux loop devices, effectuer le partitionnement, etc.

1. **Passer en root** (par exemple) :  
   ```bash
   sudo su
   ```
2. **Lancer le script complet** :  
   ```bash
   ./build_full.sh
   ```
   Ce script va :
   - Créer un fichier disk.img (64 Mo).  
   - Partitionner (parted) et formater en FAT32 (mkfs.fat).  
   - Extraire le boot sector, assembler les fichiers ASM (Stage1, Stage2), patcher le secteur 0.  
   - Compiler le noyau Rust no_std (cargo + rustc).  
   - Copier le binaire kernel dans l’image.

---

## 3. Démarrer l’OS dans QEMU

Une fois le script terminé, vous pouvez exécuter la commande suivante :

```bash
qemu-system-i386 -drive file=disk.img,format=raw -m 256
```

Cette commande démarre QEMU, qui tentera de booter depuis l’image `disk.img` générée.

---

## 4. Évolutions et avertissements

- Le projet demeure expérimental : QEMU va se figer sur “Booting from Hard Disk…” car ne trouve pas de code MBR standard.   
- Le script build_full.sh montre néanmoins tout le workflow : création d’une partition FAT32, placement d’un bootloader en ASM, compilation d’un kernel Rust no_std.

---

**Merci d’avoir consulté ce README !**  
Pour plus de détails sur la structure du code, la configuration Rust no_std, et les explications techniques, référez-vous aux fichiers du dépôt ou au rapport complet. 

Je me tienbs à votre entière disposition pour plus de questions.

Jules MONCOMBLE
