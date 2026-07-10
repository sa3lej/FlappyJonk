# Flappy Jonk 🐦🍺

A flappy-bird game rendered with **real 3D** (lights, soft shadows, bloom, procedural
sky) but played flat/2D through an orthographic camera. The "bird" is Jonk's floating
head. Dodge the pipes, catch the beer cans, chase the high score.

## Play

- **Double-click** `Flappy Jonk` in Godot's project list, or from a terminal:
  ```
  godot --path "/Users/lars-erik/FlappyJonk"
  ```
- **SPACE** or **click** = flap. Same key starts the game and restarts after a game over.
- **F** (or F11) = fullscreen, **ESC** = back to windowed.

## Scoring

- +1 per pipe you clear
- +3 per beer can 🍺
- High scores save to disk and persist forever (`user://highscores.json`).

## Tweak Jonk's face

Jonk is shown in profile (like the photo): bald, big dark-gray beard, rectangular
glasses. Colors live in the `FRIEND` dictionary at the top of `Main.gd`; the shapes
are built in `_build_head` / `_build_beard` / `_build_glasses`.

```gdscript
const FRIEND := {
    "name": "JONK",
    "skin": Color(0.95, 0.76, 0.62),
    "beard_color": Color(0.30, 0.29, 0.28),
}
```

## Secrets

- **Cmd+Shift+K** (or Ctrl+Shift+K): wipe the high-score list. Works anywhere in the game.

## Dev screenshot mode

`godot --path . -- --shot <dir>` boots the game, captures `shot_menu.png` and
`shot_play.png` (with a self-flapping autopilot) into `<dir>`, then quits.
Used for visual iteration without touching the running game.

## Image credits

The space theme uses real photographs:

- **Sky**: "The Milky Way panorama" — ESO / S. Brunier, CC BY 4.0
- **Moon**: "FullMoon2010" — Gregory H. Revera (Wikimedia Commons), CC BY-SA 3.0
- **Flying rocket**: Falcon 9 SAOCOM 1B launch — U.S. Space Force 45th Space Wing,
  public domain. Subject lifted from the photo with `tools/cutout.swift` (macOS Vision).
- **Saturn**: Cassini orbiter mosaic — NASA/JPL/Space Science Institute, public domain.
- **Ground rockets**: Soyuz TMA-02M (NASA/Carla Cioffi), New Shepard booster at
  Oshkosh (Wikimedia Commons), Falcon 9 CRS-2 on pad (SpaceX) — all subject-lifted
  with `tools/cutout.swift`.
- **Obstacles**: Pillars of Creation, JWST NIRCam (NASA, ESA, CSA, STScI).
- **Astronaut**: Bruce McCandless II untethered EVA, 1984 (NASA, public domain).
- **Earth**: "The Blue Marble", Apollo 17 (NASA, public domain).
- **Martian ground**: Curiosity Mastcam at the Bagnold Dunes — near strip from
  PIA11242, distant dune sea from PIA20755 (NASA/JPL-Caltech/MSSS, public domain).
  Cropped, made tileable, and rust-graded with `tools/make_mars_ground.py`.
- **Title font**: "Press Start 2P" (`pixel_font.ttf`) — Cody "CodeMan38" Boisclair,
  SIL Open Font License 1.1.

If the game is ever published, keep these credits visible.

## Icon

`icon.svg` is the project icon; `FlappyJonk.icns` is ready to attach as the macOS
app icon when exporting a standalone .app (Project → Export → macOS → Icon).

## Difficulty knobs

Near the top of `Main.gd`: `GRAVITY`, `FLAP_VELOCITY`, `PIPE_GAP`, `BASE_SPEED`,
`BEER_CHANCE`, etc. Bigger `PIPE_GAP` / smaller `GRAVITY` = easier.
