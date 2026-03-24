;
; doorlock.asm
;
;k236074
.include "m32def.inc"

;------------------------------------------------------
; LCD DEFINITIONS
;------------------------------------------------------
.EQU LCD_DPRT = PORTA ;LCD DATA PORT
.EQU LCD_DDDR = DDRA  ;LCD DATA DDR
.EQU LCD_DPIN = PINA  ;LCD DATA PIN
.EQU LCD_CPRT = PORTB ;LCD COMMANDS PORT
.EQU LCD_CDDR = DDRB  ;LCD COMMANDS DDR
.EQU LCD_CPIN = PINB  ;LCD COMMANDS PIN
.EQU LCD_RS = 0       ;LCD RS
.EQU LCD_RW = 1       ;LCD RW
.EQU LCD_EN = 2       ;LCD EN

;------------------------------------------------------
; KEYPAD & SERVO DEFINITIONS
;------------------------------------------------------
.EQU KEY_PORT = PORTC
.EQU KEY_PIN = PINC
.EQU KEY_DDR = DDRC
.EQU SERVO_PIN = 5    ; Servo on Port D Pin 7

;------------------------------------------------------
; DATA MEMORY (RAM) VARIABLES
;------------------------------------------------------
.DSEG
INPUT_BUF: .BYTE 4    ; Reserve 4 bytes for user input

.CSEG
;------------------------------------------------------
; MAIN RESET VECTOR
;------------------------------------------------------
.ORG 0x0000
    RJMP MAIN

MAIN:
    ; --- 1. STACK SETUP ---
    LDI R21,HIGH(RAMEND)
    OUT SPH,R21
    LDI R21,LOW(RAMEND)
    OUT SPL,R21

    ; --- 2. SERVO INIT (PORT D) ---
    SBI DDRD, SERVO_PIN ; Set PD7 as Output
    CBI PORTD, SERVO_PIN

    ; --- 3. LCD INITIALIZATION ---
    LDI R21,0xFF
    OUT LCD_DDDR, R21 
    OUT LCD_CDDR, R21 
    CBI LCD_CPRT,LCD_EN 
    CALL DELAY_2ms    
    
    LDI R16,0x38      
    CALL CMNDWRT      
    CALL DELAY_2ms
    
    LDI R16,0x0E      ; display on, cursor on
    CALL CMNDWRT
    
    LDI R16,0x01      ; clear LCD
    CALL CMNDWRT
    CALL DELAY_2ms
    
    LDI R16,0x06      
    CALL CMNDWRT

    ; --- 4. KEYPAD INITIALIZATION ---
    LDI R20,0x0F      
    OUT KEY_DDR,R20

SYSTEM_RESET:
    ; Reset Input Index Counter (R22)
    LDI R22, 0 
    
    ; Display "Enter Code"
    LDI R16, 0x01       ; Clear Screen
    CALL CMNDWRT
    CALL DELAY_2ms
    
    LDI ZL, LOW(MSG_ENTER*2)
    LDI ZH, HIGH(MSG_ENTER*2)
    CALL SEND_STRING

    ; Move Cursor to 2nd Line
    LDI R16, 0xC0
    CALL CMNDWRT

;------------------------------------------------------
; MAIN LOOP: KEYPAD SCANNING
;------------------------------------------------------
GROUND_ALL_ROWS:
    LDI R20,0xF0
    OUT KEY_PORT,R20

WAIT_FOR_RELEASE:
    NOP
    IN R21,KEY_PIN
    ANDI R21,0xF0     
    CPI R21,0xF0      
    BRNE WAIT_FOR_RELEASE 

