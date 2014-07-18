crud-c-compiler
===============

kind of a c compiler in ruby.

Consumes kinda C code, and emits x86 NASM assembly.

Only global variables allowed at this point, and they are assumed to have 4 bytes.

The only operation really supported is '+' (though always assumes int).
Function calls are kinda supported but not really tested.


Really only been tested on a mac, because its my dev machine.
