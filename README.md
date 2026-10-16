# LilyGo T-Deck Texas Hold'em Poker for WADAMESH (Lua 5.4)

A **No-Limit Texas Hold'em Poker** application built for the **LilyGo T-Deck** (and other MeshCore / WADAMESH boards) using the on-device **WADAMESH Lua App SDK (`wada.*` API v1)**.

## Project Files

- [`holdem.lua`](holdem.lua) — Standalone Lua app ready to copy to your T-Deck.
- [`holdem.json`](holdem.json) — WADAMESH app drawer / Store manifest.
- [`deploy/apps/holdem/1.0/`](deploy/apps/holdem/1.0) — Structured for USB serial sideloading (`scripts/sideload_app.py`) or submitting to the WADAMESH Store.
- [`holdem_simulator.html`](holdem_simulator.html) — Interactive desktop browser simulator of the 320×240 T-Deck screen, trackball, and physical keyboard.
- [`test_holdem.lua`](test_holdem.lua) — Automated SDK constraint and gameplay verification script.

---

## Features

- **4-Max No-Limit Table (You vs. 3 AI Personalities):**
  - **TEX** (Loose-Passive caller), **VIPER** (Tight-Aggressive shark), and **DUKE** (Loose-Aggressive bluffer).
  - Rotating **Dealer (`D`)**, **Small Blind (`SB`)**, and **Big Blind (`BB`)** badges with selectable blind levels (`$5/$10`, `$10/$20`, `$25/$50`).
  - Automatic `$500` bailout buy-in if your stack hits `$0`, and automatic AI re-buys if you bust an opponent.
- **Exact 7-Card Hand Evaluator & Side-Pot Engine:**
  - Evaluates all 10 poker hand categories (`HIGH CARD` through `ROYAL FLUSH`, including `A-2-3-4-5` wheel straights) in $O(13)$ using 32-bit-safe integers, displaying your live best hand next to your hole cards on every street.
  - Full support for uncontested fold wins, split pots, and multi-way **all-in side pots**.
- **Font-Independent Solid-Rect Suit Pips:** Custom-rendered Spade, Heart, Diamond, and Club vector icons on `wada.ui.canvas` using solid `cv:rect` scanlines so cards render crisply on all LVGL builds.
- **Persistent Stack & Home Widget:**
  - Saves your stack, all-time peak bankroll, hands won, and blind level via `wada.store`.
  - Publishes live stack and win rate to the WADAMESH **Home Screen Widget** (`wada.widget.set`).

---

## Installing on Your LilyGo T-Deck

### Option 1: microSD Card (Fastest)
1. Insert your T-Deck's microSD card into your computer.
2. Copy [`holdem.lua`](holdem.lua) and [`holdem.json`](holdem.json) to:
   ```text
   /meshcomod/apps/holdem.lua
   /meshcomod/apps/holdem.json
   ```
3. Insert the card back into the T-Deck and open the **Apps** drawer — **Texas Hold'em** will appear with the game icon.

### Option 2: USB Serial Sideload
```bash
python scripts/sideload_app.py --port COM3 --reboot deploy/apps/holdem/1.0
```

---

## Controls on the LilyGo T-Deck

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
| **Trackball Left / Right** | Cycle focus highlight across bottom bar buttons |
| **Trackball Up / Down** | Adjust raise target by 1 Big Blind |
| **Trackball Click** | Activate focused button |