WAIT_FOR_KEY:
    NOP
    IN R21,KEY_PIN
    ANDI R21,0xF0
    CPI R21,0xF0
    BREQ WAIT_FOR_KEY
    
    CALL WAIT15MS     
    
    IN R21,KEY_PIN
    ANDI R21,0xF0
    CPI R21,0xF0
    BREQ WAIT_FOR_KEY

    ; --- SCAN ROW 0 (PC0) ---
    LDI R21,0b11111110
    OUT KEY_PORT,R21
    NOP
    IN R21,KEY_PIN
    ANDI R21,0xF0
    CPI R21,0xF0
    BRNE ROW_0_FOUND

    ; --- SCAN ROW 1 (PC1) ---
    LDI R21,0b11111101
    OUT KEY_PORT,R21
    NOP
    IN R21,KEY_PIN
    ANDI R21,0xF0
    CPI R21,0xF0
    BRNE ROW_1_FOUND

    ; --- SCAN ROW 2 (PC2) ---
    LDI R21,0b11111011
    OUT KEY_PORT,R21
    NOP
    IN R21,KEY_PIN
    ANDI R21,0xF0
    CPI R21,0xF0
    BRNE ROW_2_FOUND

    ; --- SCAN ROW 3 (PC3) ---
    LDI R21,0b11110111
    OUT KEY_PORT,R21
    NOP
    IN R21,KEY_PIN
    ANDI R21,0xF0
    CPI R21,0xF0
    BRNE ROW_3_FOUND

    RJMP GROUND_ALL_ROWS

; --- ROW HANDLERS ---
ROW_0_FOUND:
    LDI R30,LOW(KCODE0<<1)
    LDI R31,HIGH(KCODE0<<1)
    RJMP FIND_PREP
ROW_1_FOUND:
    LDI R30,LOW(KCODE1<<1)
    LDI R31,HIGH(KCODE1<<1)
    RJMP FIND_PREP
ROW_2_FOUND:
    LDI R30,LOW(KCODE2<<1)
    LDI R31,HIGH(KCODE2<<1)
    RJMP FIND_PREP
ROW_3_FOUND:
    LDI R30,LOW(KCODE3<<1)
    LDI R31,HIGH(KCODE3<<1)
    RJMP FIND_PREP

; --- FIND COLUMN LOOP ---
FIND_PREP:
    SWAP R21            
FIND:
    LSR R21             
    BRCC MATCH          
    LPM R20,Z+          
    RJMP FIND

;======================================================
; MODIFIED MATCH ROUTINE
;======================================================
MATCH:
    LPM R16,Z           ; Load the pressed Key
    CALL DATAWRT        ; Display on LCD
    
    ; --- Store Key in Buffer ---
    LDI XL, LOW(INPUT_BUF) ; Load buffer address to X pointer
    LDI XH, HIGH(INPUT_BUF)
    ADD XL, R22         ; Offset X by current index (R22)
    ADC XH, R1          ; Add carry (R1 is assumed 0)
    ST X, R16           ; Store key in SRAM
    
    INC R22             ; Increment Index
    CPI R22, 3          ; Check if 4 keys entered
    BREQ CHECK_PASS     ; If 4 keys, verify password
    
    RJMP GROUND_ALL_ROWS ; Else, get next key

;======================================================
; PASSWORD CHECK LOGIC
;======================================================
CHECK_PASS:
    CALL DELAY_2ms ; Small delay
    
    ; Reset X pointer to start of buffer
    LDI XL, LOW(INPUT_BUF)
    LDI XH, HIGH(INPUT_BUF)
    
    ; Check 1st Digit ? '3'
LD R16, X+
CPI R16, '3'
BRNE WRONG_CODE

; Check 2nd Digit ? '4'
LD R16, X+
CPI R16, '4'
BRNE WRONG_CODE

; Check 3rd Digit ? '7'
LD R16, X+
CPI R16, '7'
BRNE WRONG_CODE


   

    RJMP OPEN_DOOR

;======================================================
; ACTION ROUTINES
;======================================================
WRONG_CODE:
    LDI R16, 0x01       ; Clear LCD
    CALL CMNDWRT
    CALL DELAY_2ms
    
    LDI ZL, LOW(MSG_WRONG*2)
    LDI ZH, HIGH(MSG_WRONG*2)
    CALL SEND_STRING
    
    CALL DELAY_LONG     ; Wait so user can see message
    RJMP SYSTEM_RESET

