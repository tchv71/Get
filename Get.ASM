; GET.COM - get file from PC and save to CP/M disk
; Configurable ports version - get ports config from BIOS
;USE_DMA        EQU     0
USE_PORT        EQU     1
CPM             EQU     1
?Ctrl	equ	40h
?Shift	equ	20h

IFDEF  USE_PORT

FT245R  equ     0D0h    ;  base address of FT245R FIFO
DATA    equ     0       ;  Data register
STAT    equ     1       ;  Status register
;
;  Define FIFO port
FIFO_DATA   equ   FT245R+DATA
FIFO_STATUS equ   FT245R+STAT

RXEMPTY equ     1       ; MASK FOR RX BUFFER EMPTY
TXFULL  equ     2       ; MASK FOR TX BUFFER FULL

ELSE
IFNDEF USE_DMA
;
;  Equates for I/O mapped 8250 or 16450 serial port
VV55  equ    50H ; 0C400h   ;base of 16450 UART
USER_PORT equ VV55
DATA    equ     0       ;  Data register
STAT    equ     2       ;  Status register
;
;  Define monitor serial port
SERIAL_STATUS   equ   VV55+STAT
CLIENT_STATUS   equ   VV55+1
SERIAL_DATA   equ   VV55+DATA
SERIAL_CONTROL equ  VV55+3

RXRDY equ                 1            ; MASK FOR RX BUFFER FULL
TXRDY equ                 2            ; MASK FOR TX BUFFER EMPTY


ENDIF
ENDIF
ORG_START          EQU        09000H

	LXI	H, GET_ORG_START
	LXI	D, GET_START
	LXI	B, GET_END-GET_START
CP001:
	MOV	A,M
	STAX	D
	INX	H
	INX	D
	DCX	B
	MOV	A,B
	ORA	C
	JNZ	CP001
	JMP	GET_START

@SYSREG	MACRO	VAL
        IN	-1
        MVI	A,VAL
        OUT	-1
        ENDM
; IN and OUT MACRO comands
@in	MACRO	addr
IF ((addr) LT 256)
        in	addr
ELSE
        lda	addr
ENDIF
        ENDM

@out	MACRO	addr
IF ((addr) LT 256)
        out	addr
ELSE
        sta	addr
ENDIF
        ENDM

DMA EQU 30H
SD  EQU 60H

GET_ORG_START:

	.PHASE ORG_START
GET_START:
IFDEF   CPM
	LXI	D,VRAM_ADR
	CALL	BIOS_CONFIG
ENDIF
	@SYSREG 0C0h
IFDEF  USE_PORT
	MVI     A,12
        out     FT245R
        out     FT245R + 1
ENDIF
	@SYSREG 80h

	CALL	GTFNAM
	CALL	GTOPT
	;MVI	A,9
	;CALL	StartCommand
	CALL	READRK_NO_START
IFNDEF  CPM
	MVI	A,3
	;@out	CLIENT_STATUS
	PUSH	H
	LHLD	PPI3_ADR
	INX	H
	call	_out
	POP	H
ENDIF
	LXI	B,5000
L001:	DCX	B
	MOV	A,B
	ORA	C
	JNZ	L001
	PUSH	H
	XCHG
	CALL	DSKO
	LXI	H,0
	SHLD	80H
	POP	H
	LDA	MODE
	DCR	A
	JNZ	0
	PCHL

BIOS_CONFIG:
	LHLD	1
	LXI	B,30H
	DAD	B
	MOV	A,M
	CPI	JMP
	RNZ
	INX	H
	PUSH	D
	MOV	E,M
	INX	H
	MOV	D,M
	XCHG
	POP	D
	PCHL

_in::	INR	H
	DCR	H
	JZ	_in_port
	MOV	A,M
	RET
_in_port:
	MOV	A,L
	STA	$+4
	IN	0
	RET

_out::	INR	H
	DCR	H
	jz	_out_port
	MOV	M,A
	RET
_out_port:
	PUSH	PSW
	MOV	A,L
	STA	$+5
	POP	PSW
	OUT	0
	RET



READRK_START:
	MVI	C,1
	JMP	READRK
READRK_NO_START:
	MVI	C,0
READRK:
	CALL	GETCHAR
	JC	READRK
	MOV	H,A
	CALL	GETCHAR
	JC	ERRRK
	MOV	L,A
	CALL	GETCHAR
	JC	ERRRK
	MOV	D,A
	CALL	GETCHAR
	JC	ERRRK
	MOV	E,A
	INX	D
	PUSH	D
	MOV	A,E
	SUB	L
	MOV	E,A
	MOV	A,D
	SBB	H
	MOV	D,A
	PUSH	H
