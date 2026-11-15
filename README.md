# Mochi

A tiny pixel pet that lives on your Wayland desktop. Mochi walks along the bottom of the screen, jumps onto floating windows and rides along when you move them, falls when a window closes, naps when you're away, dances when music plays, and can be petted, picked up and thrown.

Only Mochi itself catches clicks. The rest of the screen works as normal.

## What it does

- **Walks** along the bottom of the screen and on top of floating windows. At window edges it usually turns back, sometimes hops off.
- **Jumps** onto floating windows within reach and **rides along** when a window moves.
- **Falls** when its window closes or you switch workspace.
- **Sleeps** (z) after 2 minutes without input and wakes when you're back. Takes random naps too.
- **Dances** (♪) sometimes while a media player is playing (anything that speaks MPRIS: Spotify, browsers, mpv…).
- **Click** it for a happy hop (♥). **Drag** to pick it up. **Let go while moving** to throw it.

## Requirements

- A Wayland compositor with the layer-shell protocol: niri, Sway, Hyprland, KDE Plasma… (GNOME doesn't support it).
- [Quickshell](https://quickshell.org) 0.3 or newer (the `qs` command).
- **niri**, for the window tricks. Mochi reads floating-window positions from `niri msg`. On other compositors it still walks, sleeps, dances and can be thrown, but only along the bottom of the screen.

## Install

```bash
git clone https://github.com/lagswords-del/mochi.git ~/Projects/desktop-pet
mkdir -p ~/.local/bin
ln -sf ~/Projects/desktop-pet/bin/mochi ~/.local/bin/mochi
```

Make sure `~/.local/bin` is on your `PATH`. The `mochi` command finds the project through the symlink, so you can clone it anywhere.

## Use

```bash
mochi            # let Mochi out (or call it over if it's already out)
mochi stop       # send it home
mochi status     # what it's doing and where
mochi dance      # also: walk, jump, sleep, happy, idle, come
```

Mochi runs detached, so closing the terminal doesn't stop it.

### Start at login (niri)

Add this to `~/.config/niri/config.kdl`:

```kdl
spawn-at-startup "sh" "-c" "~/.local/bin/mochi"
```

## How it works

| File | What |
|---|---|
| `shell.qml` | A full-screen transparent layer surface whose input mask is just the pet. The "brain" is a small state machine (fall, land, idle, walk, crouch, jump, sleep, wake, happy, dance, drag) with gravity, and jump arcs solved to land on a chosen window. Polls `niri msg --json windows` every 350 ms. |
| `sprites.js` | The 16×14 pixel art and palette. Frames are built from one base body plus eyes, mouth and feet patches. |
| `PixelSprite.qml` | Draws a frame on a Canvas and repaints only when it changes. |
| `bin/mochi` | The command-line launcher, which talks to the running pet over Quickshell IPC. |

Raw IPC, if you'd rather skip the launcher:

```bash
qs -p ~/Projects/desktop-pet ipc call pet act dance
qs -p ~/Projects/desktop-pet ipc call pet status
```

## Known limits

- Only **floating** windows act as platforms: niri doesn't report screen positions for tiled windows.
- Uses a few percent CPU while moving, because the full-screen surface redraws.
