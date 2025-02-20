OUTPUT_FORMAT(binary)
ENTRY(_start)

SECTIONS
{
  /* On veut placer le code en 0x100000. */
  . = 0x100000;

  .text :
  {
    /* On met toutes les sections .text */
    *(.text._start)
    *(.text*)
  }

  .rodata :
  {
    *(.rodata*)
  }

  .data :
  {
    *(.data*)
  }

  .bss :
  {
    *(.bss*)
    *(COMMON)
  }
}