LOOP:	CALL	GETCHAR
	JC	ERRRK
	MOV	M,A
	INX	H
	DCX	D
	MOV	A,D
	ORA	E
	JNZ	LOOP
	POP	H
	mvi	e,6
LOOP2:  CALL	GETCHAR
	JC	ERRRK
	DCR	E
	JNZ	LOOP2
	MOV	A,C
	ORA	A
	POP	D
	RZ
	PCHL

ERRRK:
	LXI	D,ERR_RECEIVE
	MVI	C,9
	CALL	5
	RST	0

ERR_RECEIVE:
	DB	"Error on receive$"

IF 0
;SEND_MODE	equ 10000000b ; Режим передачи (1 0 0 A СH 0 B CL)
;RECV_MODE	equ 10010000b ; Режим приема (1 0 0 A СH 0 B CL)

STA_START	EQU 040h ; МК переключен в режим приема команд
STA_WAIT	EQU 041h ; МК выполняет команду
STA_OK_DISK	EQU 042h ; Накопитель исправен, микроконтроллер готов к приему команды

;----------------------------------------------------------------------------
; A start of any command. 
; A - command code

StartCommand:
; The first step is synchronization with the controller
; 256 attempts are performed, each skipping 256+ bytes
; That is, this is the maximum amount of data that the controller can transmit.
	PUSH	B
	PUSH	H
	PUSH	PSW
	MVI	C, 0

StartCommand1:
	; Receive mode (release the bus - port A) and initialize HL
	; CALL	SwitchRecv

	; Если есть синхронизация, то контроллер ответит STA_START
	CALL	GETCHAR
	CPI	STA_START
	JNZ	StartCommandErr2
;----------------------------------------------------------------------------
; Синхронизация с контроллером есть. Контроллер должен ответить STA_OK_DISK

     ; Ответ         	
	CALL	WaitForReady
	CPI	STA_OK_DISK
	JNZ	StartCommandErr2

	; Переключаемся в режим передачи
	;CALL       SwitchSend

	POP	PSW
	POP	H
	POP	B

	; Передаем код команды
	JMP	PUTCHAR
StartCommandErr2:
	POP	B ; Прошлое значение PSW
	POP	H ; Прошлое значение H
	POP	B ; Прошлое значение B     
	POP	B ; Выходим через функцию.
	RET


;----------------------------------------------------------------------------
;Switch to receive mode and wait for microcontroller be ready

SwitchRecvAndWait:
	;CALL SwitchRecv

;----------------------------------------------------------------------------
WaitForReady:
	CALL	GETCHAR
	CPI	STA_WAIT
	JZ	WaitForReady
	RET
ENDIF

;
;===========================================================================
;  Get a character to A
;
;  Return A=char, CY=0 if data received
;            CY=1 if timeout (0.5 seconds)
;
;  Uses 4 bytes of stack including return address
;
GETCHAR:
IFDEF  USE_PORT
	PUSH	D
	LXI	D,8000h       ;long timeout
gc10:	DCX	D
	MOV	A,D
	ORA	E
	JZ	gc90          ;exit if timeout
	@in	FIFO_STATUS   ;read device status
	ANI	RXEMPTY
	JNZ	gc10          ;not ready yet.
        ;PUSH    H
        ;POP     H
;
;  Data received:  return CY=0. data in A
	XRA	A             ;cy=0
	@in	FIFO_DATA     ;read data
        ;PUSH    PSW
        ;CALL    0F815h
        ;POP     PSW
	POP	D
	RET
;
;  Timeout:  return CY=1
gc90:	STC                   ;cy=1
	POP	D
	RET
ELSE
IFNDEF USE_DMA
	mvi	A,99H ; A - input, B - output, Clow, Chigh - input
	@out	SERIAL_CONTROL
	MVI	A,1
	@out	CLIENT_STATUS
	PUSH	D
	LXI	D,8000h                 ;long timeout
gc10:	DCX	D
	MOV	A,D
	ORA	E
	JZ	gc90                    ;exit if timeout
	@in	SERIAL_STATUS           ;read device status
	ANI	RXRDY
	JNZ	gc10                    ;not ready yet.
;
;  Data received:  return CY=0. data in A
	XRA	A                       ;cy=0
	@in	SERIAL_DATA             ;read data
	push	psw
	xra	a
	@out	CLIENT_STATUS
gc11:	@in	SERIAL_STATUS           ; wait for server
	ANI	RXRDY
	JZ	gc11
	pop	psw
	POP	D
	RET
;
;  Timeout:  return CY=1
gc90:	STC	                        ;cy=1
	MVI	A,0
	@out	CLIENT_STATUS
	POP	D
	RET

