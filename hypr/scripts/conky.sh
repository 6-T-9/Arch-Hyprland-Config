#!/bin/bash

killall conky

sleep 2

conky -c ~/.config/conky/date.conf &
conky -c ~/.config/conky/day.conf &
conky -c ~/.config/conky/weather.conf &