.include "m8def.inc"

;---- constants ----
.equ BAUD, 2400
.equ FREQ, 1000000
; line buffer
.equ LNB_TX_LENGTH, 64
.equ LNB_TX, SRAM_START
.equ LNB_RX_LENGTH, 32
; rx buffer right behind tx buffer
.equ LNB_RX, SRAM_START+LNB_TX_LENGTH
; <return> signals end of line
.equ LNB_RX_TERMINATOR, 13
; visual feedback with LEDs connected to PORT C
.equ LED_GREEN, PC5
.equ LED_RED, PC4

;---- register ----
; cells - "tva" local variable trinity
.equ temp, 16
.equ var, 17
.equ arg, 18

; line buffer data
.equ lnb_tx_ptr, 19 ; current position in buffer
.equ lnb_tx_remaining, 20 ; number of valid chars in buffer
.equ lnb_rx_ptr, 21 ; number of chars in buffer

;---- macros ----
.macro red_led
    push temp
    ldi temp, (1<<LED_RED)
    out PORTC,temp
    pop temp
.endm
.macro green_led
    push temp
    ldi temp, (1<<LED_GREEN)
    out PORTC,temp
    pop temp
.endm
.macro no_led
    push temp
    ldi temp, 0
    out PORTC,temp
    pop temp
.endm

.macro print_cstring STRING
    ; wait until running transmission is ended
    rcall wait_txc
    push ZH
    push ZL
    ldi ZH, hi8(\STRING\())
    ldi ZL, lo8(\STRING\())
    rcall loadln_cstring
    rcall writeln_serial
    pop ZL
    pop ZH
.endm
.macro print_register REGISTER
    ; wait until running transmission is ended
    rcall wait_txc
    push arg
    mov arg, \REGISTER\()
    rcall loadln_hex
    rcall writeln_serial
    pop arg
.endm
.macro rx_compare STRING
    ldi ZH, hi8(\STRING\())
    ldi ZL, lo8(\STRING\())
    rcall rx_compare_cstring
.endm

;---- program ----
.org 0x0000
         rjmp RESET         ; Interruptvektoren ueberspringen
                              ; und zum Hauptprogramm
         reti; rjmp EXT_INT0        ; IRQ0 Handler
         reti; EXT_INT1        ; IRQ1 Handler
         reti; TIM2_COMP
         reti; TIM2_OVF
         reti; TIM1_CAPT       ; Timer1 Capture Handler
         reti; TIM1_COMPA      ; Timer1 CompareA Handler
         reti; TIM1_COMPB      ; Timer1 CompareB Handler
         reti; TIM1_OVF        ; Timer1 Overflow Handler
         reti; TIM0_OVF        ; Timer0 Overflow Handler
         reti; SPI_STC         ; SPI Transfer Complete Handler
         rjmp USART_RXC       ; USART RX Complete Handler
         reti; USART_DRE       ; UDR Empty Handler
         rjmp USART_TXC       ; USART TX Complete Handler
         reti; ADC             ; ADC Conversion Complete Interrupthandler
         reti; EE_RDY          ; EEPROM Ready Handler
         reti; ANA_COMP        ; Analog Comparator Handler
         reti; TWSI            ; Two-wire Serial Interface Handler
         reti; SPM_RDY         ; Store Program Memory Ready Handler

;---- initialize device ----
RESET:
    ; while init no interrupt
    cli

    ; Stackpointer initialisieren
    ldi temp, hi8(RAMEND)
    out      SPH, temp
    ldi      temp, lo8(RAMEND)
    out      SPL, temp

    ; configure USART
    ; baudrate UBRR=(f/(16*baud))-1
    ldi temp, hi8( ( FREQ / ( 16 * BAUD) ) - 1 )
    out UBRRH, temp
    ldi temp, lo8( ( FREQ / ( 16 * BAUD) ) - 1 )
    out UBRRL, temp
    ; set frame format
    ldi temp, (1 << URSEL) | (3 << UCSZ0)
    out UCSRC, temp
    ; enable receiver and trnsmitter
    ldi temp, (1<< TXEN) | (1<<RXEN)
    out UCSRB, temp

    ; set LED pins on port C
    ldi temp, (1<<LED_GREEN) | (1<<LED_RED)
    out DDRC,temp

    ; enable interrupts
    sei

    ; greating message
    print_cstring STRING_WELCOME

;---- go into main loop <rx, process, tx> ----
main:
    ; request input with prompt line
    print_cstring STRING_PROMPT
    ; wait for linebuffer data (until RX interrupt gets disabled, because of termination character or overflow)
    rcall readln_serial
    ; wait until received complete line
    rcall wait_rxc
    ; wait until echo is transmitted
    rcall wait_txc

    ; branch to command
    ; command 1?
    rx_compare COMMAND_1
    brne cmd_1_end
    no_led
    rjmp main
