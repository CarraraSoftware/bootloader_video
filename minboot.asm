; +----------------------------------------------------------------------------+
; |                                                                            |
; |  COMANDOS PARA COMPILAR E RODAR                                            |
; |                                                                            |
; +----------------------------------------------------------------------------+
; 
;--- COMPILAR BOOTLOADER ------------------------------------------------------+
;   nasm boot.asm -o boot                                   
;
;--- CRIAR DISQUETE FAKE ------------------------------------------------------
;   # Primeiro, criar um arquivo contendo exatamente 1.44MB de bytes nulos
;   dd if=/dev/zero of=floppy.img bs=1474560 count=1             conv=notrunc,nocreat status=progress
;
;   # Transfere os 26 setores do bootloader, incluindo o bootsector
;   dd if=boot      of=floppy.img bs=512     count=26            conv=notrunc,nocreat status=progress
;
;   # Transfere os 962 setores do init_ram_disk
;   dd if=init      of=floppy.img bs=512     count=962  seek=26  conv=notrunc,nocreat status=progress
;
;   # Por fim, transfere os 1441 setores do kernel do Linux
;   dd if=LINUX     of=floppy.img bs=512     count=1441 seek=988 conv=notrunc,nocreat status=progress
;
;--- RODAR EMULADOR (qemu) ----------------------------------------------------
;   qemu-system-i386 \
;   -cpu pentium \
;   -m 32 \
;   -drive file=floppy.img,if=floppy,media=disk,format=raw,index=0
;   -icount shift=3


BITS 16
ORG  0x7C00


; +----------------------------------------------------------------------------+
; |                                                                            |
; |  MACROS ÚTEIS                                                              |
; |                                                                            |
; +----------------------------------------------------------------------------+
%define HALT jmp $

%macro memcopy 3
; params:
; %1: { src }
; %2: { dst }
; %3: { num_bytes } 
    pusha
    mov ESI, %1
    mov EDI, %2
    mov ECX, %3
    rep movsb
    popa
%endmacro 

; buffer temporário pra a leitura de setores em modo real
; 32 setores = 16384 bytes, acaba no endereço 0x5000.
; @NOTE: pode acabar colidindo com a stack de modo real que começa no endereço 0x7000
;        e avança para endereços menores conforme uso. 
;        mas isso exigiria que 8192 bytes fossem colocados na stack, 
;        o que não é impossível normalmente, mas está longe de ser a carga utilizada pelo bootloader
%define DISK_BUFF             0x1000 
%define MAX_SECTORS_DISK_BUFF 32 

; stack modo real
%define STACK_RM  0x7000
; stack modo protegido
%define STACK_PM  0x90000


; +----------------------------------------------------------------------------+
; |                                                                            |
; |  MAPA DO DISCO                                                             |
; |                                                                            |
; +----------------------------------------------------------------------------+
; +==========+=============+===================================================+
; |LBA       | CONTENT     | SIZE                                              |
; +==========+=============+===+===============================================+
; | 0        | STAGE_1     |   }=> BOOTSECTOR (MBR)                            |
; +==========+=============+===+===============================================+
; | 1        | STAGE_2     |   |                                               |
; +==========+=============+   \                                               |
; | ...      | STAGE_2     |    }=> STAGE_2 == 25 SETORES                      |
; +==========+=============+   /                                               |
; | 26       | STAGE_2     |   |                                               |
; +==========+=============+===+===============================================+
; | 27       | INITRD      |   |                                               |
; +==========+=============+   \                                               |
; | ..       | INITRD      |    }=> INITRD  == 962 SETORES                     |
; +==========+=============+   /                                               |
; | 988      | INITRD      |   |                                               |
; +==========+=============+===+===============================================+
; | 989      | KERNEL      |   |                                               |
; +==========+=============+   \                                               |
; | ...      | KERNEL      |    }=> KERNEL  == 1441 SETORES                    |
; +==========+=============+   /                                               |
; | 2429     | KERNEL      |   |                                               |
; +==========+=============+===+===============================================+
; | 2430     | --          |   |                                               |
; +==========+=============+   \                                               |
; | ...      | --          |    }=> 450 SETORES SOBRANDO                       |
; +==========+=============+   /                                               |
; | 2879     | --          |   |                                               |
; +==========+=============+===+===============================================+