ELSE
	PUSH	D
	PUSH	B
	LXI	D,OUTCHAR
	LXI	B,4001H
	CALL	SET_DMAW
	LDAX	D
	ORA	A ; Clear C-flag
	POP	B
	POP	D
	RET
ENDIF
ENDIF
;
;===========================================================================
;  Output character in A
;
;  Uses 4 bytes of stack including return address
;
PUTCHAR:
IFDEF  USE_PORT
	PUSH	PSW           ;save byte to output
pc10:	@in	FIFO_STATUS   ;read device status
	ANI	TXFULL        ;tx full ?
	JNZ	pc10
	POP	PSW
	@out	FIFO_DATA     ;transmit char
	RET
ELSE
IFNDEF USE_DMA
	PUSH	PSW                     ;save byte to output
	mvi	A,89H ; A - output, B - output, Clow, Chigh - input
	@out	SERIAL_CONTROL
	mvi	a,2
	@out	CLIENT_STATUS; // Ready to send
pc10:	;CALL	CheckBrk
	;JZ	0
	@in	SERIAL_STATUS           ;read device status
	ANI	TXRDY                   ;rx ready ?
	JNZ	pc10

	POP	PSW
	@out	SERIAL_DATA            ;transmit char - error in wiring! must write to _STATUS
	xra	a
	@out	CLIENT_STATUS

pc11::	;CALL	CheckBrk
	;JZ	0
	@in	SERIAL_STATUS           ; wait for server confirms reading a byte
	ANI	TXRDY
	JZ	pc11
ELSE
	PUSH	D
	PUSH	B
	LXI	D,OUTCHAR
	STAX	D
	MVI	A,1
	@out	SD
	LXI	B,8001H
	CALL	SET_DMAW
	ORA	A
	POP	B
	POP	D
ENDIF
ENDIF
	RET
OUTCHAR:	DS 1

CheckBrk:
	PUSH	H
	LHLD	PPI_ADR
	INX	H
	INX	H
	CALL	_in
	POP	H
	ANI	?Ctrl+?Shift
	RET
IFDEF USE_DMA
; Set DMA with waiting of the end of transfer
SET_DMAW:
	CALL	SET_DMA
WAIT_DMA:
	@in	DMA+8
	ANI	1;2
	JZ	WAIT_DMA
	RET

; Program DMA controller

; DE - start address
; BC - packet length with MSB:
;   10 - read cycle (transfer from memory to device)
;   01 - write cycle (thansfer from device to memory)
SET_DMA:
	@IN	DMA+0Fh
	INR	A
	JZ	DVT37
	MVI	A,0F6h
	@out	DMA+8
	MOV	A,E
	@out	DMA
	MOV	A,D
	@out	DMA
	DCX	B
	MOV	A,C
	@out	DMA+1
	MOV	A,B
	@out	DMA+1
	INX	B
	MVI	A,0F7h
	@out	DMA+8
	RET
DVT37:
	MOV	A,B
	PUSH	PSW
	ANI	3Fh
	MOV	B,A
	@OUT	DMA+0Ch
	MVI	A,4 ; Stop channel 0
	@OUT	DMA+0Ah

	MOV	A,E
	@out	DMA+0
	MOV	A,D
	@OUT	DMA+0
	DCX	B
	MOV	A,C
	@OUT	DMA+1
	MOV	A,B
	@OUT	DMA+1
	INX	B

	POP	PSW
	ANI	0C0H
	RRC
	RRC
	RRC
	RRC
	;ORI	1
	@OUT	DMA+0Bh
	MVI	A,20h
	@OUT	DMA+8
	MVI	A,0 ; Start channel 1
	@OUT	DMA+0Ah
	RET
ENDIF
;
GTFNAM:
	LXI	H,CON-1
	MOV	A,M
	CPI	20
	JC	MARAZM
	LXI	H,FCB+1
	MVI	C,11
GTN0:	MVI	M,20H
	INX	H
	DCR	C
	JNZ	GTN0
	MVI	C,17H
GTN1:	MVI	M,0
	INX	H
	DCR	C
	JNZ	GTN1
	MVI	A,1
	STA	FCB+15
	STA	FCB+36
	LXI	D,FCB+1
	LXI	H,CON-1
	MVI	B,0BH
GTN4:
	INX	H
	MOV	A,M
	CPI	20H
	JZ	GTN4
	CPI	','
	JZ	DEFAULT

GTN2:	MOV	A,M
	CPI	20H
	RC
	CPI	','
	RC
	CPI	'/'
	RZ
	CPI	'.'
	JZ	GTN3
	STAX	D
	INX	H
	INX	D
	DCR	B
	JNZ	GTN2
	RET

GTN3:	LXI	D,FCB+9
	MVI	B,3
	INX	H
	JMP	GTN2