cmd_1_end:
    ; cmd 2?
    rx_compare COMMAND_2
    brne cmd_2_end
    green_led
    rjmp main
cmd_2_end:
	; cmd 3?
	rx_compare COMMAND_3
	brne cmd_3_end
	red_led
	rjmp main
cmd_3_end:
    ; if command not found, continue main loop after issue error message
    print_cstring STRING_ERROR
    ; next cycle
    rjmp main

;---- read data from usart into line buffer until termination character ----
readln_serial:
    ; wait until active read operation with ISR is terminated
    rcall wait_rxc
    ; reset pointer
    ldi lnb_rx_ptr, 0
    ; enable receiver interrupt
    in arg, UCSRB
    sbr arg, (1 << RXCIE)
    out UCSRB, arg
    ; done
    ret

;---- insert received byte into linebuffer, check break condition ----
USART_RXC:
    ; save state
    push arg
    ; space left in buffer?
    cpi lnb_rx_ptr, LNB_RX_LENGTH
    brlt advance_rx_ptr
    ; signal buffer overflow
    rjmp disable_rx_isr
advance_rx_ptr:
    ; calculate current buffer pointer address
    push XH
    push XL
    ldi XH, hi8(LNB_RX)
    ldi XL, lo8(LNB_RX)
    add XL, lnb_rx_ptr
    ; overflow?
    brcc store_byte
    inc XH
store_byte:
    in arg, UDR
    st X, arg
    inc lnb_rx_ptr
    ; echo
    ; only send one byte
    ldi lnb_tx_remaining, 1
    ; enable and signal ongoing transmission
    in temp, UCSRB
    sbr temp, (1<<TXCIE)
    out UCSRB, temp
    out UDR, arg
    ; done receiving
    pop XL
    pop XH
    ; check rx terminator
    cpi arg, LNB_RX_TERMINATOR
    breq disable_rx_isr
    ; done, clean up
    pop arg
    reti
disable_rx_isr:
    in arg, UCSRB
    cbr arg, (1 << RXCIE)
    out UCSRB, arg
    ; we're done here
    pop arg
    reti

;---- wait for end of serial transmission, disabled interrupt on either tx or rx
wait_rxc:
    push arg
    push temp
    ldi arg, (1<<RXCIE)
    rjmp wait_xc
wait_txc:
    push arg
    push temp
    ldi arg, (1<<TXCIE)
; wait for end of rx/tx transmission as determined by variable arg
wait_xc:
    ; read enabled interrupts 
    in temp, UCSRB
    ; check if TX/RX still running
    and temp, arg
    brne wait_xc
    ; we're done: clean up
    pop temp
    pop arg
    ret

;---- write out data from line buffer, append termination character ----
writeln_serial:
    ; if pointer is reset, no need to do anything
    cpi lnb_tx_remaining, 0
    brne writeln_serial_start
    ret
writeln_serial_start:
    push arg
    push XH
    push XL
    ; enable transmitter interrupt
    in arg, UCSRB
    sbr arg, (1 << TXCIE)
    out UCSRB, arg
    ; reset pointer
    clr lnb_tx_ptr
    ; load first byte
    ldi XH, hi8(LNB_TX)
    ldi XL, lo8(LNB_TX)
    ld arg, X
    out UDR, arg
    ; the rest of the work is done in ISR
    pop XL
    pop XH
    pop arg
    ret

USART_TXC:
    ; cause we work with arg register, we might want to restore it after finish
    push arg
    ; check if remaining bytes and transmit them
    dec lnb_tx_remaining
    brne advance_pointer
    ; remove tx routine from ISRs
    rjmp disable_tx_isr
advance_pointer:
    inc lnb_tx_ptr
    ; buffer end?
    cpi lnb_tx_ptr, LNB_TX_LENGTH
    brlt tx_next_byte
disable_tx_isr:
    in arg, UCSRB
    cbr arg, (1 << TXCIE)
    out UCSRB, arg
    ; we're done here
    pop arg
    reti
tx_next_byte:
    ; load next byte
    push XH
    push XL
    ldi XH, hi8(LNB_TX)
    ldi XL, lo8(LNB_TX)
    ; adjust address according to pointer
    add XL, lnb_tx_ptr
    ; overflow?
    brcc load_byte
    inc XH
load_byte:
    ld arg, X
    out UDR, arg
    ; clean up and finish
    pop XL
    pop XH
    pop arg
    reti

;---- load constant string at program memory position determined by Z double register into line buffer ----
loadln_cstring:
    push arg
    ; resetln_serial:
    ldi lnb_tx_remaining, 0
    ; init line buf pointer
    push XH
    push XL
    ldi XH, hi8(LNB_TX)
    ldi XL, lo8(LNB_TX)
    ; read data from memory
