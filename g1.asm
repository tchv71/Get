FT245R  equ     0D0h    ;  base address of FT245R FIFO
DATA    equ     0       ;  Data register
STAT    equ     1       ;  Status register
;
;  Define FIFO port
FIFO_DATA   equ   FT245R+DATA
FIFO_STATUS equ   FT245R+STAT

@SYSREG	MACRO	VAL
        IN	-1
        MVI	A,VAL
        OUT	-1
        ENDM

	@SYSREG 0C0h
	MVI     A,12
        out     FIFO_DATA
        out     FIFO_STATUS
	@SYSREG 80h

LOOP:
        IN      FIFO_STATUS
        PUSH    PSW
        CALL    0F815h
        POP     PSW
        ANI     1
        JNZ     LOOP
        IN      FIFO_DATA
        CALL    0F815h
        JMP     LOOP

        END
