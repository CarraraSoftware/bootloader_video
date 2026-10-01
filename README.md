## Emuladores utilizados durante o desenvolvimento
- [QEMU](https://www.qemu.org/docs/master/about/index.html)
- [Bochs](https://bochs.sourceforge.io/)


## Arquivos nesse repositório:

minboot.asm:    primeira versão que eu fiz do bootloader apenas em assembly.
                Essa versão foi utilizada como referência durante as gravações do vídeo,
                tem comentários mais explicativos e foi organizado com um pouco de cuidado.

boot.asm,
hello.asm:      bootloader desenvolvido no vídeo.

Makefile:       comandos de build para compilar o bootloader desenvolvido no vídeo
                (os mesmos comandos estão presentes no arquivo boot.asm).

kernel.config:  arquivo de configuração de compilação do kernel do linux.

init.config:    arquivo de configuração de compilação do busybox.

.bochsrc:       arquivo de configuração para execução do emulador bochs.

REFS.md:        lista com todas as referências utilizadas durante o desenvolvimento
                do bootloader.


## Rodando o bootloader

Antes de tentar rodar o bootloader, tenha certeza de que você tem instalado:
- [NASM](https://www.nasm.us/)
- [QEMU](https://www.qemu.org/docs/master/about/index.html) ou [Bochs](https://bochs.sourceforge.io/)

Para bootar o kernel você precisará dos arquivos binários:
- LINUX
- init

Você pode encontrar os arquivos pré-compilados que eu utilizei no vídeo,
na página de [releases](https://github.com/CarraraSoftware/bootloader_video/releases/tag/TOSHIB%C3%83O) desse repositório.

Tendo os binários em mãos basta executar:
```bash
# caso você queira executar o bochs:
make bochs

# caso você queira executar o qemu:
make qemu
```


## Comandos para compilar seus próprios binários:

Caso você queira compilar os seus próprios binários, você precisará do código
contido nos repositórios:
- [linux](https://github.com/torvalds/linux),
- [busybox](https://github.com/mirror/busybox)

Ambos repositórios podem ser compilados o comando `make`.

Eu recomendo que você utilize os arquivos kernel.config e busybox.config
como um ponto de partida para a sua configuração de compilação.


### compilando o kernel com as exatas mesma configuração que eu (carrara)
```bash
# <caminho para bootloader_video> é o caminho para o diretório no qual você 
# clonou esse repositório que você está no momento

# <caminho para o kernel> é o caminho para o diretório no qual você 
# clonou o repositório do kernel do linux


cd <caminho para bootloader_video>/
git clone https://github.com/torvalds/linux.git <caminho para o kernel>/
cp kernel.config <caminho para o kernel>/.config
make
cp <caminho para o kernel>/arch/x86/boot/bzImage LINUX
```

### compilando o busybox com as exatas mesma configuração que eu (carrara)

```bash
# <caminho para bootloader_video> é o caminho para o diretório no qual você 
# clonou esse repositório que você está no momento

# <caminho para o busybox> é o caminho para o diretório no qual você 
# clonou o repositório do busybox

cd <caminho para bootloader_video>/
git clone https://github.com/mirror/busybox.git <caminho para o busybox>/
cp busybox.config <caminho para o busybox>/.config
make
cp <caminho para o busybox>/busybox busybox
```
NOTA: Esses comandos apenas gerarão o binário executável do busybox, você ainda
precisará criar e compactar um diretório para ser utilizado como RAMDISK,
como mostrado no vídeo.