loadln_string_read:
    LPM arg, Z+
    ST X+, arg
    ; adjust pointer
    inc lnb_tx_remaining
    ; check terminator
    cpi arg, 0
    breq loadln_string_done
    cpi lnb_tx_remaining, LNB_TX_LENGTH
    brlt loadln_string_read
loadln_string_done:
    pop XL
    pop XH
    pop arg
    ret

;---- load dec formatted number from register arg value in tx line buffer ----
loadln_dec:
    ; set pointer to line buffer
    push XH
    push XL
    push var
    push temp
    push arg ; since its a destructive algo
    ldi XH, hi8(LNB_TX)
    ldi XL, lo8(LNB_TX)
    ldi lnb_tx_remaining, 0
    ldi var, 100
    rcall process_digit
    ldi var, 10
    rcall process_digit
    ldi var, 1
    rcall process_digit
    pop arg
    pop temp
    pop var
    pop XL
    pop XH
    ret
;---- load hex formatted number from register arg value in tx line buffer ----
loadln_hex:
    ; set pointer to line buffer
    push XH
    push XL
    push var
    push temp
    push arg ; since its a destructive algo
    ldi XH, hi8(LNB_TX)
    ldi XL, lo8(LNB_TX)
    ldi lnb_tx_remaining, 0
    ldi var, 16
    rcall process_digit
    ldi var, 1
    rcall process_digit
    pop arg
    pop temp
    pop var
    pop XL
    pop XH
    ret
; process a single digit in arg with base in var register
process_digit:
    ; start with char 0
    ldi temp, 48
compare_value:
    cp arg, var
    ; if smaller, we have all hundreds counted stop here
    brlo write_digit
    ; subtract from value
    sub arg, var
    ; increment number character
    inc temp
    ; adjust for ascii hex
    cpi temp, 58
    brne compare_value
    push var
    ldi var, 7
    add temp, var
    pop var
    rjmp compare_value
write_digit:
    ; write out hundreds and reset char to zero
    st X+, temp
    inc lnb_tx_remaining
    ret

;---- print out rx buffer as hex bytes ----
rx_dump:
    push lnb_rx_ptr
    push YH
    push YL
    ldi YH, hi8(LNB_RX)
    ldi YL, lo8(LNB_RX)
next_rx_buffer_char:
    cpi lnb_rx_ptr, 0
    breq end_rx_buffer_dump
    ld var, Y+
    print_register var
    print_cstring STRING_SPACE
    dec lnb_rx_ptr
    rjmp next_rx_buffer_char
end_rx_buffer_dump:
    pop YL
    pop YH
    pop lnb_rx_ptr
    ret

;---- cstring compare, expects address of zero-terminated string to compare at Z----
rx_compare_cstring:
    push arg
    push temp
    ; reset_rx_pointer
    ; how many chars in buffer (excluding delimiter) to compare
    mov arg, lnb_rx_ptr
    dec arg
    ldi YH, hi8(LNB_RX)
    ldi YL, lo8(LNB_RX)
next_cstring_char:
    ; load current char from command list
    lpm temp, Z+
    ; a match requires remaining chars zero while there is a delimiter in command list
test_rx_string_end:
    ; no chars left for further comparisation?
    cpi arg, 0
    breq string_terminator
    ; get current char from test buffer
    dec arg
    push var
    ld var, Y+
    ; compare
    cp temp, var
    pop var
    ; if matching, advance to next position in current command
    breq next_cstring_char
    ; no match, return with NZ
    rjmp compare_end
string_terminator:
    ; marks a delimiter char an end of command string?
    cpi temp, 0
    brne next_cstring_char
    ; we have a match, clean up and return with Z
compare_end:
    pop temp
    pop arg
    ret

;---- constant strings ----
COMMAND_1:
.ascii "off"
.byte 0
COMMAND_2:
.ascii "orange"
.byte  0
COMMAND_3:
.ascii "red"
.byte  0

STRING_WELCOME:
.byte 27 ; escape cls
.ascii "[2J"
.byte 27 ; escape home
.ascii "[;H" 
.ascii "\033[1;33m" ; color yellow
.ascii "serial communication interface"
.ascii "\033[1;37m" ; color white
.byte 13,0

STRING_ERROR:
.byte 10, 13
.ascii "error"
.byte 13, 0

STRING_PROMPT:
.byte 10, 13
.ascii "ready"
.byte 10, 13
.ascii "> "
.byte 0

STRING_SPACE:
.byte 32
.byte 0

STRING_VALUE:
.byte 13, 10
.ascii "value: "
.byte 0

STRING_RXDUMP_HEADER:
.byte 13, 10
.ascii ">> rx: "
.byte 0

STRING_RX_DUMPFOOTER:
.ascii " <<"
.byte 13, 10, 0
