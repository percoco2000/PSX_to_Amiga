; -------------------------------------------------------------------
;   File    : appe_v3d_mod.asm
;   Version : 3.0d
; -------------------------------------------------------------------
; APPE -> Amiga Playstation Pad Emulator
; PSX to Amiga pad adapter interface built around a 16F84/10P micro
;
; CREATED BY ACKMAN    
; Solved a bug in the pad comunication routine...
;  
;   Adapted for GPASM and english translated by Percoco2000
;   Percoco2000@gmail.com  
; 
; Original Project : https://aminet.net/package/docs/hard/appe_v32 
; -------------------------------------------------------------------


; Disable 302 Assembler Message
ERRORLEVEL -302


processor p16f84a
    #include "./p16f84.inc"

    __CONFIG _CP_OFF & _WDT_OFF & _PWRTE_ON & _XT_OSC

; Autofire speed
; ------------------------------------------------------------------------------------
; Changing this value change the autofire speed.
; Lower the value, fastest the speed.
    #DEFINE     AUTOSPEED   0x04    
; ----------------  Variable Definition -----------------------------------------------
    cblock 0x0c

        TX_D            ;BYTE to be trasmitted at the PSX pad
        OUT             ;BYTE to jostick bits in AMIGA mode
        FLAG            ;Internal Flag Register
        CONT1           ;Generic counters
        CONT2
        CONT3
        BYTE2           ;Second useful byte received from PSX Pad
        BYTE1           ;First useful byte received from PSX Pad
        BYTE            ;receiving BYTE from PSX Pad
        SAVE_S          ;Store the STATUS register before IRQ routine
        SAVE_W          ;Store the W register before IRQ routine
        FIREVEL         ;Store the Autofire Speed. Lower Value -> Faster speed
        CD32TX          ;Data to be trasmitted to AMIGA in CD32 Mode
        CD32TXB         ;Store the value to be trasmitted in CD32 Mode
    endc

; ---------------- BITS Definition ------------------------------------------------------
; PORTA
DAT         EQU 0X00    ;PIN 17     Psx Pad data Input
COM         EQU 0X01    ;PIN 18     Psx Pad data Output
CLK         EQU 0X02    ;PIN 1      Psx Pad Sync Output
ATT         EQU 0X03    ;PIN 2      Psx Pad Enable (Recall attention)
ACK         EQU 0X04    ;PIN 3      Psx Pad ID Input

; PORTB                   MODO      NORMAL      CD32
CD32EN      EQU 0X00    ;PIN 6      NO USE      ENABLE CD32
UP          EQU 0X01    ;PIN 7      UP          --
LEFT        EQU 0X02    ;PIN 8      LEFT        --  
DOWN        EQU 0X03    ;PIN 9      DOWN        --
RIGHT       EQU 0X04    ;PIN 10     RIGHT       --
FIRE1       EQU 0X05    ;PIN 11     FIRE 1      DAT OUT
FIRE0       EQU 0X06    ;PIN 12     FIRE 1      CLOCK IN
NCONN       EQU 0X07    ;PIN 13     --          --  
                            
; -------------------- Main Program --------------------------------------------
    org 0x00
        NOP
        CALL    Ports
        CALL    Default
        GOTO    Main
        
        
; --------------------- IRQ Routine -------------------------------------------
; The IRQ routine is used to send the gamepad buttons to Amiga in CD32 Mode
; Everytime the amiga pull down RB0 an Interrupt is generated.
; RB0 is connected to amiga PIN X. This pin in CD32 protocol, is used to
; start reading data from the pad.
; While RB0 is held to 0, the routine, at every clock transition from 0 to 1
; sends a bit of the CD32TX byte to amiga
    org 0x04
    
CD32out:                        
        MOVWF   SAVE_W          ; Save the value of W
    banksel TRISB           
        BSF     PORTB,FIRE0     ; Set FIRE0 as INPUT (CD32 CLOCK) 
    banksel PORTB

WCLKE:  
        BTFSC   PORTB,CD32EN    ; IS CD32EN still 0 ?
        GOTO    ExitCD32mode    ; No, Exit from IRQ, all the data has been transmitted
        BTFSS   PORTB,FIRE0     ; Yes. Is CD32 CLOCK = 1 ?  
        GOTO    WCLKE           ; No, wait from transition from 0 to 1
