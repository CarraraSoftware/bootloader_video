all: compile run

compile:
	# Compilar o Bootloader, incluindo o Bootsector.
	nasm boot.asm -o boot                                   
	nasm hello.asm -o hello

image:
	# Primeiro, criar um arquivo contendo exatamente 1.44MB de bytes nulos
	dd if=/dev/zero of=diskette bs=1474560 count=1 conv=notrunc
	
	# Transfere o Bootsector
	dd if=boot of=diskette bs=512 count=1 conv=notrunc
	
	# Transfere a segunda parte do Bootloader
	dd if=hello  of=diskette bs=512 count=9 conv=notrunc seek=1

	# Transfere o kernel
	dd if=LINUX  of=diskette bs=512 count=1441 conv=notrunc seek=10

	# Transfere o RAMDISK
	dd if=init   of=diskette bs=512 count=962  conv=notrunc seek=1451


floppy:
	# Transfere os 1.44MB da imagem gerado para o disquete real
	sudo dd if=diskette of=/dev/sdc bs=1474560 count=1 conv=notrunc


bochs: compile image 
	# Rodar Emulador (Bochs)
	bochs -f .bochsrc -q -debugger                          

qemu: compile image  
	# Rodar Emulador (Qemu)
	qemu-system-i386 \
		-cpu pentium \
		-m 32 \
		-drive file=diskette,if=floppy,media=disk,format=raw,index=0
	# -icount shift=3
	# -enable-kvm
	# -no-reboot
	# -d int
	# -s -S

