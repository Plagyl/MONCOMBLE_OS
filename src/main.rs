#![no_std]
#![no_main]

mod panic;
mod memory;

// Importe la structure "SlabAllocator" exposée dans memory::slab_allocator
use memory::slab_allocator::SlabAllocator;
use core::panic::PanicInfo;
use core::arch::global_asm;

// Création d'un allocateur statique global
static mut SLAB_ALLOCATOR: SlabAllocator = SlabAllocator::new();

#[no_mangle]
pub extern "C" fn _start() -> ! {
    const HEAP_START: usize = 0x1000_0000;
    const HEAP_SIZE:  usize = 64 * 1024;

    unsafe {
        init_allocator(HEAP_START, HEAP_SIZE);
    }

    // Exemple d'allocation
    let ptr1 = unsafe { allocate(32) };
    let ptr2 = unsafe { allocate(64) };

    // Petit test d'écriture
    if let Some(addr) = ptr1 {
        let slice = unsafe { core::slice::from_raw_parts_mut(addr as *mut u8, 32) };
        slice[0] = 0xAB;
        slice[1] = 0xCD;
    }

    // Libération
    if let Some(addr) = ptr1 {
        unsafe { deallocate(addr) };
    }
    if let Some(addr) = ptr2 {
        unsafe { deallocate(addr) };
    }

    // Affichage du texte "MONCOMBLE_OS BOOT OK" sur VGA
    let vga_buffer = 0xb8000 as *mut u8;
    let text = b"MONCOMBLE_OS BOOT OK";
    let color = 0x0F; // Blanc sur fond noir

    for (i, &byte) in text.iter().enumerate() {
        unsafe {
            *vga_buffer.offset((i * 2) as isize) = byte;
            *vga_buffer.offset((i * 2 + 1) as isize) = color;
        }
    }

    loop {}
}

// Fonctions helper pour accéder à SLAB_ALLOCATOR
unsafe fn init_allocator(start: usize, size: usize) {
    SLAB_ALLOCATOR.init(start, size);
}

unsafe fn allocate(size: usize) -> Option<*mut u8> {
    SLAB_ALLOCATOR.allocate(size)
}

unsafe fn deallocate(ptr: *mut u8) {
    SLAB_ALLOCATOR.deallocate(ptr);
}


// Section ASM minimaliste (facultatif)
global_asm!(
    r#"
    .section .text
    .globl _start
"#
);


