; GET.COM - get file from PC and save to CP/M disk
; Configurable ports version - get ports config from BIOS

RXRDY equ                 1            ; MASK FOR RX BUFFER FULL
TXRDY equ                 2            ; MASK FOR TX BUFFER EMPTY


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

GET_ORG_START:

	.PHASE ORG_START
GET_START:
	LXI	D,VRAM_ADR
	CALL	BIOS_CONFIG
	LXI	H,50h
	SHLD	PPI2_ADR

	CALL	GTFNAM
	CALL	GTOPT
	MVI	A,9
	CALL	StartCommand
	CALL	READRK_NO_START
	MVI	A,3
	;@out	CLIENT_STATUS
	PUSH	H
	LHLD	PPI2_ADR
	INX	H
	call	_out
	POP	H
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

SEND_MODE	equ 10000000b ; Режим передачи (1 0 0 A СH 0 B CL)
RECV_MODE	equ 10010000b ; Режим приема (1 0 0 A СH 0 B CL)

ERR_START	equ 040h
ERR_WAIT	equ 041h
ERR_OK_NEXT	equ 042h
ERR_OK		equ 043h
ERR_OK_READ	equ 044h
ERR_OK_ENTRY	equ 045h
ERR_OK_WRITE	equ 046h
ERR_OK_ADDR	equ 047h
ERR_OK_BLOCK	equ 04Fh 
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
	CALL          SwitchRecv

	; Beginning of any command (play a sequence in address bus)
	LHLD	PPI2_ADR
	INX	H
	xra	a
	;@out	USER_PORT+1
	call	_out
	MVI	A, 44h
	;@out	USER_PORT+1
	call	_out
	MVI	A, 40h
	;@out	USER_PORT+1
	call	_out
	xra	a
	;@out	USER_PORT+1
	call	_out

	; If there is synchronization, then the controller will respond with ERR_START
	CALL	Recv
	CPI	ERR_START
	JZ	StartCommand2

	; Pause. And also we skip 256 bytes (in total it will be
	; 64 KB data skipped, maximum packet size)
	PUSH	B
	MVI	C, 0
StartCommand3:
	CALL	Recv
	DCR	C
	JNZ	StartCommand3
	POP	B
	
	; Попытки
	DCR	C
	JNZ	StartCommand1    

	; Код ошибки
	MVI	A, ERR_START
StartCommandErr2:
	POP	B
	POP	H
	POP	B 
	;POP	B
	RET

;----------------------------------------------------------------------------
; Synchronization with the controller is done. The controller should respond with ERR_OK_NEXT

StartCommand2:
	; Ответ            	
	CALL	WaitForReady
	CPI	ERR_OK_NEXT
	JNZ	StartCommandErr2

	; Переключаемся в режим передачи
	CALL	SwitchSend

	POP	PSW
	POP	H
	POP	B

	; Передаем код команды
	JMP	Send2

;----------------------------------------------------------------------------
; Switch to send mode

SwitchSend:
	PUSH	H
	CALL	Recv
	MVI	A, SEND_MODE
SwS01:
	LHLD	PPI2_ADR
	INX	H
	INX	H
	INX	H
	;@out	USER_PORT+3
	;RET
	call	_out
	POP	H
	RET

;----------------------------------------------------------------------------
; Successful end of the command
; and an additional cycle so that the microcontroller releases the bus
;Ret0:
;	XRA	A

;----------------------------------------------------------------------------
; Command ending with an error in A
; and an additional cycle so that the microcontroller releases the bus
EndCommand:
	PUSH	PSW
	CALL	Recv
	POP	PSW
	RET

;----------------------------------------------------------------------------
; Switch to receive mode

SwitchRecv:
	MVI	A, RECV_MODE
	PUSH	H
	;@OUT	USER_PORT+3
	;RET
	JMP	SwS01

;----------------------------------------------------------------------------
;Switch to receive mode and wait for microcontroller be ready

SwitchRecvAndWait:
	CALL SwitchRecv

;----------------------------------------------------------------------------
WaitForReady:
	CALL	Recv
	CPI	ERR_WAIT
	JZ	WaitForReady
	RET


;----------------------------------------------------------------------------
; Receive a byte into А

Recv:
	PUSH	H
	LHLD	PPI2_ADR
	JMP	Recv01
;----------------------------------------------------------------------------
; Send a byte from A.

Send2:
	PUSH	H
	LHLD	PPI2_ADR
	;@out	USER_PORT
	call	_out
Recv01:
	INX	H
	MVI	A, 20h
	;@out	USER_PORT+1
	call	_out
	XRA	A
	;@out	USER_PORT+1
	call	_out
	DCX	H
	;@in	USER_PORT
	call	_in
	POP	H
	RET
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
	PUSH	H
	PUSH	D
	LHLD	PPI2_ADR
	INX	H
	INX	H
	INX	H
	mvi	A,99H ; A - input, B - output, Clow, Chigh - input
	;@out	SERIAL_CONTROL
	call	_out
	DCX	H
	DCX	H
	MVI	A,1
	;@out	CLIENT_STATUS - PPI_2+1
	call	_out
	INX	H
	LXI	D,8000h                          ;long timeout
	
gc10:	DCX	D
	MOV	A,D
	ORA	E
	JZ	gc90                                ;exit if timeout
	;@in	SERIAL_STATUS                 ;read device status
	call	_in
	ANI	RXRDY
	JNZ	gc10                                ;not ready yet.
;
;  Data received:  return CY=0. data in A
	DCX	H
	DCX	H
	call	_in
	INX	H
	STC
	CMC                                   ;cy=0
	;@in	SERIAL_DATA                   ;read data - PPI2+0
	push	psw
	xra	a
	;@out	CLIENT_STATUS
	call	_out
	INX	H
gc11:	;@in	SERIAL_STATUS                 ; wait for server
	call	_in
	ANI	RXRDY
	JZ	gc11
	pop	psw
	POP	D
	POP	H
	RET
;
;  Timeout:  return CY=1
gc90:
	MVI	A,0
	DCX	H
	;@out	CLIENT_STATUS
	call	_out
	STC	;cy=1
	POP	D
	POP	H
	RET
;=======================================================

; GET FILE NAME
; DEFAULT - INPUT.TMP
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

NOTICE:	DB	'Get file from PC   (C) TCHV   2023',10,13
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
		DW 0,0,0	; Reserved for future use

;
GET_END:
	END
