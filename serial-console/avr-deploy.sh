#!/bin/bash
file="main"
infile="$file".s
outfile="$file".out
elffile="$file".elf
hexfile="$file".hex
avr-gcc -c -o "$outfile" "$infile" -mmcu=atmega8 -Wa,--gstabs
if [ -f "$outfile" ]
then
    avr-ld -nostandardlib -o "$elffile" "$outfile"
    if [ -f "$elffile" ]
    then
        avr-objcopy -O ihex "$elffile" "$hexfile"
	echo "compiled & sent to avrdude."
	avrdude -P usb -c usbasp-clone -p ATmega8 -qq -U flash:w:"$hexfile"
	rm "$elffile" "$hexfile" "$outfile"
    else
	echo "$elffile not found, no uploading"
	rm "$outfile"
    fi
else
    echo "$outfile not found. no linking & uploading"
fi
