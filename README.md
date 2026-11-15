# wow-pad

Play World of Warcraft on a Mac with a **PS5 (or any) controller and the keyboard and mouse together**,
with a small on-screen gamepad of your spells, like WoW's Gamepad UI, but without the Gamepad UI.

WoW's own controller mode (the Gamepad UI) locks the controller whenever an addon touches what it
reads ("taint"): map addons like OpenMap break it every time you open the map. wow-pad avoids that
entirely: **WoW never sees a controller**. A small Mac program turns the controller into keys nobody
types, and the PadBar addon binds those keys to your spells and draws the pad.

- **wow-pad** (Mac): reads the controller while WoW is the active app and sends keys. One button press
  is one key press, so it stays within Blizzard's rules.
- **PadBar** (WoW addon): the little PS5 pad. Drag spells onto it; it binds wow-pad's keys to them.

## Controls

| Controller | Does |
|---|---|
| ✕ ○ □ △, D-pad, L1/R1, L3/R3, Create, touchpad | Whatever you put on them (defaults below) |
| L2 / R2 / both | Hold for the second, third and fourth layer of buttons (Alt / Ctrl / Alt+Ctrl underneath) |
| Left stick | Move; a slight tilt walks, all the way runs |
| Right stick | Left/right turns, up/down tilts the camera (inverted) |
| Options | Escape |

Defaults on the base layer (drop a spell on one to replace it; right-click turns it off):
✕ Jump · □ Interact (with what's in front of you) · ○ Back (close an NPC dialog, else stop attacking
and clear target) · L1 target nearest friend · R1 target nearest enemy.

While you hold L2/R2, mouse clicks are Alt-/Ctrl-clicks, as with the real keys.

## Requirements

- macOS on Apple silicon, Xcode or the Command Line Tools (`xcode-select --install`) for `swiftc`
- A controller macOS sees (Bluetooth DualSense, Xbox, …)

## Install

```sh
git clone https://github.com/scottlandes1217/wow-pad.git ~/wow-pad
~/wow-pad/install.sh
```

Then launch WoW and log in. macOS asks to allow **wow-pad** under **Accessibility**; allow it.
Once, with WoW running and logged in:

```sh
~/wow-pad/wow-pad --calibrate
```

It brings WoW forward, types `/padbar learn` and sends each of its keys, so PadBar learns what this
WoW client calls them (the Mac client renames some, e.g. F13 is PRINTSCREEN). Saved per account.

## Using the pad

- **Assign:** drag a spell, item or macro onto a button. To fill a layer, hold L2/R2 while you drag,
  or click the layer's tab under the pad.
- **Clear:** right-click a button.
- **Move:** drag the dots above the pad. `/padbar lock` locks it, `/padbar reset` recenters it,
  `/padbar` hides/shows it.

## What PadBar changes in WoW

- Turns off WoW's own controller support (`GamePadEnable 0`): otherwise WoW would read the controller too.
- If they're at their controller-only defaults: soft targeting for interact and enemies is set to
  always (`SoftTargetInteract`, `SoftTargetEnemy` 1 → 3), and the camera stops swinging behind you
  while you move (`cameraSmoothStyle` 4 → 0), which fought the right stick. A value you pick stays.

## Tuning

- `pad.swift`, top: stick deadzone, walk/run threshold. Rebuild with `./build.sh`.
- `addon/PadBar/PadBar.lua`, top: camera tilt speed (`PITCH_SPEED`), inverted tilt (`INVERT_Y`).
  Copy the addon into WoW again (`./install.sh`) and `/reload`.

## How walk/run stays right

WoW has only a run/walk toggle, which addons can't press. wow-pad sends what the stick *wants*
(a "walk" or a "run" key); PadBar, which reads from your speed whether you're walking, binds only the
one that would change your mode to the toggle. Asking for the mode you're in does nothing, so it can't
drift. In combat WoW won't let addons rebind, so a change made mid-fight is corrected after it.

## Uninstall

```sh
~/wow-pad/uninstall.sh
```

and delete `Interface/AddOns/PadBar`. Turn WoW's controller support back on in its options if you want it.

Works alongside [wow-span](https://github.com/scottlandes1217/wow-span) (two monitors with Offhand),
and without it.