OPEN_DOOR:
    LDI R16, 0x01       ; Clear LCD
    CALL CMNDWRT
    CALL DELAY_2ms
    
    LDI ZL, LOW(MSG_CORRECT*2)
    LDI ZH, HIGH(MSG_CORRECT*2)
    CALL SEND_STRING
    
    LDI R16, 0xC0       ; New Line
    CALL CMNDWRT
    
    LDI ZL, LOW(MSG_OPENING*2)
    LDI ZH, HIGH(MSG_OPENING*2)
    CALL SEND_STRING

    ; --- ROTATE SERVO (90 Degrees) ---
    ; Send 2ms Pulse (High) + 18ms (Low) approx 50 times
    LDI R23, 50         ; Repeat 50 times (~1 second)
SERVO_LOOP:
    SBI PORTD, SERVO_PIN
    CALL DELAY_2ms      ; High for 2ms (Rotate)
    CBI PORTD, SERVO_PIN
    CALL DELAY_18ms     ; Low for 18ms
    DEC R23
    BRNE SERVO_LOOP

    ; --- SHOW DOOR UNLOCKED ---
    LDI R16, 0x01       ; Clear LCD
    CALL CMNDWRT
    CALL DELAY_2ms
    
    LDI ZL, LOW(MSG_UNLOCKED*2)
    LDI ZH, HIGH(MSG_UNLOCKED*2)
    CALL SEND_STRING
    
    ; Stop here (or add delay and jump to reset to close door)
STOP: RJMP STOP

;------------------------------------------------------
; LCD SUBROUTINES
;------------------------------------------------------
CMNDWRT:
    OUT LCD_DPRT,R16
    CBI LCD_CPRT,LCD_RS
    CBI LCD_CPRT,LCD_RW
    SBI LCD_CPRT,LCD_EN
    CALL SDELAY
    CBI LCD_CPRT,LCD_EN
    CALL DELAY_100us
    RET

DATAWRT:
    OUT LCD_DPRT,R16
    SBI LCD_CPRT,LCD_RS
    CBI LCD_CPRT,LCD_RW
    SBI LCD_CPRT,LCD_EN
    CALL SDELAY
    CBI LCD_CPRT,LCD_EN
    CALL DELAY_100us
    RET

; New subroutine to print full strings
SEND_STRING:
    LPM R16, Z+
    CPI R16, 0
    BREQ STR_END
    CALL DATAWRT
    RJMP SEND_STRING
STR_END:
    RET

SDELAY: 
    NOP
    NOP
    RET

DELAY_100us:
    PUSH R17
    LDI R17,60
DR0: 
    CALL SDELAY
    DEC R17
    BRNE DR0
    POP R17
    RET

DELAY_2ms:
    PUSH R17
    LDI R17,20
LDR0: 
    CALL DELAY_100US
    DEC R17
    BRNE LDR0
    POP R17
    RET

DELAY_18ms: ; Used for Servo Low time
    PUSH R17
    LDI R17, 9
D18_LOOP:
    CALL DELAY_2ms
    DEC R17
    BRNE D18_LOOP
    POP R17
    RET

DELAY_LONG: ; Approx 2 seconds
    PUSH R18
    LDI R18, 100
DL_LOOP:
    CALL DELAY_18ms
    DEC R18
    BRNE DL_LOOP
    POP R18
    RET

WAIT15MS:
    PUSH R17
    LDI R17, 8
W_LOOP:
    CALL DELAY_2ms
    DEC R17
    BRNE W_LOOP
    POP R17
    RET

;------------------------------------------------------
; DATA TABLES
;------------------------------------------------------
.ORG 0x300
KCODE0: .DB '7','8','9','/'  
KCODE1: .DB '4','5','6','*'  
KCODE2: .DB '1','2','3','-'  
KCODE3: .DB 'C','0','=','+'  

; New Message Strings (Null terminated)
MSG_ENTER:    .DB "Enter Password:", 0
MSG_WRONG:    .DB "Password Incorrect", 0
MSG_CORRECT:  .DB "Code Correct", 0
MSG_OPENING:  .DB "Door Opening...", 0
MSG_UNLOCKED: .DB "Door Unlocked", 0