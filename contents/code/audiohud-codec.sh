#!/bin/sh
# Find the first codec file across all sound cards
for i in 0 1 2 3; do
    f="/proc/asound/card${i}/codec#0"
    if [ -f "$f" ]; then
        head -1 "$f"
        exit 0
    fi
done
echo "Codec: Unknown"
