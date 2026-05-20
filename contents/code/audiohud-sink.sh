#!/bin/sh
pactl list sinks | grep -A 80 "$(pactl get-default-sink)"