MARAZM:	LXI	D,NOTICE
	CALL	PRINT
	JMP	0

DEFAULT:
	LXI	D,FCB+1
	MVI	B,11
DEF0:	MOV	A,M
	STAX	D
	INX	H
	INX	D
	DCR	B
	JNZ	DEF0
	LXI	H,CON
	RET

; GET OPTIONS
GTOPT:
	PUSH	H
	PUSH	D
	PUSH	B
	XRA	A
	STA	MODE
	STA	?FOUND
	CALL	SEARCH
	DB	'/X',0
	JNZ	ENDO0
	MVI	A,1
	STA	MODE
	MVI	A,0FFH
	STA	?FOUND
ENDOPT:
	LDA	?FOUND
	ORA	A
	JNZ	ENDO0
	CALL	SEARCH
	DB	'/',0
	JZ	MARAZM
ENDO0:	POP	B
	POP	D
	POP	H
	RET

SEARCH:	POP	H
	LXI	D,CON
SR0:	PUSH	D
	CALL	SRH0
	POP	D
	JZ	FOUND
	INX	D
	MOV	H,B
	MOV	L,C
	LDAX	D
	CPI	20H
	JC	NOT_F
	JMP	SR0

SRH0:
	MOV	B,H
	MOV	C,L
SRH1:	MOV	A,M
	ORA	A
	RZ
	LDAX	D
	CMP	M
	RNZ
	INX	H
	INX	D
	JMP	SRH1

NOT_F:	INX	H
	MOV	A,M
	CPI	20H
	JNC	NOT_F
FOUND:	INX	H
	PCHL

; WRITE FILE TO DISK
; HL	START
; DE	END
DSKO:
	PUSH	H
	LXI	H,-128
	DAD	D
	XCHG
	PUSH	D
	LXI	D,FCB
	MVI	C,13H	; DELETE FILE
	CALL	5
	LXI	D,FCB
	MVI	C,16H	; CREATE FILE
	CALL	5
	POP	D
	POP	H
	INR	A
	JNZ	DISK0

	LXI	D,_ERR0
	CALL	PRINT
	JMP	0000H

DISK0:	PUSH	H
	LXI	H,128
	DAD	D
	XCHG
	POP	H

	PUSH	H
	PUSH	D
	MVI	C,1AH	; SET TRANSFER
	CALL	5	; ADRESS

	LXI	D,FCB
	MVI	C,15H
	CALL	5
	POP	D
	POP	H
	INR	A
	JNZ	DISK1
	LXI	D,_ERR2
	CALL	PRINT
	JMP	0

DISK1:	MOV	A,D
	CMP	H
	JC	DISK0
	JNZ	DISK2
	MOV	A,L
	CMP	E
	JNC	DISK0
DISK2:
	LXI	D,FCB
	MVI	C,10H
	CALL	5
	INR	A
	RNZ

	LXI	D,_ERR1
	CALL	PRINT
	JMP	0000H

PRINT:
	PUSH	H
	PUSH	D
	PUSH	B
	MVI	C,9
	CALL	5
	POP	B
	POP	D
	POP	H
	RET

; FILE CONTROL BLOCK
FCB:
	DB	0
	DB	'INPUT   TMP',0,0,0,0
	DW	0,0,0,0,0,0,0,0
	DB	0,0,0,0,0,0,0

	CON	EQU	82H

_ERR0:	DB	0DH,0AH,'CREATING FILE ERROR$'
_ERR1:	DB	0DH,0AH,'CLOSING FILE ERROR$'
_ERR2:	DB	0DH,0AH,'WRITING FILE ERROR$'

NOTICE:	DB	'Get file from PC   (C) TCHV   2023-25',10,13
	DB	'    Enter:',10,13
	DB	'    A>GET <FILENAME>{/OPTIONS}',10,13
	DB	'         OPTIONS:',10,13
	DB	'       /X - execute',10,13
	DB	'$'

MODE:	DS	1
?FOUND:	DS	1

VRAM_ADR::	DW 0B770h	; VRAM buffer visible start address - 0B7C2h
PPI_ADR::	DW 0C200h 	; VV55 keyboard Controller - 0C200h
PPI2_ADR::	DW 0C400h	; VV55 additional PPI  - 0C400h
DISP_ADR::	DW 0C000h	; VG75 Display Controller - 0C000h
DMA_ADR::	DW 0E000h	; VT57 DMA Controller - 0E000h
PALM_CTR_ADR::	DW 0CE00h	; Palmira Control Byte
PPI3_ADR::	DW 0CA00h	; VV55 additional PPI3  - 0CA00h
		DW 0,0	; Reserved for future use

;
GET_END:
	END
