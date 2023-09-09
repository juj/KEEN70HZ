global Int21HandlerInit
global Int21HandlerRun
global Int21HandlerDone

extern GetIntVec
extern SetIntVec
extern RedirectFile

True equ 1
False equ 0

segment CODE

Int21Handler:
; Check if requesting 'Open file or device' service
    CMP AH,0x3D
    JNE PassThrough

; Check if we're supposed to be redirecting files yet
    CMP BYTE [CS:RedirectEnabled],True
    JNE PassThrough

; Call DOS with DS:DX adjusted to point to redirected file, return results
Redirect:
    ; Save registers
    PUSH DS
    PUSH DX
    PUSH ES
    PUSH DI
    PUSH SI
    PUSH CX
    PUSH BX
    PUSH AX

    ; Obtain replacement file name pointed to by DX:AX
    PUSH DS
    PUSH DX
    MOV AX,DATA
    MOV DS,AX
    CALL RedirectFile

    ; Copy replacement file name pointer to DS:DX
    MOV DS,DX
    MOV DX,AX

    ; Restore other registers
    POP AX
    POP BX
    POP CX
    POP SI
    POP DI
    POP ES

    ; Call DOS to open alternate file instead
    PUSHF
    CLI
    CALL FAR [CS:PrevInt21Handler]
    STI

    ; Restore DS:DX so it points to original file name
    POP DX
    POP DS

    ; Return to game, but preserve flags since DOS indicates file I/O errors
    ; by setting the carry flag.
    RETF 2

; Pass request through to DOS
PassThrough:
    JMP FAR [CS:PrevInt21Handler]

; Install the file redirector handler
Int21HandlerInit:
    ; Save current interrupt 21H vector state
    MOV AX,0x21
    PUSH AX
    MOV AX,SEG PrevInt21Handler
    PUSH AX
    MOV AX,PrevInt21Handler
    PUSH AX
    CALL FAR GetIntVec

    ; Install the file redirector handler by hooking interrupt 21H
    MOV AX,0x21
    PUSH AX
    MOV AX,SEG Int21Handler
    PUSH AX
    MOV AX,Int21Handler
    PUSH AX
    CALL FAR SetIntVec

    RET

; Activates the file redirection
Int21HandlerRun:
    ; Set the file redirection flag, so DOS file open requests are filtered
    MOV BYTE [CS:RedirectEnabled],True
    RET

; Uninstalls the file redirection handler
Int21HandlerDone:
    ; Restore the previous interrupt 21H vector state
    MOV AX,0x21
    PUSH AX
    PUSH WORD [CS:PrevInt21Handler+2]
    PUSH WORD [CS:PrevInt21Handler]
    CALL FAR SetIntVec
    RET

; Storage for the previous interrupt 21H vector state
PrevInt21Handler: dd 0

; Indicates if DOS file open requests should be filtered
RedirectEnabled: db False

segment DATA
