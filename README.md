# Audio HUD — KDE Plasma 6 Widget

A native Wayland/Plasma 6 desktop widget that shows live audio information from PipeWire.

## Features

- **DAC info** — active output device, codec, sample rate, bit depth
- **Stream monitoring** — active playback apps with their format
- **Bit-perfect indicator** — green when all streams match the sink format exactly, red when PipeWire is resampling
- **Mute detection** — volume icon and bar reflect mute state
- **Dynamic sink icon** — switches between headphones, speakers, HDMI, and generic icons
- **PipeWire offline detection** — widget dims and shows ⚠ OFFLINE if PipeWire stops responding
- **Adaptive theming** — follows your KDE color scheme automatically

## Requirements

- KDE Plasma 6.0+
- PipeWire with `pactl` (pulseaudio-utils / pipewire-pulse)
- `plasma5support` package

## Installation

```bash
mkdir -p ~/.local/share/plasma/plasmoids/com.github.audiohud/contents/ui
mkdir -p ~/.local/share/plasma/plasmoids/com.github.audiohud/contents/code
unzip audio-hud.plasmoid -d /tmp/audiohud
cp /tmp/audiohud/audio-hud/metadata.json ~/.local/share/plasma/plasmoids/com.github.audiohud/
cp /tmp/audiohud/audio-hud/contents/ui/main.qml ~/.local/share/plasma/plasmoids/com.github.audiohud/contents/ui/
cp /tmp/audiohud/audio-hud/contents/code/*.sh ~/.local/share/plasma/plasmoids/com.github.audiohud/contents/code/
chmod +x ~/.local/share/plasma/plasmoids/com.github.audiohud/contents/code/*.sh
plasmashell --replace &
```

Then right-click desktop → Add Widgets → search **Audio HUD**.

## Notes

- The widget reads codec info from `/proc/asound/` and scans card0–card3
- All helper scripts are bundled inside the plasmoid under `contents/code/`
- No Python dependency — fully self-contained QML/shell
