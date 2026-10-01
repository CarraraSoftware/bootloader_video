BITS 16
ORG 0x7E00

; ||--------------------------------------------------------------------------||
; ||--------------------------------------------------------------------------||
;  \\                                                                         //
;   \\                         REAL MODE                                     //
;    \\                                                                     //
;     \\-------------------------------------------------------------------//
;      \\-----------------------------------------------------------------//

entry:
    mov byte [DriveNumber], DL


    ; ativando linha A20
    ; modo 1: FastA20, comunicação direta com hardware
    in AL, 0x92
    or AL, 2
    out 0x92, AL
    ; modo 2: interrupt da bios
    mov AH, 0x24
    mov AL, 0x01
    int 0x15

    cli ; clear interrupt

    lgdt [gdt_pointer]

    mov EAX, CR0
    or  AL, 0b00000001
    mov CR0, EAX



    jmp far 8:main


lba_to_chs:
; params:
;    mov AX, { LBA } -> LBA = Linear Block Address (indíce do setor começando do 0)

; return:
;   mov DH, { H }  -> LBA / NumSects % NumHeads   
;   mov CH, { C }  -> LBA / NumSects / NumHeads     
;   mov CL, { S }  -> LBA % NumSects + 1

; DISKETTE => NumSects = 18 | NumHeads = 2
    push BX

    mov DX, 0
    mov BX, 18
    div BX ; -> AX / 18 => AX = Q, DX = R

    inc DX ; DX = DX + 1
    mov CL, DL ; coordenada S tá pronta

    mov DX, 0
    mov BX, 2
    div BX ; -> AX / 2 => AX = Q, DX = R

    mov CH, AL  ; coordenada C tá pronta

    xchg DH, DL  ; coordenada H tá pronta

    pop BX

    ret


read_sectors:
; params:
;   mov BX, { BUFFER }    - endereço de memória para onde copiar os setores
;   mov SI, { LBA }       - o índice linear do primeiro setor a ser lido
;   mov DI, { NUM_SECTS } - quantidade de setores pra ler 

    push AX
    push BX
    push SI
    push DI

.loop:

    cmp DI, 0 ; compare -> DI == 0 ? se sim, ZF (zero flag) = true (1)
    jz .end   ; if (ZF == true) { jmp .end }

    mov AX, SI
    call lba_to_chs
    call read_sector

    inc SI
    dec DI
    add BX, 512
    jmp .loop


.end:
    pop DI
    pop SI
    pop BX
    pop AX
    ret


read_sector:
; params:
;   mov DH, { H }    
;   mov CH, { C }    
;   mov CL, { S }    
;   mov BX, { BUFFER }

    push AX
    push DX
    push SI

    mov SI, 3

.retry:
    cmp SI, 0
    jz .error

    stc ; set carry. se o int não falhar, a flag de carry vai ser zerada

    mov AH, 0x02           ; AH = 02H - Read Desired Sectors into Memory
    mov DL, [DriveNumber]  ; DL       - Número do Drive do disco para ler setores
    mov AL, 1              ; AL       - Quantidade de Setores para ler
    int 0x13               ; INT 13H  - diskette 
    dec SI

    jnc .end ; jump not carry == jump se não houve falha

    call disk_reset 
    jmp .retry

.error:
    mov AL, '!'
    call panic

.end:
    pop SI
    pop DX
    pop AX
    
    ret

panic:
; mov AL, { ch } - caracter para printar antes de entrar no loop infinito
    mov AH, byte 0x0E 
    mov BH, byte 0x00
    mov BL, byte 0x04
    int 0x10
    jmp $


disk_reset:
    push AX
    push DX

    mov AH, byte 0x00
    mov DL, byte [DriveNumber]
    int 0x13

    pop DX
    pop AX
    ret


