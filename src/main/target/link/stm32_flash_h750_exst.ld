/*
*****************************************************************************
**
**  File        : stm32_flash_h750_exst.ld
**
**  Abstract    : Linker script for STM32H743xI Device with
**                512K AXI-RAM mapped onto AXI bus on D1 domain
**                128K SRAM1 mapped on D2 domain
**                128K SRAM2 mapped on D2 domain
**                 32K SRAM3 mapped on D2 domain
**                 64K SRAM4 mapped on D3 domain
**                 64K ITCM
**                128K DTCM
**
*****************************************************************************
*/

/* Entry Point */
ENTRY(Reset_Handler)

/*
0x00000000 to 0x0000FFFF   64K ITCM
0x20000000 to 0x2001FFFF  128K DTCM
0x24000000 to 0x2407FFFF  512K AXI SRAM, D1 domain, main RAM
0x30000000 to 0x3001FFFF  128K SRAM1, D2 domain, unused
0x30020000 to 0x3003FFFF  128K SRAM2, D2 domain, unused
0x30040000 to 0x30047FFF   32K SRAM3, D2 domain, unused
0x38000000 to 0x3800FFFF   64K SRAM4, D3 domain, unused
0x38800000 to 0x38800FFF    4K BACKUP SRAM, Backup domain, unused

0x08000000 to 0x0801FFFF  128K isr vector, startup code, firmware, no config! // FLASH_Sector_0
*/

/* 

For H7 EXST (External Storage) targets a binary is built that is placed on an external device.
The bootloader will then copy this entire binary to RAM, at the CODE_RAM address.  The bootloader
then executes code at the CODE_RAM address.

Currently, this is inefficient as there are two copies of some sections in RAM.  e.g. .tcm_code.

It would be technically possible to free more RAM by having a more intelligent build system
and bootloader which creates files for each of the sections that are usually copied from flash
to ram and one section for the main code.  e.g. one file for .tcm_code, one file for .data and
one for the main code/data, then load each to the appropriate address and adjust the usual startup
code which will no-longer need to duplicate code/data sections from RAM to ITCM/DTCM RAM.

The initial CODE_RAM is sized at 448K to enable all firmware features and to as much RAM free as 
possible.

*/

/* see .exst section below */
_exst_hash_size = 64; 

/* Specify the memory areas */
MEMORY
{
    ITCM_RAM (rwx)    : ORIGIN = 0x00000000, LENGTH = 64K
    DTCM_RAM (rwx)    : ORIGIN = 0x20000000, LENGTH = 128K
    RAM (rwx)         : ORIGIN = 0x24000000, LENGTH = 64K
    CODE_RAM (rx)     : ORIGIN = 0x24010000, LENGTH = 448K - _exst_hash_size
    EXST_HASH (rx)    : ORIGIN = 0x24010000 + LENGTH(CODE_RAM), LENGTH = _exst_hash_size

    D2_RAM (rwx)      : ORIGIN = 0x30000000, LENGTH = 256K /* SRAM1 + SRAM2 */

    MEMORY_B1 (rx)    : ORIGIN = 0x60000000, LENGTH = 0K
    QUADSPI (rx)      : ORIGIN = 0x90000000, LENGTH = 0K 
}

REGION_ALIAS("STACKRAM", DTCM_RAM)
REGION_ALIAS("FASTRAM", DTCM_RAM)

/* INCLUDE "stm32_flash_f7_split.ld" */
/*
*****************************************************************************
**
**  File        : stm32_flash_f7_split.ld
**
**  Abstract    : Common linker script for STM32 devices.
**
*****************************************************************************
*/

/* Entry Point */
ENTRY(Reset_Handler)

/* Highest address of the user mode stack */
_estack = ORIGIN(STACKRAM) + LENGTH(STACKRAM);    /* end of RAM */

/* Base address where the quad spi. */
__quad_spi_start = ORIGIN(QUADSPI);

