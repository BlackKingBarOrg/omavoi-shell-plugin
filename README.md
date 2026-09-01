# Omavoi — Omarchy shell plugin

The desktop half of [Omavoi](https://github.com/BlackKingBarOrg/omavoi): voice
dictation for Omarchy and Hyprland. Hold a key, talk, and the text lands in
whatever window you were already typing into.

This repository is the recording HUD, the bar module, and the five-tab console.
It is what you install.

## Install

```sh
omarchy plugin add https://github.com/BlackKingBarOrg/omavoi-shell-plugin --enable --yes
```

Then open the console — `SUPER + ALT + V`, or click the bar module — and the
first-run screen takes it from there: it asks which language you want the
interface in and which speech model to use, then does the rest itself.

## Why this is a separate repository

`omarchy-shell` is a single Quickshell process that also draws your bar, your
notifications and your lock screen. A plugin is QML running *inside* it, and
Quickshell exposes no way to read the microphone — its Pipewire service is
volume and routing, not samples — and no way to read an input device. The
pre-roll ring buffer that keeps the first syllable, and a push-to-talk key read
below xkb so a modifier works at all, both need a process of their own.

So the model, the microphone and the hotkey live in a daemon, and this plugin
talks to it over a Unix socket. The daemon is a Python package in the
[main repository](https://github.com/BlackKingBarOrg/omavoi); the first-run
screen installs it for you.

That split has one more benefit worth naming: the daemon survives
`omarchy-restart-shell`. Change your theme and dictation keeps working, with
the weights still resident, instead of reloading three gigabytes.

## What the first-run screen does

Nothing until you press it, and it shows the exact command first. Omarchy
deliberately runs nothing from inside a plugin folder — a plugin lands in a
trusted directory and is not itself trusted — so the screen asks instead.

| | needs root |
|---|---|
| system packages: `uv`, `whisper-cpp`, `ggml-cpu`, `ggml-vulkan`, `xdotool` | yes — one password prompt, drawn by Omarchy's own polkit agent |
| the daemon, its systemd user unit, and starting it | no |
| the speech model, if you do not already have usable weights on disk | no |

Existing `ggml` weights are found and reused rather than downloaded again, so
if another tool already put a 3 GB model on this machine, that step is free.

## Uninstall

```sh
~/.config/omarchy/plugins/ai.bkblab.omavoi/install.sh --remove
omarchy plugin remove ai.bkblab.omavoi
```

The first line takes out the systemd unit and the keybinding; both files are
edited between markers, so it removes exactly what was added. The daemon,
your config and any downloaded weights are left alone — see the main
repository to remove those too.

MIT.
