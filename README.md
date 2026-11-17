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
| ✕ ○ □ △, D-pad, L1/R1, L3/R3 | Whatever you put on them (defaults below) |
| Touchpad | Click a quadrant (top-left, top-right, bottom-left, bottom-right): four more buttons |
| L2 / R2 / both | Hold for the second, third and fourth layer of buttons (Alt / Ctrl / Alt+Ctrl underneath) |
| Left stick | Move; a slight tilt walks, all the way runs |
| Right stick | Moves the camera (up/down inverted). Moving goes where the camera looks, and left/right while you move steers you, like steering with the mouse (the cursor hides meanwhile) |
| Options | Escape |

Defaults on the base layer (drop a spell on one to replace it; right-click → Clear turns it off):
✕ Jump · □ Interact (with what's in front of you) · ○ Back (close an NPC dialog, else stop attacking
and clear target) · L1 target nearest friend · R1 target nearest enemy · L3 auto-run.

While you hold L2/R2, mouse clicks are Alt-/Ctrl-clicks, as with the real keys.

**Menus from the controller:** while loot, a quest or an NPC's dialog is open, the D-pad moves a gold
highlight through its options, ✕ picks one, □ does the main thing (loot all, accept, complete) and ○
closes it. Your spells are back on those buttons when it closes.

Spells on the pad show their cooldown, tint red while your target is out of range, and darken while you
can't use them (blue: not enough mana, rage, …).

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
- **WoW actions:** right-click a button for a menu of them (world map, character, bags, spellbook,
  quest log, talents, …); the button then shows a short label like MAP or BAGS.
- **Clear:** right-click a button → Clear.
- **Move:** drag the dots above the pad. `/padbar lock` locks it, `/padbar reset` recenters it,
  `/padbar` hides/shows it.

## What PadBar changes in WoW

- Turns off WoW's own controller support (`GamePadEnable 0`): otherwise WoW would read the controller too.
- If they're at their controller-only defaults: soft targeting for interact and enemies is set to
  always (`SoftTargetInteract`, `SoftTargetEnemy` 1 → 3), and the camera stops swinging behind you
  while you move (`cameraSmoothStyle` 4 → 0), which fought the right stick. A value you pick stays.

## Tuning

- `pad.swift`, top: stick deadzone, diagonal angle, walk/run threshold, steering speed. Rebuild with `./build.sh`.
- `addon/PadBar/PadBar.lua`, top: camera speeds (`YAW_SPEED`, `PITCH_SPEED`), inverted tilt (`INVERT_Y`).
  Copy the addon into WoW again (`./install.sh`) and `/reload`.

## How walk/run stays right

WoW has only a run/walk toggle, which addons can't press. wow-pad sends what the stick *wants*
(a "walk" or a "run" key); PadBar, which reads from your speed whether you're walking, binds only the
one that would change your mode to the toggle. Asking for the mode you're in does nothing, so it can't
drift. wow-pad repeats its request while you hold the stick, so a mode that slipped is put right. In combat WoW
won't let addons rebind, so walk/run doesn't switch during a fight; it catches up right after.

## Uninstall

```sh
~/wow-pad/uninstall.sh
```

and delete `Interface/AddOns/PadBar`. Turn WoW's controller support back on in its options if you want it.

Works alongside [wow-span](https://github.com/scottlandes1217/wow-span) (two monitors with Offhand),
and without it.