/* Generate a link error if heap and stack don't fit into RAM */
_Min_Heap_Size = 0;      /* required amount of heap  */
_Min_Stack_Size = 0x800; /* required amount of stack */

/* Define output sections */
SECTIONS
{
  /* The startup code goes first into CODE_RAM */
  .isr_vector :
  {
    . = ALIGN(512);
    PROVIDE (isr_vector_table_base = .);
    KEEP(*(.isr_vector)) /* Startup code */
    . = ALIGN(4);
  } >CODE_RAM

  /* The program code and other data goes into CODE_RAM */
  .text :
  {
    . = ALIGN(4);
    *(.text)           /* .text sections (code) */
    *(.text*)          /* .text* sections (code) */
    *(.rodata)         /* .rodata sections (constants, strings, etc.) */
    *(.rodata*)        /* .rodata* sections (constants, strings, etc.) */
    *(.glue_7)         /* glue arm to thumb code */
    *(.glue_7t)        /* glue thumb to arm code */
    *(.eh_frame)

    KEEP (*(.init))
    KEEP (*(.fini))

    . = ALIGN(4);
    _etext = .;        /* define a global symbols at end of code */
  } >CODE_RAM

  /* Critical program code goes into ITCM RAM */
  /* Copy specific fast-executing code to ITCM RAM */ 
  tcm_code = LOADADDR(.tcm_code); 
  .tcm_code :
  {
    . = ALIGN(4);
    tcm_code_start = .; 
    *(.tcm_code)
    *(.tcm_code*)
    . = ALIGN(4);
    tcm_code_end = .; 
  } >ITCM_RAM AT >CODE_RAM

  .ARM.extab   : 
  { 
    *(.ARM.extab* .gnu.linkonce.armextab.*) 
  } >CODE_RAM
  
  .ARM : 
  {
    __exidx_start = .;
    *(.ARM.exidx*) __exidx_end = .;
  } >CODE_RAM

  .pg_registry :
  {
    PROVIDE_HIDDEN (__pg_registry_start = .);
    KEEP (*(.pg_registry))
    KEEP (*(SORT(.pg_registry.*)))
    PROVIDE_HIDDEN (__pg_registry_end = .);
  } >CODE_RAM
  
  .pg_resetdata :
  {
    PROVIDE_HIDDEN (__pg_resetdata_start = .);
    KEEP (*(.pg_resetdata))
    PROVIDE_HIDDEN (__pg_resetdata_end = .);
  } >CODE_RAM

  /* used by the startup to initialize data */
  _sidata = LOADADDR(.data);

  /* Initialized data sections goes into RAM, load LMA copy after code */
  .data :
  {
    . = ALIGN(4);
    _sdata = .;        /* create a global symbol at data start */
    *(.data)           /* .data sections */
    *(.data*)          /* .data* sections */

    . = ALIGN(4);
    _edata = .;        /* define a global symbol at data end */
  } >RAM AT >CODE_RAM

  /* Uninitialized data section */
  . = ALIGN(4);
  .bss (NOLOAD) :
  {
    /* This is used by the startup in order to initialize the .bss secion */
    _sbss = .;         /* define a global symbol at bss start */
    __bss_start__ = _sbss;
    *(.bss)
    *(SORT_BY_ALIGNMENT(.bss*))
    *(COMMON)

    . = ALIGN(4);
    _ebss = .;         /* define a global symbol at bss end */
    __bss_end__ = _ebss;
  } >RAM

  /* Uninitialized data section */
  . = ALIGN(4);
  .sram2 (NOLOAD) :
  {
    /* This is used by the startup in order to initialize the .sram2 secion */
    _ssram2 = .;         /* define a global symbol at sram2 start */
    __sram2_start__ = _ssram2;
    *(.sram2)
    *(SORT_BY_ALIGNMENT(.sram2*))

    . = ALIGN(4);
    _esram2 = .;         /* define a global symbol at sram2 end */
    __sram2_end__ = _esram2;
  } >RAM

  /* used during startup to initialized fastram_data */
  _sfastram_idata = LOADADDR(.fastram_data);

  /* Initialized FAST_RAM section for unsuspecting developers */
  .fastram_data :
  {
    . = ALIGN(4);
    _sfastram_data = .;        /* create a global symbol at data start */
    *(.fastram_data)           /* .data sections */
    *(.fastram_data*)          /* .data* sections */

    . = ALIGN(4);
    _efastram_data = .;        /* define a global symbol at data end */
  } >FASTRAM AT >CODE_RAM

  . = ALIGN(4);
  .fastram_bss (NOLOAD) :
  {
    _sfastram_bss = .;
    __fastram_bss_start__ = _sfastram_bss;
    *(.fastram_bss)
    *(SORT_BY_ALIGNMENT(.fastram_bss*))

    . = ALIGN(4);
    _efastram_bss = .;
    __fastram_bss_end__ = _efastram_bss;
  } >FASTRAM

  .DMA_RAM (NOLOAD) :
  {
    _sdmaram = .;
    _dmaram_start__ = _sdmaram;
    KEEP(*(.DMA_RAM))
    _edmaram = .;
    _dmaram_end__ = _edmaram;
  } >D2_RAM
  
  .persistent_data (NOLOAD) :
  {
    __persistent_data_start__ = .;
    *(.persistent_data)
    . = ALIGN(4);
    __persistent_data_end__ = .;
  } >RAM
  

  /* User_heap_stack section, used to check that there is enough RAM left */
  _heap_stack_end = ORIGIN(STACKRAM)+LENGTH(STACKRAM) - 8; /* 8 bytes to allow for alignment */
  _heap_stack_begin = _heap_stack_end - _Min_Stack_Size  - _Min_Heap_Size;
  . = _heap_stack_begin;
  ._user_heap_stack :
  {
    . = ALIGN(4);
    PROVIDE ( end = . );
    PROVIDE ( _end = . );
    . = . + _Min_Heap_Size;
    . = . + _Min_Stack_Size;
    . = ALIGN(4);
  } >STACKRAM = 0xa5

  /* MEMORY_bank1 section, code must be located here explicitly            */
  /* Example: extern int foo(void) __attribute__ ((section (".mb1text"))); */
  .memory_b1_text :
  {
    *(.mb1text)        /* .mb1text sections (code) */
    *(.mb1text*)       /* .mb1text* sections (code)  */
    *(.mb1rodata)      /* read-only data (constants) */
    *(.mb1rodata*)
  } >MEMORY_B1

  /* Create space for a hash.  Currently an MD5 has is used, which is 16   */
  /* bytes long. however the last 64 bytes are RESERVED for hash related   */
  .exst_hash :
  {
    /* 64 bytes is the size of an MD5 hashing block size.                  */
    . = ORIGIN(EXST_HASH);

    BYTE(0x00); /* block format */
    BYTE(0x00); /* Checksum method, 0x00 = MD5 hash */
    BYTE(0x00); /* Reserved */
    BYTE(0x00); /* Reserved */
    
    /* Fill the last 60 bytes with data, including an empty hash aligned   */
    
    /* to the last 16 bytes.                                               */
    FILL(0x00000000); /* Reserved */
    
    . = ORIGIN(EXST_HASH) + LENGTH(EXST_HASH) - 16;
    __md5_hash_address__ = .;
    LONG(0x00000000);
    LONG(0x00000000);
    LONG(0x00000000);
    LONG(0x00000000);
    . = ORIGIN(EXST_HASH) + LENGTH(EXST_HASH);
    __firmware_end__ = .;
  } >EXST_HASH

  /* Remove information from the standard libraries */
  /DISCARD/ :
  {
    libc.a ( * )
    libm.a ( * )
    libgcc.a ( * )
  }

  .ARM.attributes 0 : { *(.ARM.attributes) }
}