%define STAGE2_START_LBA    1 
%define STAGE2_SIZE_SECTORS 25
%define STAGE2_SIZE_BYTES   (STAGE2_SIZE_SECTORS * 512)
%define BOOTLOADER_MAX_SIZE_BYTES ((STAGE2_SIZE_SECTORS + 1) * 512)

%define INITRD_START_LBA    (STAGE2_START_LBA + STAGE2_SIZE_SECTORS)
%define INITRD_SIZE_SECTORS 962
%define INITRD_SIZE_BYTES   (INITRD_SIZE_SECTORS * 512)
%define INITRD_MEMADDR      0x200000

%define KERNEL_START_LBA          (INITRD_START_LBA + INITRD_SIZE_SECTORS)
%define KERNEL_TOTAL_SIZE_SECTORS 1441

%define KERNEL_SETUP_START_LBA    KERNEL_START_LBA
%define KERNEL_SETUP_SIZE_SECTORS 32
%define KERNEL_SETUP_SIZE_BYTES   (KERNEL_SETUP_SIZE_SECTORS * 512)
%define KERNEL_SETUP_MEMADDR      0x10000

%define KERNEL_MAIN_START_LBA     (KERNEL_SETUP_START_LBA + KERNEL_SETUP_SIZE_SECTORS)
%define KERNEL_MAIN_SIZE_SECTORS  (KERNEL_TOTAL_SIZE_SECTORS - KERNEL_SETUP_SIZE_SECTORS)
%define KERNEL_MAIN_SIZE_BYTES    (KERNEL_MAIN_SIZE_SECTORS * 512)
%define KERNEL_MAIN_MEMADDR       0x100000