; CD32 Clock transition from 0 to 1
; Send LSB of CD32TX, and rotate
  
        BTFSS   CD32TX,0        ; CD32TX's LSB = 1 ? 
        BCF     PORTB,FIRE1     ; No, set FIRE1 (CD32 DAT) to 0
        BTFSC   CD32TX,0        ; Yes, So check if is a 0 
        BSF     PORTB,FIRE1     ; No, set FIRE1 to 1
        RRF     CD32TX,F        ; Shift CD32TX to right 

WCLKU:  
        BTFSC   PORTB,CD32EN    ; Is CD32EN still 0 ?
        GOTO    ExitCD32mode    ; No, exit from IRQ, all data has been transmitted
        BTFSC   PORTB,FIRE0     ; Yes. Is CD32 CLOCK = 0 ? 
        GOTO    WCLKU           ; No, Wait from transition from 1 to 0
        GOTO    WCLKE           ; Repeat the routine (Send Next BIT)

ExitCD32mode:
; All BITs has been transmitted

    banksel     TRISB
        BCF     PORTB,FIRE0     ; Set FIRE0 as Output
    banksel     PORTB
        ;MOVF   OUT,W           ;COLOCA LOS DATOS EN LA SALIDA COMO ANTES DE LA IRQ
        ;MOVWF  PORTB
        MOVF    CD32TXB,W       ; Reinit CD32TX in case new IRQ occour
        MOVWF   CD32TX
        MOVF    SAVE_W,W        ; Restore W
        BCF     INTCON,INTF     ; Clear RB0 IRQ flag
        RETFIE                  ; Exit from IRQ

; Main loop
; ----------------------------------------------------------------------
; |--|
; |  v
; |  Read the pad status 
; |  v
; |  Set the joystick bits 
; |  v
; |  Prepare the data for CD32 out
; |  v
; |__| 

Main:
        CALL    Pad
        CALL    Bigdelay
        CALL    Bigdelay
        CALL    Joyout
        CALL    Bigdelay
        CALL    Prep32
        CALL    Bigdelay
        GOTO    Main

Pad:    
    ; Routine to read data from PSX PAD
    ; TX_D  --> the byte to be transmitted
    ; BYTE  --> The data reiceved
    ; BITE1 --> first data byte
    ; BITE2 --> 2nd   data byte
        BCF     PORTA,ATT   ;Set PAD Attention
        CALL    Bigdelay    ;Wait
        MOVLW   0X01        ;Send 01 to the PAD to reset
        MOVWF   TX_D
        CALL    Tx_Rx
        CALL    Bigdelay    
        MOVLW   0X42        ; Send COMand 0x42 to request pad data
        MOVWF   TX_D
        CALL    Tx_Rx       ; Simultaneously receive the pad type
                ; 0X41= Digital Pad
                ; 0X23=Negcom
                ; 0X73=Analog RED Led
                ; 0X53=Analog GREEN Led
                ; 0X12=PSX Mouse
                ;**** Not really compatible with mouse****
        CALL    Bigdelay    ; Wait
        CALL    Tx_Rx       ; Send empty COMand (TX_D=FF)
                ;Simultaneously receive 0x52 , DATA ready (not really checked)
        CALL    Bigdelay    ; Wait
        CALL    Tx_Rx       ; Receive first byte
        MOVF    BYTE,W      ; 
        MOVWF   BYTE1       ; And store in BYTE1
        CALL    Bigdelay    ; Wait
        CALL    Tx_Rx       ; Receive second byte
        MOVF    BYTE,W
        MOVWF   BYTE2       ; And store in BYTE2
        CALL    Bigdelay    ; Wait
        BSF     PORTA,ATT   ; Unset PAD attention
        RETURN  




; Protocol timing to send and receive a byte 
; COM is the transmitter pin
; DAT is the receiver pin
; Bits changes on the falling edge of CLOCK
;
;        BIT0  BIT1  BIT2  BIT3  BIT4  BIT5  BIT6  BIT7
;clock---___---___---___---___---___---___---___---___------------
;DAT ---000000111111222222333333444444555555666666777777---------
;           *     *     *     *     *     *     *     *
;COM ---000000111111222222333333444444555555666666777777---------
;ack  ------------------------------------------------------___---
;        |-4µS-|

