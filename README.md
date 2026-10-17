# Texas Hold'em Poker for WADAMESH (Lua 5.4) — T-Deck & T-Display P4 (AMOLED / LCD)

A **No-Limit Texas Hold'em Poker** application built for **LilyGo T-Display P4 (AMOLED & LCD)**, **LilyGo T-Deck**, **Heltec V4**, **T-LoRa Pager**, and other MeshCore / WADAMESH boards using the on-device **WADAMESH Lua App SDK (`wada.*` API v1)**.

## Project Files

- [`holdem.lua`](holdem.lua) — Standalone Lua app ready to copy to your device.
- [`holdem.json`](holdem.json) — WADAMESH app drawer / Store manifest.
- [`deploy/apps/holdem/1.1/`](deploy/apps/holdem/1.1) — Structured for USB serial sideloading (`scripts/sideload_app.py`) or submitting to the WADAMESH Store.
- [`holdem_simulator.html`](holdem_simulator.html) — Interactive desktop browser simulator.
- [`test_holdem.lua`](test_holdem.lua) — Automated SDK constraint, instruction budget, and multi-device verification script.

---

## Supported Devices & Auto-Scaling

`holdem.lua` automatically detects the host device and screen orientation on startup (`app.on_open(w, h)` / `wada.sys.board()`) and adapts its canvas architecture, layout, card dimensions, suit pips, and font sizes:

| Device | Native Resolution | App Body (`w × h`) | Canvas Tiles (`<= 480×480`) | Community Cards (`cw × ch`) | Font Tiers |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **LilyGo T-Display P4 AMOLED** (Portrait) | `568 × 1232` (RM69A10) | `568 × 1166` | `2 × 3` tiles (`284 × 389`) | `98 × 137` px | `14 / 16 / 20 / 24` |
| **LilyGo T-Display P4 AMOLED** (Landscape) | `1232 × 568` (RM69A10) | `1232 × 502` | `3 × 2` tiles (`411 × 251`) | `88 × 120` px | `14 / 16 / 20 / 24` |
| **LilyGo T-Display P4 LCD** (Portrait) | `540 × 1168` (HI8561) | `540 × 1102` | `2 × 3` tiles (`270 × 368`) | `92 × 128` px | `14 / 16 / 20 / 24` |
| **LilyGo T-Display P4 LCD** (Landscape) | `1168 × 540` (HI8561) | `1168 × 474` | `3 × 1` tiles (`390 × 474`) | `85 × 116` px | `14 / 16 / 20 / 24` |
| **LilyGo T-Deck / T-Deck Plus** | `320 × 240` | `320 × 208` | `1` canvas (`320 × 208`) | `36 × 47` px | `10 / 11 / 12 / 14 / 16` |
| **Heltec V4 / Compact Portrait** | `240 × 320` | `240 × 244` | `1` canvas (`240 × 244`) | `38 × 50` px | `10 / 11 / 12 / 14 / 16` |
| **LilyGo T-LoRa Pager** | `480 × 222` | `480 × 178` | `1` canvas (`480 × 178`) | `32 × 42` px | `10 / 11 / 12 / 14 / 16` |

---

## Features

- **4-Max No-Limit Table (You vs. 3 AI Personalities):**
  - **TEX** (Loose-Passive caller), **VIPER** (Tight-Aggressive shark), and **DUKE** (Loose-Aggressive bluffer).
  - Rotating **Dealer (`D`)**, **Small Blind (`SB`)**, and **Big Blind (`BB`)** badges with selectable blind levels (`$5/$10`, `$10/$20`, `$25/$50`).
  - Automatic `$500` bailout buy-in if your stack hits `$0`, and automatic AI re-buys if you bust an opponent.
- **Exact 7-Card Hand Evaluator & Side-Pot Engine:**
  - Evaluates all 10 poker hand categories (`HIGH CARD` through `ROYAL FLUSH`, including `A-2-3-4-5` wheel straights) in $O(13)$ using 32-bit-safe integers, displaying your live best hand next to your hole cards on every street.
  - Full support for uncontested fold wins, split pots, and multi-way **all-in side pots**.
- **Scalable Solid-Rect Suit Pips:** Custom-rendered Spade, Heart, Diamond, and Club vector icons on `wada.ui.canvas` that scale from `2px` mini pips on T-Deck AI showdown cards up to `13px` center pips with dual-corner rank indices on the T-Display P4.
- **Persistent Stack & Home Widget:**
  - Saves your stack, all-time peak bankroll, hands won, and blind level via `wada.store`.
  - Publishes live stack and win rate to the WADAMESH **Home Screen Widget** (`wada.widget.set`).

---

## Installing on Your Device

### Option 1: microSD Card (Fastest)
1. Insert your device's microSD card into your computer.
2. Copy [`holdem.lua`](holdem.lua) and [`holdem.json`](holdem.json) to:
   ```text
   /meshcomod/apps/holdem.lua
   /meshcomod/apps/holdem.json
   ```
3. Insert the card back into your T-Display P4 or T-Deck and open the **Apps** drawer — **Texas Hold'em** will appear with the game icon.

### Option 2: USB Serial Sideload
```bash
python scripts/sideload_app.py --port COM3 --reboot deploy/apps/holdem/1.1
```

---

## Controls

| Input Method | Action |
| :--- | :--- |
| **Touchscreen** | Tap any action button on the bottom bar (`FOLD`, `CHECK`/`CALL`, `BET`/`RAISE`, `+BB`, `ALL-IN`), tap during an AI turn to fast-forward, tap the table after a hand to deal, or tap top-right to mute/unmute beeps. |
| **Keyboard `F`** | **Fold** |
| **Keyboard `C`** | **Check** or **Call** |
| **Keyboard `R`** | **Bet** or **Raise** to target amount |
| **Keyboard `A`** | **All-In** |
| **Keyboard `W` / `Z` or `+` / `-`** | Increase / Decrease raise target by 1 Big Blind |
| **Keyboard `D` / `H`** | **Deal** next hand |
| **Keyboard `B` / `N`** | Cycle **Blinds** (`$5/$10`, `$10/$20`, `$25/$50`) / **New Table** (`$500` reset) |
| **Keyboard `Enter` / `Space`** | Activate highlighted button (or skip AI delay) |
| **Keyboard `M`** | Toggle sound (`wada.sys.beep`) |
| **Trackball / Swipe Left / Right** | Cycle focus highlight across bottom bar buttons |
| **Trackball / Swipe Up / Down** | Adjust raise target by 1 Big Blind |
