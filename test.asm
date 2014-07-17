global _start

section .text
_start:
	
	; pop  dword [_x]
	; push dword [_x]
	
	mov dword eax, 55
	mov dword [_x], eax
	
	push dword [num]
	push dword 12
	
	call _main
	add eax, 3
	push eax
	
	mov eax, 0x1
	sub esp, 4
	int 0x80

_main:
	push dword 3
	pop  eax
	ret

section .data

	num dd 11, 22, 33, 44, 55
	_x  dd 88