Tx_Rx:
    ; Routine to simultaney transmit and receive a byte to the pad
    ; The byte to be trasmitted in stored in TX_D, and is sent
    ; starting from the LSB from right to left
    ; The byte to be received is stored in BYTE, starting from
    ; the LSB from left to right
    
        MOVLW   0X08        ; Set the number of bits to be transmitted in CONT3
        MOVWF   CONT3
Read_Loop:
        BCF     PORTA,CLK   ; Set to 0 the CLOCK line
        ; Check for TX_D MSB. If 0 set PORTA COM=0, if 1 set PORTA COM=1
        BTFSC   TX_D,0      
        BSF     PORTA,COM
        BTFSS   TX_D,0
        BCF     PORTA,COM
        RRF     TX_D,F      ; Right SHIFT TX_D
        RRF     BYTE,F      ; Righ SHIFT BYTE
        NOP                 ; Wait for at least 1.5 uS
        NOP
        NOP
        NOP
        NOP
        NOP 
        BCF     BYTE,7      ; Clear BYTE MSB
        BSF     PORTA,CLK   ; Set to 1 the CLOCK line
        BTFSC   PORTA,DAT   ; Read the received bit on DAT, is 0 ? Yes, leave BYTE's MSB to 0
        BSF     BYTE,7      ; No, set to 1 BYTE's MSB
        ;BSF PORTA,CLK   ;PONE A UNO LA LINEA DE RELOG
        NOP                 ; Wait for at least 1.5 uS
        NOP
        NOP
        NOP
        NOP
        NOP
        DECFSZ  CONT3,F     ; Is this the last bit?
        GOTO    Read_Loop   ; No, read the following
        MOVLW   0XFF        ; Yes, put FF in the byte to be trasmitted
        MOVWF   TX_D
        BSF     PORTA,COM  ; Set COM bit to 1
        RETURN              ; Exit





; SoubRoutine : Joyout
; ---------------------------------------------------------------------
; Convert the data received from the psx PAD to joystick buttons
; The data from the PSX correnspond to this table 
;  
;       BIT7    BIT6    BIT5    BIT4    BIT3    BIT2    BIT1    BIT0
;BYTE1  Left    Down    Right   Up      Start    -       -      Select
;BITE2  (|_|)   (X)     (O)     (/\)    R1       L1      R2     L2
; When a button is pressed the relative bit is set to 0
; On an amiga, instead , a button press mean the relative bit set to 0
; 

Joyout:
        MOVLW   0XFF        ; Clear OUT ( Remenber, when a button is pressed is grounded to 0 )
        MOVWF   OUT
        BTFSS   BYTE1,4     ; UP pressed ? (if BIT=0 )
        BCF     OUT,UP      ; Yes, put corrensponding BIT to 0
        BTFSS   BYTE1,5     ; Right pressed ?
        BCF     OUT,RIGHT   ; Yes
        BTFSS   BYTE1,6     ; Down  pressed ?
        BCF     OUT,DOWN    ; Yes
        BTFSS   BYTE1,7     ; Left  pressed ?
        BCF     OUT,LEFT    ; Yes
        BTFSS   BYTE2,4     ; (/\)  pressed ?
        BCF     OUT,UP      ; Yes --> Button (/\) mapped to UP
        BTFSS   BYTE2,1     ; R2    pressed ?
        CALL    Autofire    ; Yes --> Autofire
        BTFSS   BYTE2,5     ; (O)   pressed ?
        BCF     OUT,FIRE1   ; Fire1 put to 0 
        BTFSS   BYTE2,6     ; (X)   pressed ?
        BCF     OUT,FIRE0   ; Fire0 put to 0
        MOVF    OUT,W       ; Copy the OUT byte on PORTB
        MOVWF   PORTB
        RETURN  

; SoubRoutine : Autofire
; ---------------------------------------------------
; The Fire0 output is lowered every 'FIREVEL'nt time 
; Joyout is executed. Chamging, at compile time, the value
; of FIREVEL the autofire speed can be modified        
Autofire:
        DECFSZ  FIREVEL,F   ; Is FIREVEL = 0 ?
        RETURN              ; No
        BCF     BYTE2,6     ; Yes, Fire0 put to 0
        MOVLW   AUTOSPEED   ; Reload FIREVEL  
        MOVWF   FIREVEL
        RETURN  