boot_linux:

    ; desliga motor do drive de disquete
    mov DX, 0x03F2
    mov AL, 0x00
    out DX, AL


    ; base_ptr = 0x10000
    ; seg      = 0x1000

    mov AX, 0x1000
    mov DS, AX
    mov ES, AX
    mov FS, AX
    mov GS, AX
    mov SS, AX

    mov SP, 0xE000 ; heap_end
    mov BP, SP

    cli

    jmp far 0x1020:0  ;CABEÇÃO DO PENGUIM
    ret ; unreachable



DriveNumber: DB 0

callback: DD 0


gdt_pointer:
dw gdt - gdt_end - 1  ; 2 bytes: limit = size - 1
dd gdt                ; 4 bytes: address

align 8
gdt:
db 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000 ; 00 - NULL SEGMENT
db 0b11111111, 0b11111111, 0b00000000, 0b00000000, 0b00000000, 0b10011010, 0b11001111, 0b00000000 ; 08 - CODE - 32 BITS
db 0b11111111, 0b11111111, 0b00000000, 0b00000000, 0b00000000, 0b10010010, 0b11001111, 0b00000000 ; 16 - DATA - 32 BITS
db 0b11111111, 0b11111111, 0b00000000, 0b00000000, 0b00000000, 0b10011010, 0b10001111, 0b00000000 ; 24 - CODE - 16 BITS
db 0b11111111, 0b11111111, 0b00000000, 0b00000000, 0b00000000, 0b10010010, 0b10001111, 0b00000000 ; 32 - DATA - 16 BITS
gdt_end:


; ||--------------------------------------------------------------------------||
; ||--------------------------------------------------------------------------||
;  \\                                                                         //
;   \\                      PROTECTED MODE                                   //
;    \\                                                                     //
;     \\-------------------------------------------------------------------//
;      \\-----------------------------------------------------------------//


BITS 32

protected_ESP: DD 0
protected_EBP: DD 0

main:
    mov AX, 16
    mov DS, AX
    mov ES, AX
    mov FS, AX
    mov GS, AX
    mov SS, AX

    mov ESP, 0x90000
    mov EBP, ESP


    ; LINUX_HEAD
    mov EBX, 0x10000  ; DEST
    mov ESI, 10       ; LBA
    mov EDI, 32       ; N
    call read_all_sectors
    call setup_kernel


    ; LINUX_BODY
    mov EBX, 0x100000  ; DEST
    mov ESI, 42        ; LBA
    mov EDI, 1409      ; N
    call read_all_sectors

    ; INIT
    mov EBX, 0x200000  ; DEST
    mov ESI, 1451      ; LBA
    mov EDI, 962       ; N
    call read_all_sectors

    mov dword [callback], boot_linux
    call run_real_mode_callback


    jmp $ ; unreachable

setup_kernel:
    push EAX
    push ESI
    push EDI
    push ECX

    mov EAX, 0x10000                   ; base_ptr
    mov [EAX + 0x210], byte 0xFF       ; type_of_loader
    mov [EAX + 0x211], byte 0b10000001 ; loadflags  
    mov [EAX + 0x218], dword 0x200000  ; ramdisk_image = <initrd_address>;
    mov [EAX + 0x21C], dword 492544    ; ramdisk_size = <initrd_size>;
    mov [EAX + 0x224], word 0xDE00     ; heap_end_ptr = heap_end - 0x200 = 0xE000 - 0x200
    mov [EAX + 0x228], dword 0x1E000   ; cmd_line_ptr = base_ptr + heap_end = 0x10000 + 0xE000

    ; strcpy(cmd_line_ptr, cmdline);
    mov ESI, cmdline ; endereço fonte
    mov EDI, 0x1E000 ; endereço destino
    mov ECX, 26      ; quantidade de bytes
    call memory_copy

    pop ECX
    pop EDI
    pop ESI
    pop EAX
    ret

cmdline: DB "initrd=init rdinit=/bin/sh", 0


