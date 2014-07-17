section .text
global _start
_start:
	call _main
	push eax
	mov eax, 0x1
	sub esp, 4
	int 0x80
_main:
	push dword 4
	pop  dword [_x]
	push dword [_x]
	pop eax
	push dword 7
	pop  dword [_y]
	push dword [_y]
	pop eax
	push dword [_x]
	push dword [_y]
	pop ecx
	pop eax
	add eax, ecx
	push eax
	pop eax
	ret
section .data
	_x dd 0
	_y dd 0