; SoubRoutine : Prep32
; ------------------------------------------------------
; Setup the bits to be trasimtted in CD32 mode
; The data are stored in CD32TX according to this table
;  
;       BIT7    BIT6    BIT5    BIT4    BIT3    BIT2    BIT1    BIT0
;CD32TX  N/A     N/A    PLAY    <<       >>     Green   Orange  Red
;EQU                    START   L1       R1     (|_|)   (/\)    (X)

; Don't need to trasmit the Blue button becasue is connected to fire1
; and correnspon to PSX (O)
Prep32:
        
        BSF     CD32TX,6
        BSF     CD32TX,7
        ; Check for pressed buttons
        BTFSS   BYTE1,3     ; PSX START pressed ? (BIT=0 ?)
        BCF     CD32TX,5    ; Yes, set PLAY/PAUSE to 0
        BTFSS   BYTE2,2     ; PSX L1 pressed ? 
        BCF     CD32TX,4    ; Yes, set << to 0
        BTFSS   BYTE2,3     ; PSX R1 pressed ?
        BCF     CD32TX,3    ; Yes, set >> to 0
        BTFSS   BYTE2,4     ; PSX (/\) pressed ?
        BCF     CD32TX,1    ; Yes, set ORANGE to 0 
        BTFSS   BYTE2,7     ; PSX (|_|) pressed ? 
        BCF     CD32TX,2    ; Yes, set GREEN to 0
        BTFSS   BYTE2,6     ; PSX (X) pressed ?
        BCF     CD32TX,0    ; Yes, set RED to 0
        
        ; Check for unpressed button
        BTFSC   BYTE1,3     ; PSX START unpressed ? (BIT=1 ? )
        BSF     CD32TX,5    ; Yes, set PLAY/PAUSe to 1
        BTFSC   BYTE2,2     ; PSX L1 unpressed ?
        BSF     CD32TX,4    ; Yes, set << to 1
        BTFSC   BYTE2,3     ; PSX R1 unpressed ?
        BSF     CD32TX,3    ; Yes, set >> to 1
        BTFSC   BYTE2,4     ; PSX (/\) unpressed ?
        BSF     CD32TX,1    ; Yes, set ORANGE to 1 
        BTFSC   BYTE2,7     ; PSX (|_|) unpressed ? 
        BSF     CD32TX,2    ; Yes, set GREEN to 1
        BTFSC   BYTE2,6     ; PSX (X) unpressed ?
        BSF     CD32TX,0    ; Yes, set RED to 1
        MOVF    CD32TX,W
        MOVWF   CD32TXB     ; Keep a copy of CD32TX to CD32TXB 
        RETURN

Ports:
    ;Init of I/O pins

    banksel     TRISA
        BSF     TRISA,DAT
        BCF     TRISA,COM
        BCF     TRISA,CLK
        BCF     TRISA,ATT
        BCF     TRISB,FIRE0
        BCF     TRISB,FIRE1
        BSF     TRISB,CD32EN
        BCF     TRISB,UP
        BCF     TRISB,DOWN
        BCF     TRISB,LEFT
        BCF     TRISB,RIGHT
        BCF     OPTION_REG,INTEDG       ; Interrupt on falling edge
        BSF     OPTION_REG,NOT_RBPU     ; Disable PullUP
    banksel     PORTA

        RETURN  

Default:
    ; Set Defaults value
    ; Init IRQs
        BSF     PORTA,ATT               ; Set COMunication pins to 1
        BSF     PORTA,CLK
        BSF     PORTA,COM
        MOVLW   AUTOSPEED               ; Preset Autofire speed
        MOVWF   FIREVEL         
        BCF     INTCON,INTF             ; Configure IRQ
        BSF     INTCON,GIE
        BSF     INTCON,INTE

        RETURN  
        
; SubRoutine : Delay
;--------------------------------------------
; A delay routine, whose value is passed in W
; Not known the delay value in uS   
Delay:
        MOVWF   CONT1
Loop1:
        DECFSZ  CONT1,F
        GOTO    Loop1
        RETURN  
; SubRoutine : Bigdelay
; ------------------------------------------
; A long delay routine on top of 'Delay' 
Bigdelay:
        MOVLW   0X0A
        MOVWF   CONT2
        MOVLW   0X0A
Loop2:
        CALL    Delay
        DECFSZ  CONT2,F
        GOTO    Loop2
        RETURN  
        
        END