; +----------------------------------------------------------------------------+
; |                                                                            |
; |  SETUP DO BOOT DO LINUX                                                    |
; |                                                                            |
; +----------------------------------------------------------------------------+
; (Fonte: https://www.kernel.org/doc/Documentation/x86/boot.rst)

%define HEAP_END     0xE000
%define HEAP_END_PTR (HEAP_END - 0x200)

%define COMMAND_LINE_PTR (KERNEL_SETUP_MEMADDR + HEAP_END);

; linux kernel loadflags masks
%define LOADED_HIGH   0b00000001  ; indica que foi carregado no endereço 0x100000
%define KASLR_FLAG    0b00000010  ; sei lá, não ligo
%define QUIET_FLAG    0b00100000  ; sei lá, não ligo
%define KEEP_SEGMENTS 0b01000000  ; sei lá, não ligo
%define CAN_USE_HEAP  0b10000000  ; indica que o heap foi configurado corretamente e tá pra jogo
%define KERNEL_LOAD_FLAGS (0 | LOADED_HIGH | CAN_USE_HEAP)

; +----------------------------------------------------------------------------+
; |                                                                            |
; |  BOOTLOADER - STAGE 1                                                      |
; |                                                                            |
; +----------------------------------------------------------------------------+

; os primeiros bytes precisam ser uma instrução válida, por isso
; é bem comum que os primeiros bytes sejam um jmp para a rotina main (ou às vezes _start, ou coisa parecida)
jmp main
; o jmp vai pular todas as variaveis que a gente colocar antes da rotina main


; argumentos de linha de comando que vão ser passados para o kernel
CommandLine:      db "initrd=/init rdinit=/bin/sh", 0 
CommandLineSize:  db $ - CommandLine 

; geometria e características do disquete
BytesPerSector:   dw 512
TotalSectors:     dw 80 * 2 * 18
SectorsPerTrack:  dw 18
NumberHeads:      dw 2
DriveNumber: 	  db 0


main:
    cli
    xor AX, AX
    mov SS, AX
    mov DS, AX
    mov ES, AX
    mov SP, STACK_RM
    mov BP, SP
    sti

    mov byte [DriveNumber], DL
    call disk_reset

    mov AL, 'C'
    call print_chr
    mov AL, 'B'
    call print_chr
    mov AL, 0x0A
    call print_chr
    mov AL, 0x0D
    call print_chr

    mov CX, STAGE2_START_LBA
    mov DI, STAGE2_SIZE_SECTORS
    mov BX, 0x7E00 ; = 0x7C00 + 512
    call read_sectors

    jmp 0x7E00

    HALT


lba_to_chs:
; params: 
; mov AX, { LBA_Sector }
;
; return:
; mov CX[0-5],  { sector         }   Sector   = (LBA % SectorsPerTrack) + 1        
; mov CX[6-15], { cylinder       }   Cylinder = (LBA / SectorsPerTrack) / NumHeads   
; mov DH,       { head           }   Head     = (LBA / SectorsPerTrack) % NumHeads 
    push AX

    xor DX, DX
    div word [SectorsPerTrack] ; div divide o valor armazenado em AX pelo argumento
                               ; e coloca o resulado da divisão em AX e o resto em DX

    ; o resto + 1 é o valor do Setor
    inc DX      ; DX = (LBA % SectorsPerTrack) + 1 = Sector 
    mov CX, DX  ; CX = DX = Sector

    xor DX, DX
    div word [NumberHeads] 
    ; depois da primeira div, o AX contém o resultado inteiro da divisão,
    ; aí a gente divide AX novamente, de forma a colocar o resto em DX.
    ; esse resto é o head, mas ele vai estar em DL, ao invés de DH.
    ; basta fazer o swap do dois:
    xchg DL, DH
    xor  DL, DL ; zerar o DL só por desencargo

    ; novamente, AX tem o resultado inteiro da divisão após a instrução div.
    ; embora AX tenha 2 bytes de tamanho, a gente só precisa de 1 byte.
    ; então basta pegar o byte baixo de AX (AL) e colocar em CH.
    mov CH, AL

    ; no caso de um hard disk, tem dois bits adicionais que vão em CL
    ; não é necessário no boot pelo disquete, mas deixo aqui por completude.
    shl AH, 6  
    or  CL, AH

    pop AX
    
    ret


; @NOTE: esse é um jeito extremamente lento de ler os setores do disquete, pois essa rotina lê um setor por vez.
;        isso significa que, por exemplo, ao ler um arquivo de 1000 setores de tamanho, a rotina fará 1000 chamadas a interrupts da BIOS.
;        (obs: o kernel do linux usado aqui tem 1441 setores de tamanho).
;        esse é um modo bem burro porém conveniente de lidar com o fato de que o interrupt de leitura de setor vai falhar caso
;        ele tente ler um conjunto de setores que cruze uma fronteira de cilindro.
;        (por exemplo: ler os 2 últimos setores do cilindro atual,
;                      o primeiro setor de fato estaria no cilindro atual, mas o segundo setor estaria no próximo cilindro.
;                      nesse caso, ocorreria uma fault da cpu e nenhum setor seria lido.
;        )
;        já que essa rotina faz uma chamada de interrupt pra cada setor lido, o cenário de cruzar a fronteira é impossível.
read_sectors: 
; params:
; mov CX, { LBA_Sector     } // @NOTE: Linear Block Address (LBA) começa em 0
; mov DI, { number_sectors }
; mov BX, { buffer         }
    pusha

    cmp DI, 0                                   ; se num_sectors (salvo em DI) for zero, não tem nada pra fazer e podemos pular pro fim
    jz .end

    mov AH, byte 0x02                           ; subfunction = 2
    mov SI, DI                                  ; inicia um contador em SI com o valor de setores que se deseja ler

    push CX

.read_single_sector:                            ; @TODO: mover essa parte para uma rotina separada?
    pop CX

    cmp SI, 0                                   ; se o contador (salvo em SI) for zero, acabamos de ler todos os setores que se queria
    jz .end                                     ; e portanto, podemos pular pro fim

    mov AX, CX
    push CX                                     ; salvar CX na stack antes de chamar lba_to_chs pq 
    call lba_to_chs                             ; essa rotina espera o valor do LBA in AX e retorna 
                                                ; os valores de CHS em CX e DH conforme esperado por int 0x13, AH=0x02

    mov DI, 3                                   ; 3 tentativas
.retry:
    stc                                         ; aciona a flag de carry em caso da BIOS apenas zerar a flag no caso de sucesso

    mov AL, byte 0x01                           ; ler um único setor por vez pra evitar de cruzar a fronteira de cilindro 
    mov AH, byte 0x02                           ; subfunction 2 = ler setores
    mov DL, byte [DriveNumber]
    int 0x13

    jnc .next                                   ; se não teve errors, a flag de carry é zero e a gente avança pra próxima iteração
    call disk_reset                             ; se teve errors, a gente não fez o jmp, então reseta o disco e tenta de novo 
    dec DI          
    test DI, DI
    jnz .retry
.error:                                         ; se chegarmos nesse ponto é pq já 3 tentativas e falhou todas as vezes
    mov AL, 51                                  ; falha de leitura de setores = código de erro 3 (ascii = 51)
    call print_chr
    HALT

.next:
    pop  CX
    inc  CX                                     ; incrementa o índice do LBA
    push CX

    add BX, 512                                 ; move o pointer do buffer 512 bytes (tamanho de 1 setor) pra frente
    dec SI                                      ; diminui o iterator
    jmp .read_single_sector                     ; leitura de mais 1 setor

.end:
    popa
    ret

disk_reset:
    pusha
    mov AH, byte 0x00
    mov DL, byte [DriveNumber]
    int 0x13
    popa
    ret

print_chr:
; params:
; mov AL, { char }
    pusha
    test AL, AL
    jz .end
    mov AH, byte 0x0E 
    mov BH, byte 0x00
    mov BL, byte 0x00
    int 0x10
.end:
    popa
    ret

; padding pra bater 510 bytes
TIMES 510 - ($ - $$) db 0

; os bytes 511° e 512º são bytes mágicos pra indicar pra BIOS que se trata de um bootsector
db 0x55 
db 0xAA

; +----------------------------------------------------------------------------+
; |                                                                            |
; |  BOOTLOADER - STAGE 2                                                      |
; |                                                                            |
; +----------------------------------------------------------------------------+
BITS 16
stage_2:
    ; habilita a porta a20, alguns pcs/BIOSes oferecem suporte a um meio, outros somente a outros, 
    ; então a gente tenta com 2 modos diferentes
    ; modo 1: por meio de interrupt da bios
    mov AH, 0x24
    mov AL, 0x01
    int 0x15     
    ; modo 2: instrução direta pro dispositivo
    in AL, 0x92
    or AL, 2
    out 0x92, AL 


    ; ACIONANDO MODO PROTEGIDO PELA PRIMEIRA VEZ
    cli           ; desativa interrupts
    lgdt [gdtr]   ; carrega o endereço da gdt
    mov EAX, CR0  ;
    or AL, 1      ; ativa o último bit do CR0,
    mov CR0, EAX  ; que indica o modo protegido

    ; far um far jump para sincronizar o estado interno da cpu (e.g. o registrador CS)
    ; e fazer valer de fato o modo protegido 32 bits
    jmp far 0x8:pmode



BITS 32
pmode:
    ; índice da GDT correspondente a código de 32 bits em todos os registradores de segmento
    mov AX, 0x10
    mov DS, AX
    mov SS, AX
    mov ES, AX
    ; stack de mode protegido
    mov ESP, STACK_PM
    mov EBP, ESP

    ; call playground

    ; BOOTANDO O KERNEL 
    call load_init         ; carrega o initramdisk que vai ser usado como sistema de arquivos do kernel
    call load_kernel_setup ; os primeiros 32 setores do kernel são um setup em modo real do kernel principal
    call setup_kernel      ; que precisa que alguns valores importantes sejam configurados 
    call load_kernel_main  ; e finalmente carrega o kernel principal no endereço 0x100000

    ; executa o kernel modo real
    mov dword [real_mode_cb], kernel_start_RM
    call shift_real_mode
    HALT ; unreachable: o controle de execução deveria ter passado completamente pro kernel nesse ponto

playground:
    ; rotina reservada pra entulhar de código avulso quando se precisa testar as paradas tudo
    mov dword [real_mode_cb], playground_real
    call shift_real_mode
    ret 



load_sectors_into_disk_buff:
; params:
; mov ECX,  { lba }
; mov EDI,  { num_sectors } // @NOTE: max 32 sectors (idealmente)
    pusha
    mov EBX, dword DISK_BUFF
    mov dword [real_mode_cb], read_sectors
    call shift_real_mode
    popa
    ret

load_init:
    pusha
    mov ECX, INITRD_START_LBA
    mov EBX, INITRD_SIZE_SECTORS
    mov EAX, INITRD_MEMADDR
    call load_file
    popa
    ret


setup_kernel:
    push EAX
    mov EAX, KERNEL_SETUP_MEMADDR
    mov [EAX + 0x210], byte  0xFF
    mov [EAX + 0x211], byte  KERNEL_LOAD_FLAGS
    mov [EAX + 0x218], dword INITRD_MEMADDR
    mov [EAX + 0x21C], dword INITRD_SIZE_BYTES
    mov [EAX + 0x224], word  HEAP_END_PTR
    mov [EAX + 0x228], dword COMMAND_LINE_PTR
    memcopy CommandLine, COMMAND_LINE_PTR, CommandLineSize
    pop EAX
    ret

load_kernel_setup:
    pusha
    mov ECX, KERNEL_SETUP_START_LBA
    mov EBX, KERNEL_SETUP_SIZE_SECTORS
    mov EAX, KERNEL_SETUP_MEMADDR
    call load_file
    popa
    ret

load_kernel_main:
    pusha
    mov ECX, KERNEL_MAIN_START_LBA
    mov EBX, KERNEL_MAIN_SIZE_SECTORS
    mov EAX, KERNEL_MAIN_MEMADDR
    call load_file
    popa
    ret


load_file:
; mov EAX, { buffer   } ; final buffer
; mov EBX, { num_secs } ; total amount of sectors to read
; mov ECX, { lba }      ; initial lba to read from
    pusha
.loop:
    cmp EBX, 0
    jz .end

    mov EDI, EBX
    cmp EDI, MAX_SECTORS_DISK_BUFF
    jle .less_equal
    mov EDI, MAX_SECTORS_DISK_BUFF
.less_equal:
    ; copiar os setores do buffer temporário (DISK_BUFF) para o pointer do buffer (EAX)
    call load_sectors_into_disk_buff
    mov EDX, EDI 
    mul EDX, 512 ; converte a quantidade de setores lidos (EDI) para quantidade de bytes 
    memcopy DISK_BUFF, EAX, EDX

    sub EBX, EDI ; decrementa a quantidade de setores que faltam ler
    add ECX, EDI ; incrementa o índice do próximo setor a ser lido

    mul EDI, 512 ; tamanho em bytes de quantos setores foram lidos
    add EAX, EDI ; move o pointer do buffer pra frente 

    jmp .loop ; repete o loop até esgotar os setores do arquivo

.end:
    popa
    ret

protected_mode_entry: ; Entry Point for when shifting from real mode
    xor EAX, EAX
    mov AX, word 0x10
    mov DS, AX
    mov ES, AX
    mov FS, AX
    mov GS, AX
    mov SS, AX

    mov ESP, dword [protected_mode_sp] 
    mov EBP, dword [protected_mode_bp] 

    jmp dword [protected_mode_ret] ; goto [return]
    HALT ; unreachable

shift_real_mode: ; Shift[Prot Mode -> Real Mode]
    ; salva os valores da stack de modo protegido 
    ; (espera que tenha sido inicializada corretamente a primeira vez que entramos no modo protegido)
    mov dword [protected_mode_sp],  ESP
    mov dword [protected_mode_bp],  EBP 

    ; após a execução do callback em modo real, 
    ; é necessário um endereço pro qual retornar no modo protegido.
    ; geralmente isso seria feito com uma instrução 'ret' que pega o endereço na stack.
    ; no entanto como a gente faz a transição entre modo real e modo protegido, 
    ; o endereço da própria stack assume diferentes valores (0x7000 pra real, 0x90000 pra protegido).
    ; então o endereço de retorno é salvo em uma variável reservada só pra isso:
    mov dword [protected_mode_ret], the_return
    jmp far 0x18:real_mode
the_return:
    ret

;------------------------------------------------------------------------------;
; 32 BITS - Data                                                               ;
;------------------------------------------------------------------------------;
protected_mode_ret: dd 0  ; endereço de retorno em modo protegido para quando estamos voltando do modo real
protected_mode_bp:  dd 0  ; save do base pointer da stack em modo protegido
protected_mode_sp:  dd 0  ; save do stack pointer  em modo protegido
real_mode_cb:       dd 0  ; callback pra executar em modo real

BITS 16
; -----------------------------------------------------------------------------;
; 16 BITS - CODE - Protected Mode                                              ;
; -----------------------------------------------------------------------------;
align 16 
; @NOTE: isso daqui é UNreal mode? 
real_mode:
    ; índice da GDT correspondente a código de 16 bits em todos os registradores de segmento
    mov AX, 0x20
    mov DS, AX
    mov ES, AX
    mov FS, AX
    mov GS, AX
    mov SS, AX

    ; desativa interrupts
    cli

    ; desativa o modo protegido:
    mov EAX, CR0                       ; cr0
    and EAX, 0xFFFFFFFE                ; |--- 32 bits ---|
    mov CR0, EAX                       ; [ # # # # ... 0 ]
                                       ;               ^-modo real
    ; faz o far jump pro código de 16 bits em modo real
    jmp far 0x0:real_mode_entry
BITS 16
align 16
real_mode_entry:  ; primeira rotina executada em modo real 16 bits quando fazemos o shift a partir do modo protegido
                  ; essa rotina deve chamada a partir de código 16 bits em modo protegido. 
    lidt [idtr]
    sti

    xor AX, AX
    mov DS, AX
    mov ES, AX
    mov FS, AX
    mov GS, AX
    mov SS, AX
    mov SP, STACK_RM
    mov BP, SP

    call dword [real_mode_cb] ; executa o callback

    jmp shift_protected_mode  ; volta pro modo protegido
    HALT ; unreachable


BITS 16
; -----------------------------------------------------------------------------;
; 16 BITS - CODE - Real Mode                                                   ; 
; -----------------------------------------------------------------------------;
align 16
shift_protected_mode:  ; Shift[Real Mode -> Prot Mode]
    ; habilita porta a20 de novo só por desencargo de consciência
    mov AX, 0x2401
    int 0x15
    
    in AL, 0x92
    or AL, 2
    out 0x92, AL

    cli

    lgdt [gdtr]

    xor EAX, EAX
    mov CR3, EAX

    xor EAX, EAX
    mov EAX, CR0      ; cr0                          
    or  EAX, 1        ; |<-- 32 bits -->|           
    mov CR0, EAX      ; [ # # # # ... 1 ]           
                      ;               ^- modo protegido
                           
    jmp 0x8:protected_mode_entry
    HALT


align 16
kernel_start_RM:
    mov BX, 0x1000 ; segmento onde o setup do kernel foi carregado = 0x1000 (full address = 0x10000)
    mov CX, 0xE000 ; offset do heap (full address = 0x10000 + 0xE000)

    ; nas docs em boot.rst falam pra desligar o motor do leitor do disquete, então tá aqui:
    mov DX, 0x03F2
    mov AL, 0x00
    out DX, AL

    ; também fala pra desativar interrupts
    cli

    mov SS, BX
    xor ESP, ESP
    mov SP, CX

    mov DS, BX
    mov ES, BX
    mov FS, BX
    mov GS, BX

    jmp far 0x1020:0


playground_real:
    ; rotina reservada pra entulhar de código avulso quando se precisa testar as paradas tudo
    ret


;------------------------------------------------------------------------------;
; 16 BITS - Data                                                               ;
;------------------------------------------------------------------------------;
BITS 16

align 8
gdtr:
gdt_size: dw gdtend - gdt - 1
gdt_ptr:  dd gdt

align 8
gdt:
db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; 0x00: null segment
db 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x9A, 0xCF, 0x00 ; 0x08: 32bit - code segment (ring 0)
db 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x92, 0xCF, 0x00 ; 0x10: 32bit - data segment (ring 0)
db 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x9A, 0x00, 0x00 ; 0x18: 16bit - code segment (ring 0)
db 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x92, 0x00, 0x00 ; 0x20: 16bit - data segment (ring 0)
gdtend:


align 16 
idtr:
idtsize:   dw 0x3FF
idtoffset: dd 0x000

TIMES BOOTLOADER_MAX_SIZE_BYTES - ($ - $$) db 0
