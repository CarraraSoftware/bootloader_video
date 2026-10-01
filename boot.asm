; +----------------------------------------------------------------------------+
; |                                                                            |
; |  MAPA DO DISCO                                                             |
; |                                                                            |
; +----------------------------------------------------------------------------+
; +==========+=============+===================================================+
; |LBA       | CONTENT     | SIZE                                              |
; +==========+=============+===+===============================================+
; | 0        | BOOT.ASM    |   }=> BOOTSECTOR (MBR)                            |
; +==========+=============+===+===============================================+
; | 1        | HELLO.ASM   |   |                                               |
; +==========+=============+   \                                               |
; | ...      | HELLO.ASM   |    }=> BOOTLOADER == 09 SETORES                   |
; +==========+=============+   /                                               |
; | 9        | HELLO.ASM   |   |                                               |
; +==========+=============+===+===============================================+
; | 10       | LINUX_HEAD  |   |                                               |
; +==========+=============+   \                                               |
; | ...      | LINUX_HEAD  |    }=> KERNEL == 32   SETORES                     |
; +==========+=============+   /                                               |
; | 41       | LINUX_HEAD  |   |                                               |
; +==========+=============+===+===============================================+
; | 42       | LINUX_BODY  |   |                                               | 
; +==========+=============+   \                                               |
; | ...      | LINUX_BODY  |    }=> KERNEL == 1409 SETORES                     |
; +==========+=============+   /                                               |
; | 1450     | LINUX       |   |                                               |
; +==========+=============+===+===============================================+
; | 1451     | INIT        |   |                                               |
; +==========+=============+   \                                               |
; | ...      | INIT        |    }=> INIT == 962 SETORES                        |
; +==========+=============+   /                                               |
; | 2412     | INIT        |   |                                               |
; +==========+=============+===+===============================================+



call boot_linux


; +----------------------------------------------------------------------------+
; |                                                                            |
; |  COMANDOS PARA COMPILAR E RODAR                                            |
; |                                                                            |
; +----------------------------------------------------------------------------+
; 
;--- COMPILAR BOOTLOADER ------------------------------------------------------+
;   nasm boot.asm -o boot                                   
;   nasm hello.asm -o hello                                   
;
;--- CRIAR DISQUETE FAKE ------------------------------------------------------+
;   # Primeiro, criar um arquivo contendo exatamente 1.44MB de bytes nulos
;   dd if=/dev/zero of=diskette bs=1474560 count=1 conv=notrunc
;   
;   # Transfere o Bootloader
;   dd if=boot of=diskette bs=512 count=1 conv=notrunc
;
;   # Transfere outros arquivos                               
;   dd if=hello  of=diskette bs=512 count=9    conv=notrunc seek=1
;   dd if=LINUX  of=diskette bs=512 count=1441 conv=notrunc seek=10
;   dd if=init   of=diskette bs=512 count=962  conv=notrunc seek=1451
;
;--- PREPARAR DISQUETE REAL ---------------------------------------------------+
;   # Transfere o ISO para o Disquete real 
;   sudo dd if=diskette  of=/dev/sdc bs=1474560 count=1 conv=notrunc
;
;
;--- RODAR O EMULADOR (qemu) --------------------------------------------------+
;   qemu-system-i386 -cpu pentium -m 32 -drive file=diskette,if=floppy,media=disk,format=raw,index=0
;
;--- RODAR O EMULADOR (bochs) -------------------------------------------------+
;   bochs -f .bochsrc -q -debugger 

;   nasm boot.asm -o boot && nasm hello.asm -o hello && dd if=/dev/zero of=diskette bs=1474560 count=1 conv=notrunc && dd if=boot of=diskette bs=512 count=1 conv=notrunc && dd if=hello  of=diskette bs=512 count=9    conv=notrunc seek=1 && dd if=LINUX  of=diskette bs=512 count=1441 conv=notrunc seek=10 && dd if=init   of=diskette bs=512 count=962  conv=notrunc seek=1451



%define HELLO 0x7E00

ORG 0x7C00

mov [DriveNumber], DL

; STACK
mov SP, 0x7000
mov BP, SP

; SEGMENTOS
mov AX, 0
mov DS, AX
mov ES, AX
mov FS, AX
mov GS, AX
mov SS, AX


mov [0x1000], 35
mov AX, [0x1000]

mov AH, 0x02           ; AH = 02H - Read Desired Sectors into Memory
mov DL, [DriveNumber]  ; DL       - Número do Drive do disco para ler setores
mov DH, 0              ; DH       - Cabeça
mov CH, 0              ; CH       - Cilindro
mov CL, 2              ; CL       - Setor
mov BX, HELLO          ; (ES:BX)  - Buffer de memory
mov AL, 9              ; AL       - Quantidade de Setores para ler
int 0x13               ; INT 13H  - diskette


mov DL, byte [DriveNumber]
jmp HELLO

DriveNumber: DB 0

TIMES 510 - ($ - $$) DB 0x00
DB 0x55
DB 0xAA

