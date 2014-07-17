; hello.asm - a "hello, world" program using NASM

section .text

global _start

_start:
	
	push dword mylen
	push dword mymsg
	push dword 1
	
	mov eax, 0x4
	sub esp, 4
	int 0x80
	
	add esp, 16
	
	push dword 0
	
	mov eax, 0x1
	sub esp, 4
	int 0x80

section .data

	mymsg db "hello, world", 0xa
	mylen equ $-mymsg

