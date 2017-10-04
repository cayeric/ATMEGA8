# ATMEGA8
Tools, functions and other programming resources for the Atmega8.

## serial-console
The given assembler code implements a demonstration of a serial console interface to the ATMega8 microcontroller.
It reads a command from UART, compares against available command routines and calls the routine, if found. Sample commands switch connected LEDs on GPIO PC4 and PC5 on or off.
Installation of the serial console requires the gnu avr-gcc toolchain, including avrdude, avr-gcc and gas.
The deployment script expects a USB-ASP compatible programmer connected to the serial in-circuit-programming interface of the microcontroller.
