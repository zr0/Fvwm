#!/bin/bash

#XPOS="1358"
XPOS="231"

art="/home/s3r0/.config/bspwm/scripts/covers/$(ls ~/.config/bspwm/scripts/covers | grep -v SMALL | grep "$(mpc current -f %album% | sed 's/:/ /g')")"

feh -x -B black -^ "" -g 108x108+$(($XPOS-230))+$(($YPOS+116)) -Z "$art"& 

#sleep 60

#killall feh
