#!/usr/bin/env bash

WP="$1"

if [ -z "$WP" ] || [ ! -f "$WP" ]; then
    echo "Error: Invalid file path: $WP"
    exit 1
fi

if pgrep -x "awww-daemon" > /dev/null || command -v awww &>/dev/null; then
    awww img "$WP" --transition-type outer --transition-step 90 --transition-fps 60 2>/dev/null || awww img "$WP"
    exit 0
fi

if pgrep -x "hyprpaper" > /dev/null; then
    hyprctl hyprpaper preload "$WP"
    hyprctl hyprpaper wallpaper ",$WP"
    exit 0
fi

echo "No supported wallpaper daemon is running."
exit 1