read_all_sectors:
; params:
;   mov EBX, { DEST } - o endereço final pra onde copiar os setores
;   mov ESI, { LBA  } - índice do primeiro setor a ser lido
;   mov EDI, { N    } - a quantidade de setores pra ler (máximo de 2880 setores)

    push EBX
    push ESI
    push EDI
    push ECX

; ECX = a quantidade de setores que faltam ler no total
; EDI = a quantidade de setores pra ler nessa iteração atual
    mov ECX, EDI

.loop:
    cmp ECX, 0
    jz .end

    mov EDI, ECX
    cmp EDI, 40
    jle .body        ; jump if less equal (jump se menor ou igual)
    mov EDI, 40

.body:
    call read_sectors_diskbuff
    sub ECX, EDI     ; atualiza quantos setores ainda faltam
    add ESI, EDI     ; atualiza o índice do próximo setor pra ler
    mul EDI, 512     ; converte a quantidade de setores para quantidade de bytes
    add EBX, EDI     ; move DEST pra frente de acordo com quantos bytes foram lidos
    jmp .loop

.end:
    pop ECX
    pop EDI
    pop ESI
    pop EBX
    ret


read_sectors_diskbuff:
; params:
;   mov EBX, { DEST } - o endereço final pra onde copiar os setores
;   mov ESI, { LBA  } - índice do primeiro setor a ser lido
;   mov EDI, { N    } - a quantidade de setores pra ler (máximo de 40 setores)

    push EBX
    push ESI
    push EDI
    push ECX

    push EBX ; salvar DEST na stack

    ; TRANSFERE OS SETORES DO DISCO PARA O DISKBUFF
    mov EBX, 0x1000 ; DISKBUFF
    mov dword [callback], read_sectors
    call run_real_mode_callback

    ; COPIAR OS BYTES DO DISKBUFF PARA DEST
    mov ESI, 0x1000 ; DISKBUFF
    mov ECX, EDI    ; número de setores
    mul ECX, 512    ; converte para número de bytes
    pop EDI         ; pega DEST na stack e coloca em EDI
    call memory_copy

    pop ECX
    pop EDI
    pop ESI
    pop EBX

    ret

memory_copy:
; params:
;   mov ESI, { SOURCE } - endereço fonte
;   mov EDI, { DEST   } - endereço destino
;   mov ECX, { N      } - quantidade de bytes
    rep movsb 
    ret



run_real_mode_callback:
    mov dword [protected_ESP], ESP
    mov dword [protected_EBP], EBP
    jmp far 24:.set_real_mode

BITS 16 ; 16 BITS - protected mode
.set_real_mode:
    mov AX, 32
    mov DS, AX
    mov ES, AX
    mov FS, AX
    mov GS, AX
    mov SS, AX

    cli ; clear interrupt

    mov EAX, CR0
    and AL, 0b11111110
    mov CR0, EAX
    
    jmp far 0:.real_mode

BITS 16 ; 16 BITS - real mode
.real_mode:

    sti ; set interrupt

    mov SP, 0x7000
    mov BP, SP

    mov AX, 0
    mov DS, AX
    mov ES, AX
    mov FS, AX
    mov GS, AX
    mov SS, AX
    
    call dword [callback]

    ; ativando linha A20
    ; modo 1: FastA20, comunicação direta com hardware
    in AL, 0x92
    or AL, 2
    out 0x92, AL
    ; modo 2: interrupt da bios
    mov AH, 0x24
    mov AL, 0x01
    int 0x15

    cli ; clear interrupt


    lgdt [gdt_pointer]

    mov EAX, CR0
    or  AL, 0b00000001
    mov CR0, EAX

    jmp far 8:.restore_protected_mode

BITS 32
.restore_protected_mode:
    mov AX, 16
    mov DS, AX
    mov ES, AX
    mov FS, AX
    mov GS, AX
    mov SS, AX

    mov ESP, dword [protected_ESP]
    mov EBP, dword [protected_EBP]

    ret









TIMES 4606 - ($ - $$) DB 0x00
DB 0xBE
DB 0xEF
