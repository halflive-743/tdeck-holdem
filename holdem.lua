-- Texas Hold'em Poker — WADAMESH Lua app for LilyGo T-Deck, T-Display P4 (AMOLED & LCD), & MeshCore boards
-- No-Limit 4-Max Table (You vs. 3 AI Bots: TEX, VIPER, DUKE)
-- Controls:
--   Touch:     Tap any bottom-bar button, tap during AI turn to fast-forward, tap table after hand to deal
--   Keyboard:  [F] Fold  [C] Check/Call  [R] Bet/Raise  [A] All-In  [D/H] Deal
--              [W/Up/+] Increase Raise  [Z/Down/-] Decrease Raise  [B] Cycle Blinds  [N] New Table  [M] Mute
--   Trackball: Left/Right cycle buttons, Up/Down adjust raise size, Click to activate focused button

local ui, sys, store, timer = wada.ui, wada.sys, wada.store, wada.timer
local C = ui.colors

local app = {}

-- Screen, device profile & layout metrics
local W, H = 320, 208
local cv
local MAX_CANVAS_DIM = 480 -- LuaAppHost.cpp enforces 1..480 per wada.ui.canvas call

local DEV = {
  id = "tdeck",
  name = "T-Deck",
  is_p4 = false,
  portrait = false,
  scale = 1,
}

local L = {
  top_h = 20,
  bot_h = 30,
  table_h = 158,
  cc_w = 37,
  cc_h = 48,
  cc_gap = 5,
  p_cw = 37,
  p_ch = 48,
  pip_sm = 3,
  pip_lg = 5,
  f_xs = 10,
  f_sm = 11,
  f_md = 12,
  f_lg = 14,
  f_xl = 16,
  f_rank = 12,
  lh_xs = 14,
  lh_sm = 15,
  lh_md = 16,
  lh_lg = 18,
  lh_xl = 20,
  lh_rank = 16,
  pad = 6,
  btn_gap = 4,
}

-- Palette tailored for WadaMesh dark UI & casino felt
local COL_FELT       = 0x0B2B1E
local COL_FELT_DARK  = 0x082016
local COL_FELT_LINE  = 0x164A35
local COL_TOPBAR     = 0x0E1318
local COL_BOTBAR     = 0x0E1318
local COL_POD_BG     = 0x101820
local COL_POD_FOLD   = 0x0A1214
local COL_CARD_BG    = 0xF5F7FA
local COL_CARD_SHAD  = 0x06150E
local COL_CARD_BACK  = 0x1B4F8A
local COL_CARD_TRIM  = 0x4A8FE7
local COL_RED        = 0xD9383A
local COL_BLACK      = 0x181C24
local COL_GOLD       = 0xF2C14E
local COL_BTN        = 0x1A222B
local COL_BTN_ACT    = 0x1E3A3A
local COL_BTN_DIS    = 0x11161C
local COL_TEXT_DIM   = 0x525A65

-- Game constants
local START_STACK = 500
local BLIND_LEVELS = {
  { sb = 5,  bb = 10 },
  { sb = 10, bb = 20 },
  { sb = 25, bb = 50 },
}
local blind_idx = 1

local RANKS = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K" }
local HAND_NAMES = {
  [0] = "HIGH CARD",
  [1] = "ONE PAIR",
  [2] = "TWO PAIR",
  [3] = "3 OF A KIND",
  [4] = "STRAIGHT",
  [5] = "FLUSH",
  [6] = "FULL HOUSE",
  [7] = "4 OF A KIND",
  [8] = "STR. FLUSH",
  [9] = "ROYAL FLUSH",
}

-- Persistent stats
local best_bank = START_STACK
local hands_won = 0
local hands_played = 0
local sound_on = true

-- Table & round state
-- state: "title" | "player" | "ai" | "done"
local state = "title"
local street = 0 -- 0=PRE-FLOP, 1=FLOP, 2=TURN, 3=RIVER, 4=SHOWDOWN
local STREET_NAMES = { [0] = "PRE-FLOP", [1] = "FLOP", [2] = "TURN", [3] = "RIVER", [4] = "SHOWDOWN" }

local deck = {}
local deck_top = 0
local board = {}
local pot = 0
local cur_bet = 0
local min_raise = 10
local raise_to = 20
local dealer_seat = 1
local turn_seat = 1
local last_aggressor = 0
local show_all_cards = false

local banner_title = ""
local banner_sub = ""
local banner_col = 0x15B6A6

-- 4 Seats: 1=YOU (bottom), 2=TEX (left), 3=VIPER (center), 4=DUKE (right)
local seats = {
  { name = "YOU",   is_human = true,  style = "human", stack = START_STACK, cards = {}, street_bet = 0, total_bet = 0, folded = false, all_in = false, acted = false, status = "", role = "" },
  { name = "TEX",   is_human = false, style = "loose", stack = START_STACK, cards = {}, street_bet = 0, total_bet = 0, folded = false, all_in = false, acted = false, status = "", role = "" },
  { name = "VIPER", is_human = false, style = "tag",   stack = START_STACK, cards = {}, street_bet = 0, total_bet = 0, folded = false, all_in = false, acted = false, status = "", role = "" },
  { name = "DUKE",  is_human = false, style = "lag",   stack = START_STACK, cards = {}, street_bet = 0, total_bet = 0, folded = false, all_in = false, acted = false, status = "", role = "" },
}

-- Bottom bar interactive buttons
local active_btns = {}
local focus_idx = 1

-- Strict integer helper (LuaAppHost.cpp requires integers for all canvas coords)
local function I(x)
  return math.floor(tonumber(x) or 0)
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function sfx()
  if sound_on and sys.beep then
    pcall(sys.beep)
  end
end

-- Safe RNG wrapper: LuaAppHost.cpp sysRandom(lo, hi) requires hi > lo
local function rand_int(lo, hi)
  lo, hi = I(lo), I(hi)
  if hi <= lo then return lo end
  local r = sys.random(lo, hi)
  if r < lo or r > hi then
    r = lo + (math.abs(r) % (hi - lo + 1))
  end
  return I(r)
end

local function text_w(str, sz)
  local s = tostring(str or "")
  local fsz = I(sz or L.f_sm)
  if ui.text_w then
    return I(ui.text_w(s, fsz))
  end
  return I(#s * (fsz + 4) * 0.48)
end

local function text_h(sz)
  local fsz = I(sz or L.f_sm)
  if ui.text_h then
    return I(ui.text_h(fsz))
  end
  return fsz + 4
end

-- Auto-detect WADAMESH device (T-Display P4 AMOLED, T-Display P4 LCD, T-Deck, Heltec V4, Pager, etc.)
local function detect_device(w, h)
  local short_side = math.min(w, h)
  local long_side  = math.max(w, h)
  local portrait   = (h > w)

  if long_side >= 1185 or (w == 568 and h >= 900) or (w >= 1185 and h >= 460) then
    DEV = { id = "p4_amoled", name = "T-Display P4 AMOLED", is_p4 = true, portrait = portrait, scale = 2 }
  elseif (long_side >= 1050 and long_side < 1185) or (w == 540 and h >= 900) or (w >= 500 and w < 560 and h >= 900) then
    DEV = { id = "p4_lcd", name = "T-Display P4 LCD", is_p4 = true, portrait = portrait, scale = 2 }
  elseif long_side >= 700 or short_side >= 460 then
    DEV = { id = "large_hd", name = "Large HD", is_p4 = false, portrait = portrait, scale = 2 }
  elseif w >= 440 and h < 320 then
    DEV = { id = "pager", name = "Wide Compact", is_p4 = false, portrait = false, scale = 1 }
  elseif portrait and w <= 260 then
    DEV = { id = "v4_portrait", name = "Compact Portrait", is_p4 = false, portrait = true, scale = 1 }
  else
    DEV = { id = "tdeck", name = "T-Deck", is_p4 = false, portrait = portrait, scale = 1 }
  end
end

local function compute_layout()
  detect_device(W, H)

  if DEV.scale >= 2 then
    L.f_xs   = 14
    L.f_sm   = 14
    L.f_md   = 16
    L.f_lg   = 20
    L.f_xl   = 24
    L.f_rank = 16
  else
    L.f_xs   = 10
    L.f_sm   = 11
    L.f_md   = 12
    L.f_lg   = 14
    L.f_xl   = 16
    L.f_rank = 12
  end

  L.lh_xs   = text_h(L.f_xs)
  L.lh_sm   = text_h(L.f_sm)
  L.lh_md   = text_h(L.f_md)
  L.lh_lg   = text_h(L.f_lg)
  L.lh_xl   = text_h(L.f_xl)
  L.lh_rank = text_h(L.f_rank)

  if DEV.scale >= 2 then
    L.top_h   = I(math.max(L.lh_md + 16, 40))
    L.bot_h   = DEV.portrait and I(math.max(L.lh_md + 42, 72)) or I(math.max(L.lh_md + 26, 54))
    L.pad     = 14
    L.btn_gap = 8
  else
    L.top_h   = 20
    L.bot_h   = 30
    L.pad     = 6
    L.btn_gap = 4
  end

  L.table_h = math.max(80, H - L.top_h - L.bot_h)

  if DEV.portrait and DEV.scale >= 2 then
    -- T-Display P4 Portrait (568x1166 AMOLED or 540x1102 LCD)
    L.cc_gap = 10
    L.cc_w   = I(clamp((W - 36 - L.cc_gap * 4) / 5, 86, 98))
    L.cc_h   = I(L.cc_w * 1.40)
    L.p_cw   = I(clamp(W * 0.175, 92, 104))
    L.p_ch   = I(L.p_cw * 1.40)
    L.pip_sm = 6
    L.pip_lg = 13
  elseif DEV.scale >= 2 then
    -- T-Display P4 Landscape (1232x502 or 1168x474)
    L.cc_h   = I(clamp(L.table_h * 0.30, 88, 120))
    L.cc_w   = I(L.cc_h * 0.74)
    L.cc_gap = 12
    L.p_cw   = L.cc_w
    L.p_ch   = L.cc_h
    L.pip_sm = 5
    L.pip_lg = 11
  elseif DEV.portrait then
    -- Compact Portrait (Heltec V4 240x244)
    L.cc_gap = 4
    L.cc_w   = I(clamp((W - 16 - L.cc_gap * 4) / 5, 34, 40))
    L.cc_h   = I(clamp(L.cc_w * 1.32, 44, 52))
    L.p_cw   = 35
    L.p_ch   = 46
    L.pip_sm = 3
    L.pip_lg = 5
  else
    -- LilyGo T-Deck (320x208) & Wide Compact (Pager 480x178)
    L.cc_h   = clamp(I(L.table_h * 0.30), 40, 48)
    L.cc_w   = clamp(I(L.cc_h * 0.77), 32, 37)
    L.cc_gap = 5
    L.p_cw   = L.cc_w
    L.p_ch   = L.cc_h
    L.pip_sm = 3
    L.pip_lg = 5
  end
end

-- Create a full-screen canvas matching (W, H) without violating LuaAppHost.cpp's
-- 1..480 per-canvas dimension check on large displays like the LilyGo T-Display P4.
local function create_screen_canvas(w, h)
  w, h = I(w), I(h)
  if w <= MAX_CANVAS_DIM and h <= MAX_CANVAS_DIM then
    local single = ui.canvas(w, h)
    single:pos(0, 0)
    return single
  end

  local nx = math.ceil(w / MAX_CANVAS_DIM)
  local ny = math.ceil(h / MAX_CANVAS_DIM)
  local base_tw = I(math.ceil(w / nx))
  local base_th = I(math.ceil(h / ny))

  local tiles = {}
  for ry = 0, ny - 1 do
    local ty = ry * base_th
    local th = math.min(base_th, h - ty)
    for cx = 0, nx - 1 do
      local tx = cx * base_tw
      local tw = math.min(base_tw, w - tx)
      if tw > 0 and th > 0 then
        local tc = ui.canvas(tw, th)
        tc:pos(tx, ty)
        tiles[#tiles + 1] = {
          c  = tc,
          x  = tx,
          y  = ty,
          w  = tw,
          h  = th,
          x2 = tx + tw,
          y2 = ty + th,
        }
      end
    end
  end

  local vcv = { w = w, h = h, tiles = tiles }

  function vcv:pos(px, py)
    px, py = I(px), I(py)
    for i = 1, #tiles do
      local t = tiles[i]
      t.c:pos(px + t.x, py + t.y)
    end
  end

  function vcv:fill(col)
    col = I(col)
    for i = 1, #tiles do
      tiles[i].c:fill(col)
    end
  end

  function vcv:rect(x, y, rw, rh, col, filled, radius)
    x = x - (x % 1); y = y - (y % 1)
    rw = rw - (rw % 1); rh = rh - (rh % 1)
    col = col - (col % 1)
    local rad = radius ~= nil and (radius - (radius % 1)) or nil
    local rx2, ry2 = x + rw, y + rh
    for i = 1, #tiles do
      local t = tiles[i]
      if rx2 > t.x and x < t.x2 and ry2 > t.y and y < t.y2 then
        if rad ~= nil then
          t.c:rect(x - t.x, y - t.y, rw, rh, col, filled, rad)
        else
          t.c:rect(x - t.x, y - t.y, rw, rh, col, filled)
        end
      end
    end
  end

  function vcv:line(x1, y1, x2, y2, col, width)
    x1 = x1 - (x1 % 1); y1 = y1 - (y1 % 1)
    x2 = x2 - (x2 % 1); y2 = y2 - (y2 % 1)
    col = col - (col % 1)
    local lw = width ~= nil and (width - (width % 1)) or 1
    local lx1 = (x1 < x2 and x1 or x2) - lw
    local ly1 = (y1 < y2 and y1 or y2) - lw
    local lx2 = (x1 > x2 and x1 or x2) + lw + 1
    local ly2 = (y1 > y2 and y1 or y2) + lw + 1
    for i = 1, #tiles do
      local t = tiles[i]
      if lx2 > t.x and lx1 < t.x2 and ly2 > t.y and ly1 < t.y2 then
        t.c:line(x1 - t.x, y1 - t.y, x2 - t.x, y2 - t.y, col, lw)
      end
    end
  end

  function vcv:circle(x, y, r, col, filled)
    x = x - (x % 1); y = y - (y % 1); r = r - (r % 1); col = col - (col % 1)
    local cx1, cy1 = x - r - 2, y - r - 2
    local cx2, cy2 = x + r + 2, y + r + 2
    for i = 1, #tiles do
      local t = tiles[i]
      if cx2 > t.x and cx1 < t.x2 and cy2 > t.y and cy1 < t.y2 then
        t.c:circle(x - t.x, y - t.y, r, col, filled)
      end
    end
  end

  local function draw_text_segment(x, y, s, col, sz)
    x = x - (x % 1); y = y - (y % 1); col = col - (col % 1); sz = sz - (sz % 1)
    local tw = text_w(s, sz)
    local th = text_h(sz)
    if tw > base_tw - 10 then
      local mid = math.floor(#s / 2)
      local split_pos = nil
      for d = 0, mid - 1 do
        if s:sub(mid + d, mid + d) == " " then split_pos = mid + d; break end
        if mid - d >= 1 and s:sub(mid - d, mid - d) == " " then split_pos = mid - d; break end
      end
      if split_pos and split_pos > 1 and split_pos < #s then
        local left_s = s:sub(1, split_pos - 1)
        local right_s = s:sub(split_pos + 1)
        draw_text_segment(x, y, left_s, col, sz)
        draw_text_segment(x + text_w(left_s .. " ", sz), y, right_s, col, sz)
        return
      end
    end
    local tx2, ty2 = x + tw + 4, y + th + 4
    for i = 1, #tiles do
      local t = tiles[i]
      if tx2 > t.x and x < t.x2 and ty2 > t.y and y < t.y2 then
        t.c:text(x - t.x, y - t.y, s, col, sz)
      end
    end
  end

  function vcv:text(x, y, s, col, size)
    draw_text_segment(x, y, tostring(s or ""), col, size or L.f_sm)
  end

  return vcv
end

local function get_blinds()
  local b = BLIND_LEVELS[blind_idx] or BLIND_LEVELS[1]
  return b.sb, b.bb
end

-- Persistence & WadaMesh Home Screen Widget
local function save_stats()
  local pstack = I(seats[1].stack)
  if pstack > best_bank then
    best_bank = pstack
  end
  store.set("he_bank", pstack)
  store.set("he_best", I(best_bank))
  store.set("he_wins", I(hands_won))
  store.set("he_hands", I(hands_played))
  store.set("he_blind", I(blind_idx))
  if wada.widget and wada.widget.set then
    local pct = hands_played > 0 and I((hands_won * 100) / hands_played) or 0
    pcall(wada.widget.set, {
      title = "Hold'em",
      value = string.format("$%d", pstack),
      line  = string.format("Peak $%d  ·  Won %d%% (%d/%d)", I(best_bank), pct, I(hands_won), I(hands_played))
    })
  end
end

-- Pre-allocate 52-card deck once and shuffle in-place
local function init_deck_pool()
  if #deck == 52 then return end
  deck = {}
  local idx = 1
  for s = 1, 4 do
    for r = 1, 13 do
      deck[idx] = { r = r, s = s }
      idx = idx + 1
    end
  end
end

local function build_deck()
  init_deck_pool()
  for i = 52, 2, -1 do
    local j = rand_int(1, i)
    deck[i], deck[j] = deck[j], deck[i]
  end
  deck_top = 52
end

local function draw_card()
  if deck_top < 1 then build_deck() end
  local c = deck[deck_top]
  deck_top = deck_top - 1
  return c
end

-- Convert internal rank (1=Ace, 2..13=2..K) to poker value (2..14, where 14=Ace)
local function pval(r)
  return r == 1 and 14 or r
end

-- Fast O(13) 5-to-7 card Poker Hand Evaluator
-- Returns: score (32-bit safe integer < 10,000,000), category (0..9), short_name
local function eval_best_hand(hole, comm)
  local all = {}
  for i = 1, #hole do all[#all + 1] = hole[i] end
  if comm then
    for i = 1, #comm do all[#all + 1] = comm[i] end
  end
  local n = #all
  if n == 0 then return 0, 0, "HIGH CARD" end

  local rcnt = {}
  local scnt = { 0, 0, 0, 0 }
  local sbits = { 0, 0, 0, 0 }
  local rbits = 0

  for v = 2, 14 do rcnt[v] = 0 end

  for i = 1, n do
    local v = pval(all[i].r)
    local s = all[i].s
    rcnt[v] = rcnt[v] + 1
    scnt[s] = scnt[s] + 1
    local bit = 1 << v
    rbits = rbits | bit
    sbits[s] = sbits[s] | bit
    if v == 14 then
      rbits = rbits | 2     -- Ace low bit (value 1) for A-2-3-4-5 wheel
      sbits[s] = sbits[s] | 2
    end
  end

  local function pack(cat, k1, k2, k3, k4, k5)
    k1 = k1 or 0; k2 = k2 or 0; k3 = k3 or 0; k4 = k4 or 0; k5 = k5 or 0
    return I(cat * 1000000 + k1 * 38416 + k2 * 2744 + k3 * 196 + k4 * 14 + k5)
  end

  local function top_straight(mask)
    for high = 14, 5, -1 do
      local m = 31 << (high - 4)
      if (mask & m) == m then
        return high
      end
    end
    return 0
  end

  -- 1. Check Flush & Straight Flush
  local flush_suit = 0
  for s = 1, 4 do
    if scnt[s] >= 5 then
      flush_suit = s
      break
    end
  end

  if flush_suit > 0 then
    local sf_high = top_straight(sbits[flush_suit])
    if sf_high > 0 then
      local cat = (sf_high == 14) and 9 or 8
      return pack(cat, sf_high, 0, 0, 0, 0), cat, HAND_NAMES[cat]
    end
  end

  -- Group ranks by multiplicity
  local quads, trips, pairs, singles = {}, {}, {}, {}
  for v = 14, 2, -1 do
    local c = rcnt[v]
    if c == 4 then quads[#quads + 1] = v
    elseif c == 3 then trips[#trips + 1] = v
    elseif c == 2 then pairs[#pairs + 1] = v
    elseif c == 1 then singles[#singles + 1] = v
    end
  end

  -- 2. Four of a Kind
  if #quads > 0 then
    local q = quads[1]
    local kicker = 0
    for v = 14, 2, -1 do
      if v ~= q and rcnt[v] > 0 then kicker = v; break end
    end
    return pack(7, q, kicker, 0, 0, 0), 7, HAND_NAMES[7]
  end

  -- 3. Full House
  if #trips > 0 and (#trips >= 2 or #pairs >= 1) then
    local t = trips[1]
    local p = (#trips >= 2) and trips[2] or pairs[1]
    return pack(6, t, p, 0, 0, 0), 6, HAND_NAMES[6]
  end

  -- 4. Flush
  if flush_suit > 0 then
    local fc = {}
    local mask = sbits[flush_suit]
    for v = 14, 2, -1 do
      if (mask & (1 << v)) ~= 0 then
        fc[#fc + 1] = v
        if #fc == 5 then break end
      end
    end
    return pack(5, fc[1], fc[2], fc[3], fc[4], fc[5]), 5, HAND_NAMES[5]
  end

  -- 5. Straight
  local st_high = top_straight(rbits)
  if st_high > 0 then
    return pack(4, st_high, 0, 0, 0, 0), 4, HAND_NAMES[4]
  end

  -- 6. Three of a Kind
  if #trips > 0 then
    local t = trips[1]
    local k1, k2 = 0, 0
    for v = 14, 2, -1 do
      if v ~= t and rcnt[v] > 0 then
        if k1 == 0 then k1 = v elseif k2 == 0 then k2 = v; break end
      end
    end
    return pack(3, t, k1, k2, 0, 0), 3, HAND_NAMES[3]
  end

  -- 7. Two Pair
  if #pairs >= 2 then
    local p1, p2 = pairs[1], pairs[2]
    local k1 = 0
    for v = 14, 2, -1 do
      if v ~= p1 and v ~= p2 and rcnt[v] > 0 then k1 = v; break end
    end
    return pack(2, p1, p2, k1, 0, 0), 2, HAND_NAMES[2]
  end

  -- 8. One Pair
  if #pairs == 1 then
    local p1 = pairs[1]
    return pack(1, p1, singles[1], singles[2], singles[3], 0), 1, HAND_NAMES[1]
  end

  -- 9. High Card
  return pack(0, singles[1], singles[2], singles[3], singles[4], singles[5]), 0, HAND_NAMES[0]
end

-- Forward declarations
local rebuild_buttons
local draw_screen
local advance_turn
local next_street_or_showdown
local resolve_hand

-- Count players still in the hand (not folded) and players able to act (not folded and not all-in)
local function count_players()
  local active, can_act = 0, 0
  for i = 1, 4 do
    if not seats[i].folded then
      active = active + 1
      if not seats[i].all_in and seats[i].stack > 0 then
        can_act = can_act + 1
      end
    end
  end
  return active, can_act
end

-- Post chips from seat idx into pot
local function post_chips(idx, amount)
  local p = seats[idx]
  local actual = I(math.min(amount, p.stack))
  p.stack = I(p.stack - actual)
  p.street_bet = I(p.street_bet + actual)
  p.total_bet = I(p.total_bet + actual)
  pot = I(pot + actual)
  if p.stack <= 0 then
    p.stack = 0
    p.all_in = true
  end
  return actual
end

-- Sync player's raise_to slider bounds
local function sync_raise_bounds()
  local _, bb = get_blinds()
  local p = seats[1]
  local max_total = I(p.street_bet + p.stack)
  local min_total = I(cur_bet + math.max(bb, min_raise))
  if cur_bet == 0 then
    min_total = bb
  end
  if min_total > max_total then
    min_total = max_total
  end
  raise_to = I(clamp(raise_to, min_total, max_total))
end

-- Execute an action for seat idx: "fold" | "call" | "raise" | "allin"
local function perform_action(idx, kind, target_bet)
  local p = seats[idx]
  local _, bb = get_blinds()
  p.acted = true

  if kind == "fold" then
    p.folded = true
    p.status = "FOLD"
    sfx()
  elseif kind == "call" then
    local need = I(cur_bet - p.street_bet)
    if need <= 0 then
      p.status = "CHECK"
    else
      post_chips(idx, need)
      p.status = p.all_in and "ALL-IN" or string.format("CALL $%d", I(p.street_bet))
    end
    sfx()
  elseif kind == "raise" or kind == "allin" then
    local max_tot = I(p.street_bet + p.stack)
    local des_tot = (kind == "allin") and max_tot or I(clamp(target_bet or raise_to, cur_bet + bb, max_tot))
    local added = I(des_tot - p.street_bet)
    if added > 0 then
      post_chips(idx, added)
    end
    if p.street_bet > cur_bet then
      local diff = I(p.street_bet - cur_bet)
      if diff > min_raise then min_raise = diff end
      cur_bet = p.street_bet
      last_aggressor = idx
      for i = 1, 4 do
        if i ~= idx and not seats[i].folded and not seats[i].all_in then
          seats[i].acted = false
        end
      end
    end
    if p.all_in then
      p.status = string.format("ALL-IN $%d", I(p.street_bet))
    elseif cur_bet == added then
      p.status = string.format("BET $%d", I(p.street_bet))
    else
      p.status = string.format("RAISE $%d", I(p.street_bet))
    end
    sfx()
  end

  local active = count_players()
  if active <= 1 then
    resolve_hand(true)
    return
  end

  advance_turn()
end

-- Decide AI action for seat idx
local function ai_decide(idx)
  local p = seats[idx]
  local _, bb = get_blinds()
  local to_call = I(cur_bet - p.street_bet)
  local score, cat = eval_best_hand(p.cards, board)

  local strength = 25
  if street == 0 then
    local v1, v2 = pval(p.cards[1].r), pval(p.cards[2].r)
    local hi, lo = math.max(v1, v2), math.min(v1, v2)
    local suited = (p.cards[1].s == p.cards[2].s)
    if v1 == v2 then
      strength = 52 + hi * 3
    else
      strength = (hi * 2) + lo + (suited and 8 or 0) + ((hi - lo == 1) and 5 or 0)
    end
  else
    strength = 18 + cat * 18 + I((score % 1000000) / 38416)
  end

  local roll = rand_int(1, 100)
  if p.style == "loose" then
    strength = strength + 10
  elseif p.style == "lag" then
    strength = strength + (roll > 65 and 18 or 4)
  elseif p.style == "tag" then
    strength = strength + (street > 0 and cat >= 1 and 8 or -3)
  end

  if to_call <= 0 then
    if strength >= 58 and p.stack > bb and roll <= 70 then
      local bet_sz = I(math.min(p.street_bet + p.stack, math.max(bb, I(pot * 0.5))))
      perform_action(idx, "raise", bet_sz)
    else
      perform_action(idx, "call")
    end
  else
    local pot_odds_penalty = I((to_call * 45) / math.max(bb, pot))
    local eff = strength - pot_odds_penalty
    if to_call >= p.stack then
      if strength >= 52 or (to_call <= bb * 2 and strength >= 36) then
        perform_action(idx, "allin")
      else
        perform_action(idx, "fold")
      end
    elseif eff >= 54 and p.stack > to_call + bb * 2 and roll <= 55 then
      local r_tot = I(cur_bet + math.max(min_raise, bb * 2))
      perform_action(idx, "raise", r_tot)
    elseif eff >= 24 or to_call <= bb then
      perform_action(idx, "call")
    else
      perform_action(idx, "fold")
    end
  end
end

-- Find next player to act on current street, or move to next street
advance_turn = function()
  local active, can_act = count_players()
  if active <= 1 then
    resolve_hand(true)
    return
  end

  for step = 1, 4 do
    local nxt = ((turn_seat + step - 1) % 4) + 1
    local p = seats[nxt]
    if not p.folded and not p.all_in and p.stack > 0 then
      if not p.acted or p.street_bet < cur_bet then
        if can_act == 1 and p.street_bet >= cur_bet then
          break
        end
        turn_seat = nxt
        if p.is_human then
          timer.stop()
          state = "player"
          sync_raise_bounds()
          rebuild_buttons()
          draw_screen()
        else
          state = "ai"
          rebuild_buttons()
          draw_screen()
          timer.every(420)
        end
        return
      end
    end
  end

  next_street_or_showdown()
end

-- Deal next community street or proceed to showdown
next_street_or_showdown = function()
  timer.stop()
  for i = 1, 4 do
    seats[i].street_bet = 0
    seats[i].acted = false
    if not seats[i].folded and not seats[i].all_in then
      seats[i].status = ""
    end
  end
  cur_bet = 0
  local _, bb = get_blinds()
  min_raise = bb

  if street == 0 then
    street = 1
    board[1] = draw_card()
    board[2] = draw_card()
    board[3] = draw_card()
  elseif street == 1 then
    street = 2
    board[4] = draw_card()
  elseif street == 2 then
    street = 3
    board[5] = draw_card()
  else
    resolve_hand(false)
    return
  end

  sfx()
  local _, can_act = count_players()
  if can_act < 2 then
    show_all_cards = true
    state = "ai"
    rebuild_buttons()
    draw_screen()
    timer.every(520)
    return
  end

  turn_seat = dealer_seat
  advance_turn()
end

-- Settle pot (with full side-pot & split-pot support)
resolve_hand = function(by_fold)
  timer.stop()
  state = "done"
  street = 4

  if by_fold then
    local winner = 1
    for i = 1, 4 do
      if not seats[i].folded then winner = i; break end
    end
    seats[winner].stack = I(seats[winner].stack + pot)
    seats[winner].status = "WIN!"
    hands_played = hands_played + 1
    if winner == 1 then
      hands_won = hands_won + 1
      banner_title = "YOU WIN POT!"
      banner_sub = string.format("+$%d (Opponents Folded)", I(pot))
      banner_col = C.good
    else
      banner_title = seats[winner].name .. " WINS"
      banner_sub = string.format("Pot $%d (Folded)", I(pot))
      banner_col = C.accent
    end
    pot = 0
    save_stats()
    rebuild_buttons()
    draw_screen()
    return
  end

  show_all_cards = true
  local scores = {}
  local hnames = {}
  for i = 1, 4 do
    if not seats[i].folded then
      local sc, _, nm = eval_best_hand(seats[i].cards, board)
      scores[i] = sc
      hnames[i] = nm
      seats[i].status = nm
    else
      scores[i] = -1
    end
  end

  local rem = { seats[1].total_bet, seats[2].total_bet, seats[3].total_bet, seats[4].total_bet }
  local won_amt = { 0, 0, 0, 0 }
  local best_overall_winner = 1
  local best_overall_score = -1

  for i = 1, 4 do
    if scores[i] > best_overall_score then
      best_overall_score = scores[i]
      best_overall_winner = i
    end
  end

  while true do
    local min_lvl = 999999
    for i = 1, 4 do
      if not seats[i].folded and rem[i] > 0 and rem[i] < min_lvl then
        min_lvl = rem[i]
      end
    end
    if min_lvl == 999999 then break end

    local slice_pot = 0
    local elig = {}
    for i = 1, 4 do
      local take = math.min(rem[i], min_lvl)
      if take > 0 then
        rem[i] = rem[i] - take
        slice_pot = slice_pot + take
      end
      if not seats[i].folded and take == min_lvl then
        elig[#elig + 1] = i
      end
    end

    if slice_pot > 0 and #elig > 0 then
      local max_sc = -1
      for _, idx in ipairs(elig) do
        if scores[idx] > max_sc then max_sc = scores[idx] end
      end
      local winners = {}
      for _, idx in ipairs(elig) do
        if scores[idx] == max_sc then winners[#winners + 1] = idx end
      end
      local share = I(slice_pot / #winners)
      local odd = I(slice_pot - share * #winners)
      for w_i, idx in ipairs(winners) do
        local award = share + (w_i == 1 and odd or 0)
        seats[idx].stack = I(seats[idx].stack + award)
        won_amt[idx] = I(won_amt[idx] + award)
      end
    end

    local any_nonfold_rem = false
    for i = 1, 4 do
      if not seats[i].folded and rem[i] > 0 then any_nonfold_rem = true end
    end
    if not any_nonfold_rem then
      for i = 1, 4 do
        if rem[i] > 0 then
          seats[i].stack = I(seats[i].stack + rem[i])
          rem[i] = 0
        end
      end
      break
    end
  end

  hands_played = hands_played + 1
  if won_amt[1] > 0 then
    hands_won = hands_won + 1
    banner_title = string.format("YOU WIN $%d!", I(won_amt[1]))
    banner_sub = hnames[1] or "BEST HAND"
    banner_col = COL_GOLD
  else
    local w = best_overall_winner
    banner_title = string.format("%s WINS $%d", seats[w].name, I(won_amt[w]))
    banner_sub = hnames[w] or "SHOWDOWN"
    banner_col = seats[1].folded and C.accent or C.bad
  end

  pot = 0
  save_stats()
  sfx()
  rebuild_buttons()
  draw_screen()
end

-- Start a new hand
local function start_hand()
  local sb, bb = get_blinds()

  if seats[1].stack < bb then
    seats[1].stack = START_STACK
    sys.toast("Free $500 bailout buy-in!")
  end
  for i = 2, 4 do
    if seats[i].stack < bb then
      seats[i].stack = START_STACK
      sys.toast(seats[i].name .. " re-bought $500")
    end
  end

  build_deck()
  board = {}
  pot = 0
  street = 0
  show_all_cards = false
  banner_title = ""
  banner_sub = ""

  dealer_seat = (dealer_seat % 4) + 1
  local sb_seat = (dealer_seat % 4) + 1
  local bb_seat = (sb_seat % 4) + 1

  for i = 1, 4 do
    local p = seats[i]
    p.cards = { draw_card(), draw_card() }
    p.street_bet = 0
    p.total_bet = 0
    p.folded = false
    p.all_in = false
    p.acted = false
    p.status = ""
    if i == dealer_seat then p.role = "D"
    elseif i == sb_seat then p.role = "SB"
    elseif i == bb_seat then p.role = "BB"
    else p.role = "" end
  end

  post_chips(sb_seat, sb)
  seats[sb_seat].status = string.format("SB $%d", I(seats[sb_seat].street_bet))

  post_chips(bb_seat, bb)
  seats[bb_seat].status = string.format("BB $%d", I(seats[bb_seat].street_bet))

  cur_bet = bb
  min_raise = bb
  raise_to = bb * 2
  last_aggressor = bb_seat

  sfx()
  turn_seat = bb_seat
  advance_turn()
end

local function adjust_raise(delta)
  if state ~= "player" then return end
  raise_to = I(raise_to + delta)
  sync_raise_bounds()
  sfx()
  rebuild_buttons()
  draw_screen()
end

local function cycle_blinds()
  blind_idx = (blind_idx % #BLIND_LEVELS) + 1
  local sb, bb = get_blinds()
  sys.toast(string.format("Blinds: $%d / $%d", sb, bb))
  sfx()
  save_stats()
  rebuild_buttons()
  draw_screen()
end

local function reset_table()
  for i = 1, 4 do
    seats[i].stack = START_STACK
  end
  sys.toast("New $500 Table")
  sfx()
  start_hand()
end

-- Build bottom bar buttons for current state
rebuild_buttons = function()
  active_btns = {}
  local sb, bb = get_blinds()
  local compact_btns = (W < 280)

  if state == "title" then
    active_btns = {
      { label = string.format("BLINDS $%d/$%d", sb, bb), key = "b", enabled = true, fn = cycle_blinds },
      { label = "RESET $500", key = "n", enabled = true, fn = reset_table },
      { label = compact_btns and "DEAL" or "DEAL HOLD'EM [D]", key = "d", primary = true, enabled = true, fn = start_hand },
    }
    focus_idx = 3
  elseif state == "player" then
    local p = seats[1]
    local to_call = I(math.max(0, cur_bet - p.street_bet))
    local can_raise = (p.stack > to_call)
    sync_raise_bounds()

    local call_lbl
    if to_call <= 0 then
      call_lbl = compact_btns and "CHECK" or "CHECK [C]"
    elseif to_call >= p.stack then
      call_lbl = string.format("ALL-IN $%d", I(p.stack))
    else
      call_lbl = string.format("CALL $%d", to_call)
    end

    local raise_lbl = (cur_bet == 0)
      and string.format("BET $%d", I(raise_to))
      or string.format("RAISE $%d", I(raise_to))

    active_btns = {
      { label = compact_btns and "FOLD" or "FOLD [F]", key = "f", enabled = true, fn = function() perform_action(1, "fold") end },
      { label = call_lbl,  key = "c", primary = true, enabled = true, fn = function() perform_action(1, "call") end },
      { label = raise_lbl, key = "r", enabled = can_raise, fn = function() perform_action(1, "raise", raise_to) end },
      { label = "+BB",     key = "+", enabled = can_raise, fn = function()
          local max_t = I(p.street_bet + p.stack)
          if raise_to >= max_t then
            raise_to = I(cur_bet + math.max(bb, min_raise))
          else
            raise_to = I(raise_to + bb)
          end
          sync_raise_bounds()
          sfx()
          rebuild_buttons()
          draw_screen()
        end },
      { label = "ALL-IN",  key = "a", enabled = p.stack > 0, fn = function() perform_action(1, "allin") end },
    }
    focus_idx = 2
  elseif state == "ai" then
    local who = seats[turn_seat] and seats[turn_seat].name or "DEALER"
    active_btns = {
      { label = who .. " ACTING... (TAP TO SKIP)", key = " ", enabled = true, fn = function()
          if state == "ai" then app.on_tick(0) end
        end }
    }
    focus_idx = 1
  elseif state == "done" then
    active_btns = {
      { label = string.format("$%d/$%d [B]", sb, bb), key = "b", enabled = true, fn = cycle_blinds },
      { label = compact_btns and "RESET" or "NEW TBL [N]", key = "n", enabled = true, fn = reset_table },
      { label = compact_btns and "DEAL [D]" or "NEXT HAND [D]", key = "d", primary = true, enabled = true, fn = start_hand },
    }
    focus_idx = 3
  end
end

-- Scalable solid-rect vector suit pip renderer (crisp at any radius r >= 2)
local function draw_suit_pip(x, y, suit, r)
  x, y, r = I(x), I(y), math.max(2, I(r))
  local col = (suit == 2 or suit == 3) and COL_RED or COL_BLACK
  local step = r >= 9 and 2 or 1

  -- Fast path: if using a tiled virtual canvas and this pip lies wholly within one tile,
  -- issue draw calls directly to that tile's native canvas with local coordinates.
  local tc = cv
  local ox, oy = 0, 0
  local tiles = cv.tiles
  if tiles then
    local x1, y1, x2, y2 = x - r - 2, y - r - 2, x + r + 2, y + r + 4
    for i = 1, #tiles do
      local t = tiles[i]
      if x1 >= t.x and x2 <= t.x2 and y1 >= t.y and y2 <= t.y2 then
        tc = t.c
        ox = t.x
        oy = t.y
        break
      end
    end
  end
  local px, py = x - ox, y - oy

  if r <= 2 then
    -- Ultra-compact mini pip (for small T-Deck AI showdown cards)
    if suit == 1 then -- Spade
      tc:rect(px, py - 2, 1, 1, col, true)
      tc:rect(px - 1, py - 1, 3, 1, col, true)
      tc:rect(px - 2, py, 5, 2, col, true)
      tc:rect(px, py + 2, 1, 2, col, true)
    elseif suit == 2 then -- Heart
      tc:rect(px - 2, py - 2, 2, 1, col, true)
      tc:rect(px + 1, py - 2, 2, 1, col, true)
      tc:rect(px - 2, py - 1, 5, 2, col, true)
      tc:rect(px - 1, py + 1, 3, 1, col, true)
      tc:rect(px, py + 2, 1, 1, col, true)
    elseif suit == 3 then -- Diamond
      tc:rect(px, py - 2, 1, 1, col, true)
      tc:rect(px - 1, py - 1, 3, 1, col, true)
      tc:rect(px - 2, py, 5, 1, col, true)
      tc:rect(px - 1, py + 1, 3, 1, col, true)
      tc:rect(px, py + 2, 1, 1, col, true)
    else -- Club
      tc:rect(px - 1, py - 2, 3, 2, col, true)
      tc:rect(px - 2, py, 5, 2, col, true)
      tc:rect(px, py + 2, 1, 2, col, true)
    end
    return
  end

  if suit == 1 then -- Spade
    local body_bot = I(r * 0.25)
    local span = math.max(1, r + body_bot)
    for dy = -r, body_bot, step do
      local hw = I(((dy + r) * r) / span)
      tc:rect(px - hw, py + dy, hw * 2 + 1, step, col, true)
    end
    local lr = math.max(1, I(r * 0.36))
    local lx = math.max(1, I(r * 0.42))
    local ly = I(r * 0.22)
    tc:circle(px - lx, py + ly, lr, col, true)
    tc:circle(px + lx, py + ly, lr, col, true)
    local stem_w = math.max(1, I(r * 0.22) * 2 + 1)
    local stem_top = I(r * 0.25)
    tc:rect(px - I(stem_w / 2), py + stem_top, stem_w, math.max(2, r - stem_top + 1), col, true)
    local base_hw = math.max(2, I(r * 0.55))
    tc:rect(px - base_hw, py + r, base_hw * 2 + 1, math.max(1, I(r * 0.18)), col, true)

  elseif suit == 2 then -- Heart
    local lr = math.max(1, I(r * 0.46))
    local lx = math.max(1, I(r * 0.46))
    local ly = I(r * 0.32)
    tc:circle(px - lx, py - ly, lr, col, true)
    tc:circle(px + lx, py - ly, lr, col, true)
    local top_dy = -I(r * 0.18)
    local span = math.max(1, r - top_dy)
    for dy = top_dy, r, step do
      local hw = math.max(0, I(((r - dy) * r) / span))
      tc:rect(px - hw, py + dy, hw * 2 + 1, step, col, true)
    end

  elseif suit == 3 then -- Diamond
    for dy = -r, r, step do
      local hw = math.max(0, r - math.abs(dy))
      tc:rect(px - hw, py + dy, hw * 2 + 1, step, col, true)
    end

  else -- Club
    local lr = math.max(1, I(r * 0.38))
    local lx = math.max(2, I(r * 0.48))
    local ty = I(r * 0.48)
    local by = I(r * 0.14)
    tc:circle(px, py - ty, lr, col, true)
    tc:circle(px - lx, py + by, lr, col, true)
    tc:circle(px + lx, py + by, lr, col, true)
    local stem_w = math.max(1, I(r * 0.22) * 2 + 1)
    tc:rect(px - I(stem_w / 2), py - I(r * 0.1), stem_w, math.max(2, r + I(r * 0.1) + 1), col, true)
    local base_hw = math.max(2, I(r * 0.52))
    tc:rect(px - base_hw, py + r, base_hw * 2 + 1, math.max(1, I(r * 0.18)), col, true)
  end
end

-- Draw a playing card at (x, y) of size (cw, ch)
local function draw_card_box(x, y, cw, ch, card, hidden, pip_sm_ov, pip_lg_ov)
  x, y, cw, ch = I(x), I(y), I(cw), I(ch)
  local rad = cw >= 64 and 8 or 3
  local shad = cw >= 64 and 3 or 1
  cv:rect(x + shad, y + shad, cw, ch, COL_CARD_SHAD, true, rad)

  if hidden or not card then
    local pad1 = cw >= 64 and 3 or 1
    local pad2 = cw >= 64 and 6 or 3
    cv:rect(x, y, cw, ch, COL_CARD_BG, true, rad)
    cv:rect(x + pad1, y + pad1, cw - pad1 * 2, ch - pad1 * 2, COL_CARD_BACK, true, math.max(2, rad - 1))
    if cw >= 26 then
      cv:rect(x + pad2, y + pad2, cw - pad2 * 2, ch - pad2 * 2, COL_CARD_TRIM, false, math.max(2, rad - 2))
      local er = math.max(4, I(cw * 0.15))
      cv:circle(I(x + cw / 2), I(y + ch / 2), er, COL_GOLD, false)
    end
    return
  end

  cv:rect(x, y, cw, ch, COL_CARD_BG, true, rad)
  cv:rect(x, y, cw, ch, 0xCBD2D9, false, rad)

  local col = (card.s == 2 or card.s == 3) and COL_RED or COL_BLACK
  local rstr = RANKS[card.r]

  if cw <= 24 then
    cv:text(x + 2, y + 1, rstr, col, 10)
    draw_suit_pip(x + I(cw / 2), y + ch - 7, card.s, 2)
  elseif cw < 64 then
    local p_sm = pip_sm_ov or 3
    local p_lg = pip_lg_ov or 5
    cv:text(x + 3, y + 2, rstr, col, 12)
    if cw >= 32 then
      draw_suit_pip(x + cw - 7, y + 8, card.s, p_sm)
    end
    draw_suit_pip(x + I(cw / 2), y + I(ch / 2) + 5, card.s, p_lg)
  else
    -- Large high-DPI card (LilyGo T-Display P4 AMOLED & LCD)
    local p_sm = pip_sm_ov or L.pip_sm
    local p_lg = pip_lg_ov or L.pip_lg
    local rank_fsz = L.f_rank
    local pad_x, pad_y = 6, 4
    cv:text(x + pad_x, y + pad_y, rstr, col, rank_fsz)
    draw_suit_pip(x + cw - p_sm - pad_x - 1, y + pad_y + p_sm + 2, card.s, p_sm)
    if cw >= 72 and ch >= 96 then
      local r_w = text_w(rstr, rank_fsz)
      local r_h = text_h(rank_fsz)
      cv:text(x + cw - pad_x - r_w, y + ch - pad_y - r_h, rstr, col, rank_fsz)
      draw_suit_pip(x + pad_x + p_sm + 1, y + ch - pad_y - p_sm - 3, card.s, p_sm)
    end
    draw_suit_pip(x + I(cw / 2), I(y + ch / 2), card.s, p_lg)
  end
end

-- Render one AI opponent pod at (px, py, pw, ph)
local function draw_ai_pod(idx, px, py, pw, ph)
  px, py, pw, ph = I(px), I(py), I(pw), I(ph)
  local p = seats[idx]
  local is_turn = (state == "ai" and turn_seat == idx)
  local bg = p.folded and COL_POD_FOLD or COL_POD_BG
  local border = is_turn and COL_GOLD or (p.status == "WIN!" and C.good or 0x22303C)
  local rad = DEV.scale >= 2 and 8 or 5

  cv:rect(px, py, pw, ph, bg, true, rad)
  cv:rect(px, py, pw, ph, border, false, rad)

  local head = p.role ~= "" and (p.name .. "·" .. p.role) or p.name
  local ncol = p.folded and COL_TEXT_DIM or (is_turn and COL_GOLD or C.text)
  local scol = p.folded and COL_TEXT_DIM or COL_GOLD
  local st = p.status ~= "" and p.status or (p.all_in and "ALL-IN" or "WAIT")
  local st_col = p.folded and COL_TEXT_DIM
    or (p.status == "WIN!" and C.good or (is_turn and C.accent or C.sub))

  if DEV.scale >= 2 and ph >= 110 then
    -- High-DPI Tall Pod (T-Display P4 Portrait)
    local pad_x = 10
    cv:text(px + pad_x, py + 8, head, ncol, L.f_md)
    cv:text(px + pad_x, py + 8 + L.lh_md + 2, string.format("$%d", I(p.stack)), scol, L.f_md)
    cv:text(px + pad_x, py + ph - L.lh_sm - 8, st, st_col, L.f_sm)

    if #p.cards == 2 and not p.folded then
      local mc_w = 42
      local mc_h = 58
      local mc_y = py + 12
      local mc_x1 = px + pw - mc_w * 2 - 12
      local mc_x2 = px + pw - mc_w - 6
      draw_card_box(mc_x1, mc_y, mc_w, mc_h, p.cards[1], not show_all_cards, 3, 6)
      draw_card_box(mc_x2, mc_y, mc_w, mc_h, p.cards[2], not show_all_cards, 3, 6)
    end
  elseif DEV.scale >= 2 then
    -- High-DPI Wide Pod (T-Display P4 Landscape)
    local pad_x = 12
    cv:text(px + pad_x, py + 6, head, ncol, L.f_md)
    cv:text(px + pad_x, py + 6 + L.lh_md + 2, string.format("$%d", I(p.stack)), scol, L.f_md)
    cv:text(px + pad_x, py + 6 + L.lh_md * 2 + 4, st, st_col, L.f_sm)

    if #p.cards == 2 and not p.folded then
      local mc_h = ph - 14
      local mc_w = I(mc_h * 0.72)
      draw_card_box(px + pw - mc_w * 2 - 14, py + 7, mc_w, mc_h, p.cards[1], not show_all_cards, 3, 6)
      draw_card_box(px + pw - mc_w - 8, py + 7, mc_w, mc_h, p.cards[2], not show_all_cards, 3, 6)
    end
  else
    -- Standard Compact Pod (T-Deck 320x208, Heltec V4 240x244, Pager 480x178)
    cv:text(px + 4, py + 2, head, ncol, L.f_xs)
    cv:text(px + 4, py + 14, string.format("$%d", I(p.stack)), scol, L.f_sm)
    cv:text(px + 4, py + 27, st, st_col, L.f_xs)

    if #p.cards == 2 and not p.folded and pw >= 84 then
      if show_all_cards then
        draw_card_box(px + pw - 39, py + 4, 18, 25, p.cards[1], false)
        draw_card_box(px + pw - 20, py + 4, 18, 25, p.cards[2], false)
      else
        draw_card_box(px + pw - 33, py + 5, 15, 22, p.cards[1], true)
        draw_card_box(px + pw - 20, py + 5, 15, 22, p.cards[2], true)
      end
    end
  end
end

-- Render full screen
draw_screen = function()
  local top_h   = L.top_h
  local bot_h   = L.bot_h
  local table_h = L.table_h
  local sb, bb  = get_blinds()

  cv:fill(COL_FELT)
  local margin = DEV.scale >= 2 and 8 or 3
  cv:rect(margin, top_h + margin - 1, W - margin * 2, table_h - (margin - 1) * 2, COL_FELT_LINE, false, DEV.scale >= 2 and 12 or 7)

  -- Top status bar
  cv:rect(0, 0, W, top_h, COL_TOPBAR, true)
  cv:line(0, top_h, W, top_h, 0x1F2933, 1)

  local top_fsz = DEV.scale >= 2 and L.f_md or L.f_sm
  local top_lh  = text_h(top_fsz)
  local top_ty  = math.max(1, I((top_h - top_lh) / 2))

  cv:text(L.pad, top_ty, string.format("STACK $%d", I(seats[1].stack)), COL_GOLD, top_fsz)

  local mid_top_str = (state == "title")
    and string.format("BLINDS $%d/$%d", sb, bb)
    or string.format("%s · $%d/$%d", STREET_NAMES[street] or "HOLD'EM", sb, bb)
  local mid_x = I((W - text_w(mid_top_str, top_fsz)) / 2)
  cv:text(mid_x, top_ty, mid_top_str, C.accent, top_fsz)

  local pk_str = string.format("PEAK $%d%s", I(best_bank), sound_on and "" or " [M]")
  local rw = text_w(pk_str, top_fsz)
  cv:text(math.max(mid_x + text_w(mid_top_str, top_fsz) + 6, W - rw - L.pad), top_ty, pk_str, C.sub, top_fsz)

  if state == "title" then
    local pad_x = DEV.scale >= 2 and 20 or 12
    local pad_y = DEV.scale >= 2 and 16 or 8
    local box_w = W - pad_x * 2
    local box_h = table_h - pad_y * 2
    local box_y = top_h + pad_y
    cv:rect(pad_x, box_y, box_w, box_h, COL_FELT_DARK, true, DEV.scale >= 2 and 12 or 8)
    cv:rect(pad_x, box_y, box_w, box_h, COL_FELT_LINE, false, DEV.scale >= 2 and 12 or 8)

    if DEV.portrait and DEV.scale >= 2 then
      -- High-DPI Portrait Title Screen (T-Display P4 AMOLED & LCD)
      local t1 = "TEXAS HOLD'EM"
      local t2 = "No-Limit 4-Max  ·  3 AI Opponents"
      local dev_s = string.format("%s  (%dx%d)", DEV.name, W, H)

      local cur_y = box_y + I(box_h * 0.07)
      cv:text(I((W - text_w(t1, L.f_xl)) / 2), cur_y, t1, COL_GOLD, L.f_xl)
      cur_y = cur_y + L.lh_xl + 10
      cv:text(I((W - text_w(t2, L.f_sm)) / 2), cur_y, t2, C.sub, L.f_sm)
      cur_y = cur_y + L.lh_sm + 6
      cv:text(I((W - text_w(dev_s, L.f_sm)) / 2), cur_y, dev_s, COL_FELT_LINE, L.f_sm)
      cur_y = cur_y + L.lh_sm + I(box_h * 0.05)

      local dec_w, dec_h = L.p_cw, L.p_ch
      local dec_gap = 24
      draw_card_box(I(W / 2 - dec_w - dec_gap / 2), cur_y, dec_w, dec_h, { r = 1, s = 1 }, false)
      draw_card_box(I(W / 2 + dec_gap / 2), cur_y, dec_w, dec_h, { r = 1, s = 2 }, false)
      cur_y = cur_y + dec_h + I(box_h * 0.06)

      local pill = string.format("BLINDS: $%d / $%d   BUY-IN: $%d", sb, bb, I(seats[1].stack))
      local pw = text_w(pill, L.f_lg)
      local pill_h = L.lh_lg + 24
      local pill_w = pw + 48
      cv:rect(I((W - pill_w) / 2), cur_y, pill_w, pill_h, COL_BTN_ACT, true, 10)
      cv:rect(I((W - pill_w) / 2), cur_y, pill_w, pill_h, C.accent, false, 10)
      cv:text(I((W - pw) / 2), cur_y + I((pill_h - L.lh_lg) / 2), pill, C.text, L.f_lg)
      cur_y = cur_y + pill_h + I(box_h * 0.05)

      local pct = hands_played > 0 and I((hands_won * 100) / hands_played) or 0
      local stat_str = string.format("Hands Played: %d   ·   Won: %d (%d%%)", I(hands_played), I(hands_won), pct)
      cv:text(I((W - text_w(stat_str, L.f_sm)) / 2), cur_y, stat_str, C.sub, L.f_sm)

      local hint = "Tap [DEAL HOLD'EM] below to start a hand"
      cv:text(I((W - text_w(hint, L.f_sm)) / 2), box_y + box_h - L.lh_sm - 18, hint, C.sub, L.f_sm)
    else
      -- Standard / Landscape Title Screen
      local dec_w = DEV.scale >= 2 and 64 or 32
      local dec_h = DEV.scale >= 2 and 90 or 44
      if W >= 280 then
        draw_card_box(pad_x + 10, box_y + 10, dec_w, dec_h, { r = 1, s = 1 }, false, DEV.scale >= 2 and 4 or 3, DEV.scale >= 2 and 9 or 5)
        draw_card_box(W - pad_x - dec_w - 10, box_y + 10, dec_w, dec_h, { r = 1, s = 2 }, false, DEV.scale >= 2 and 4 or 3, DEV.scale >= 2 and 9 or 5)
      end

      local t1 = "TEXAS HOLD'EM"
      local t1_y = box_y + 10
      cv:text(I((W - text_w(t1, L.f_xl)) / 2), t1_y, t1, COL_GOLD, L.f_xl)

      local t2 = "No-Limit 4-Max  ·  3 AI Opponents"
      local t2_y = t1_y + L.lh_xl + 4
      cv:text(I((W - text_w(t2, L.f_sm)) / 2), t2_y, t2, C.sub, L.f_sm)

      local pill = string.format("BLINDS: $%d / $%d   BUY-IN: $%d", sb, bb, I(seats[1].stack))
      local pw = text_w(pill, L.f_md)
      local pill_h = L.lh_md + (DEV.scale >= 2 and 16 or 8)
      local pill_w = pw + (DEV.scale >= 2 and 36 or 20)
      local py = math.max(t2_y + L.lh_sm + 8, I(box_y + (box_h - pill_h) * 0.54))
      cv:rect(I((W - pill_w) / 2), py, pill_w, pill_h, COL_BTN_ACT, true, 5)
      cv:rect(I((W - pill_w) / 2), py, pill_w, pill_h, C.accent, false, 5)
      cv:text(I((W - pw) / 2), py + I((pill_h - L.lh_md) / 2), pill, C.text, L.f_md)

      local hint = W >= 300 and "Tap [DEAL HOLD'EM] or press [D] to play" or "Tap [DEAL] below to play"
      local hint_y = box_y + box_h - L.lh_sm - (DEV.scale >= 2 and 12 or 6)
      if hint_y > py + pill_h + 4 then
        cv:text(I((W - text_w(hint, L.f_sm)) / 2), hint_y, hint, C.sub, L.f_sm)
      end
    end

  elseif DEV.portrait and DEV.scale >= 2 then
    -- High-DPI Portrait Table Layout (LilyGo T-Display P4 AMOLED 568x1166 & LCD 540x1102)
    local pad_x = 16
    local pod_gap = 10
    local pod_w = I((W - pad_x * 2 - pod_gap * 2) / 3)
    local pod_h = 126
    local pod_y = top_h + 16

    draw_ai_pod(2, pad_x, pod_y, pod_w, pod_h)
    draw_ai_pod(3, pad_x + pod_w + pod_gap, pod_y, pod_w, pod_h)
    draw_ai_pod(4, pad_x + (pod_w + pod_gap) * 2, pod_y, pod_w, pod_h)

    -- Pot & Call Status Pill
    local pot_box_y = pod_y + pod_h + 22
    local pot_box_h = 68
    cv:rect(pad_x, pot_box_y, W - pad_x * 2, pot_box_h, COL_FELT_DARK, true, 10)
    cv:rect(pad_x, pot_box_y, W - pad_x * 2, pot_box_h, COL_FELT_LINE, false, 10)

    local pot_str = string.format("TOTAL POT: $%d", I(pot))
    cv:text(pad_x + 18, pot_box_y + I((pot_box_h - L.lh_xl) / 2), pot_str, COL_GOLD, L.f_xl)

    local to_call = I(math.max(0, cur_bet - seats[1].street_bet))
    local call_str = (state == "done")
      and "HAND COMPLETE"
      or (to_call > 0 and string.format("TO CALL: $%d", to_call) or "CHECK AVAILABLE")
    cv:text(W - pad_x - text_w(call_str, L.f_md) - 18, pot_box_y + I((pot_box_h - L.lh_md) / 2), call_str, C.accent, L.f_md)

    -- 5 Community Card Slots centered horizontally
    local cc_w, cc_h, cc_gap = L.cc_w, L.cc_h, L.cc_gap
    local cc_total_w = cc_w * 5 + cc_gap * 4
    local cc_start_x = I((W - cc_total_w) / 2)
    local cc_y = pot_box_y + pot_box_h + 24

    for i = 1, 5 do
      local cx = cc_start_x + (i - 1) * (cc_w + cc_gap)
      if board[i] then
        draw_card_box(cx, cc_y, cc_w, cc_h, board[i], false)
      else
        cv:rect(cx, cc_y, cc_w, cc_h, COL_FELT_DARK, true, 8)
        cv:rect(cx, cc_y, cc_w, cc_h, COL_FELT_LINE, false, 8)
      end
    end

    -- Player Section at Bottom
    local p = seats[1]
    local p_info_h = 98
    local p_info_y = top_h + table_h - p_info_h - 16
    local p_cards_y = p_info_y - L.p_ch - 18

    -- Dedicated middle strip between Community Cards and Player Hole Cards for Outcome Banner
    local mid_top = cc_y + cc_h + 12
    local mid_bot = p_cards_y - 12
    local mid_cy  = I((mid_top + mid_bot) / 2)

    if state == "done" and banner_title ~= "" then
      local bw = W - pad_x * 2 - 24
      local bh = L.lh_xl + L.lh_md + 28
      local bx = I((W - bw) / 2)
      local by = I(mid_cy - bh / 2)
      cv:rect(bx, by, bw, bh, 0x0D131A, true, 10)
      cv:rect(bx, by, bw, bh, banner_col, false, 10)
      cv:text(I((W - text_w(banner_title, L.f_xl)) / 2), by + 8, banner_title, banner_col, L.f_xl)
      cv:text(I((W - text_w(banner_sub, L.f_md)) / 2), by + 12 + L.lh_xl, banner_sub, C.text, L.f_md)
    else
      cv:line(pad_x + 24, mid_cy, W - pad_x - 24, mid_cy, COL_FELT_LINE, 1)
    end

    -- Player's 2 Hole Cards centered
    if #p.cards == 2 then
      local hc_gap = 18
      local hc_x1 = I(W / 2 - L.p_cw - hc_gap / 2)
      local hc_x2 = I(W / 2 + hc_gap / 2)
      draw_card_box(hc_x1, p_cards_y, L.p_cw, L.p_ch, p.cards[1], false)
      draw_card_box(hc_x2, p_cards_y, L.p_cw, L.p_ch, p.cards[2], false)
    end

    -- Player HUD Box below Hole Cards
    cv:rect(pad_x, p_info_y, W - pad_x * 2, p_info_h, COL_POD_BG, true, 10)
    cv:rect(pad_x, p_info_y, W - pad_x * 2, p_info_h, state == "player" and C.accent or 0x22303C, false, 10)

    local you_hdr = p.role ~= "" and string.format("YOU [%s]  ·  STREET BET: $%d", p.role, I(p.street_bet)) or string.format("YOU  ·  STREET BET: $%d", I(p.street_bet))
    cv:text(pad_x + 16, p_info_y + 10, you_hdr, C.text, L.f_md)

    local _, _, hname = eval_best_hand(p.cards, board)
    local h_str = p.folded and "FOLDED" or hname
    cv:text(W - pad_x - text_w(h_str, L.f_md) - 16, p_info_y + 10, h_str, p.folded and C.bad or COL_GOLD, L.f_md)

    local line2 = (state == "player")
      and string.format("RAISE TARGET: $%d   (Tap +BB or Up/Down)", I(raise_to))
      or (p.status ~= "" and ("STATUS: " .. p.status) or "WAITING FOR TABLE...")
    cv:text(pad_x + 16, p_info_y + 14 + L.lh_md, line2, C.accent, L.f_sm)

    local line3 = "Touch action buttons below  ·  Tap table after hand to deal"
    cv:text(pad_x + 16, p_info_y + 18 + L.lh_md + L.lh_sm, line3, C.sub, L.f_sm)

  elseif DEV.portrait then
    -- Compact Portrait Layout (Heltec V4 240x244)
    local pod_y = top_h + 4
    local pod_w = I((W - 16) / 3)
    draw_ai_pod(2, 4, pod_y, pod_w, 40)
    draw_ai_pod(3, 4 + pod_w + 4, pod_y, pod_w, 40)
    draw_ai_pod(4, 4 + (pod_w + 4) * 2, pod_y, pod_w, 40)

    local strip_y = pod_y + 43
    local to_call = I(math.max(0, cur_bet - seats[1].street_bet))
    local pot_line = string.format("POT $%d   ·   %s", I(pot), to_call > 0 and string.format("CALL $%d", to_call) or "CHECK OK")
    cv:text(I((W - text_w(pot_line, L.f_sm)) / 2), strip_y, pot_line, COL_GOLD, L.f_sm)

    local cc_w, cc_h, cc_gap = L.cc_w, L.cc_h, L.cc_gap
    local cc_total_w = cc_w * 5 + cc_gap * 4
    local cc_start_x = I((W - cc_total_w) / 2)
    local cc_y = strip_y + 16
    for i = 1, 5 do
      local cx = cc_start_x + (i - 1) * (cc_w + cc_gap)
      if board[i] then
        draw_card_box(cx, cc_y, cc_w, cc_h, board[i], false)
      else
        cv:rect(cx, cc_y, cc_w, cc_h, COL_FELT_DARK, true, 3)
        cv:rect(cx, cc_y, cc_w, cc_h, COL_FELT_LINE, false, 3)
      end
    end

    local py = cc_y + cc_h + 6
    local p = seats[1]
    if #p.cards == 2 then
      draw_card_box(6, py, L.p_cw, L.p_ch, p.cards[1], false)
      draw_card_box(34, py, L.p_cw, L.p_ch, p.cards[2], false)
    end

    local info_x = 74
    local info_w = W - info_x - 4
    if state == "done" and banner_title ~= "" then
      cv:rect(info_x, py, info_w, L.p_ch, 0x0D131A, true, 5)
      cv:rect(info_x, py, info_w, L.p_ch, banner_col, false, 5)
      cv:text(info_x + I((info_w - text_w(banner_title, L.f_md)) / 2), py + 6, banner_title, banner_col, L.f_md)
      cv:text(info_x + I((info_w - text_w(banner_sub, L.f_xs)) / 2), py + 24, banner_sub, C.text, L.f_xs)
    else
      cv:rect(info_x, py, info_w, L.p_ch, COL_POD_BG, true, 5)
      cv:rect(info_x, py, info_w, L.p_ch, state == "player" and C.accent or 0x22303C, false, 5)
      local _, _, hname = eval_best_hand(p.cards, board)
      cv:text(info_x + 4, py + 4, p.folded and "FOLDED" or hname, COL_GOLD, L.f_xs)
      cv:text(info_x + 4, py + 18, string.format("BET $%d  R:$%d", I(p.street_bet), I(raise_to)), C.accent, L.f_xs)
      cv:text(info_x + 4, py + 31, p.status ~= "" and p.status or "YOUR TURN", C.sub, L.f_xs)
    end

  else
    -- Landscape Table Layout (LilyGo T-Deck 320x208, T-Display P4 Landscape, T-LoRa Pager)
    local v_pad = DEV.scale >= 2 and 12 or 4
    local h_pad = DEV.scale >= 2 and 16 or 6
    local pod_gap = DEV.scale >= 2 and 12 or 4
    local pod_y = top_h + v_pad
    local pod_h = DEV.scale >= 2 and I(table_h * 0.27) or 40
    local pod_w = I((W - h_pad * 2 - pod_gap * 2) / 3)

    draw_ai_pod(2, h_pad, pod_y, pod_w, pod_h)
    draw_ai_pod(3, h_pad + pod_w + pod_gap, pod_y, pod_w, pod_h)
    draw_ai_pod(4, h_pad + (pod_w + pod_gap) * 2, pod_y, pod_w, pod_h)

    -- 2. Middle Row: Pot Info Box (Left) + 5 Community Cards (Right)
    local mid_y = pod_y + pod_h + v_pad
    local cc_w, cc_h, cc_gap = L.cc_w, L.cc_h, L.cc_gap
    local cc_total_w = cc_w * 5 + cc_gap * 4
    local cc_start_x = W - h_pad - cc_total_w
    local pot_w = math.max(DEV.scale >= 2 and 220 or 92, cc_start_x - h_pad - (DEV.scale >= 2 and 16 or 6))

    cv:rect(h_pad, mid_y, pot_w, cc_h, COL_FELT_DARK, true, DEV.scale >= 2 and 8 or 5)
    cv:rect(h_pad, mid_y, pot_w, cc_h, COL_FELT_LINE, false, DEV.scale >= 2 and 8 or 5)
    local p_tx = h_pad + (DEV.scale >= 2 and 14 or 5)
    cv:text(p_tx, mid_y + (DEV.scale >= 2 and 8 or 4), "TOTAL POT", C.sub, L.f_xs)
    cv:text(p_tx, mid_y + (DEV.scale >= 2 and (10 + L.lh_xs) or 16), string.format("$%d", I(pot)), COL_GOLD, L.f_lg)

    local to_call = I(math.max(0, cur_bet - seats[1].street_bet))
    local call_info = (state == "done")
      and "HAND OVER"
      or (to_call > 0 and string.format("TO CALL: $%d", to_call) or "CHECK OK")
    cv:text(p_tx, mid_y + cc_h - L.lh_xs - (DEV.scale >= 2 and 8 or 3), call_info, C.accent, L.f_xs)

    for i = 1, 5 do
      local cx = cc_start_x + (i - 1) * (cc_w + cc_gap)
      if board[i] then
        draw_card_box(cx, mid_y, cc_w, cc_h, board[i], false)
      else
        cv:rect(cx, mid_y, cc_w, cc_h, COL_FELT_DARK, true, DEV.scale >= 2 and 8 or 3)
        cv:rect(cx, mid_y, cc_w, cc_h, COL_FELT_LINE, false, DEV.scale >= 2 and 8 or 3)
      end
    end

    -- 3. Bottom Player Row
    local py = mid_y + cc_h + v_pad
    local p = seats[1]
    local hc_overlap = DEV.scale >= 2 and I(L.p_cw * 0.82) or 30

    if #p.cards == 2 then
      draw_card_box(h_pad + 2, py, L.p_cw, L.p_ch, p.cards[1], false)
      draw_card_box(h_pad + 2 + hc_overlap, py, L.p_cw, L.p_ch, p.cards[2], false)
    end

    local info_x = h_pad + 2 + hc_overlap + L.p_cw + (DEV.scale >= 2 and 16 or 7)
    local info_w = W - info_x - h_pad
    local info_h = L.p_ch - (DEV.scale >= 2 and 0 or 4)
    local info_y = py + (DEV.scale >= 2 and 0 or 2)

    if state == "done" and banner_title ~= "" then
      cv:rect(info_x, info_y, info_w, info_h, 0x0D131A, true, 6)
      cv:rect(info_x, info_y, info_w, info_h, banner_col, false, 6)
      local ty1 = info_y + I((info_h - (L.lh_lg + L.lh_sm)) / 2)
      cv:text(info_x + I((info_w - text_w(banner_title, L.f_lg)) / 2), ty1, banner_title, banner_col, L.f_lg)
      cv:text(info_x + I((info_w - text_w(banner_sub, L.f_sm)) / 2), ty1 + L.lh_lg + 2, banner_sub, C.text, L.f_sm)
    else
      cv:rect(info_x, info_y, info_w, info_h, COL_POD_BG, true, 5)
      local p_border = (state == "player") and C.accent or 0x22303C
      cv:rect(info_x, info_y, info_w, info_h, p_border, false, 5)

      local pad_in = DEV.scale >= 2 and 14 or 6
      local you_hdr = p.role ~= "" and string.format("YOU [%s]  BET $%d", p.role, I(p.street_bet)) or string.format("YOU  BET $%d", I(p.street_bet))
      cv:text(info_x + pad_in, info_y + (DEV.scale >= 2 and 8 or 3), you_hdr, C.text, L.f_sm)

      local _, _, hname = eval_best_hand(p.cards, board)
      local h_str = p.folded and "FOLDED" or hname
      cv:text(info_x + info_w - text_w(h_str, L.f_sm) - pad_in, info_y + (DEV.scale >= 2 and 8 or 3), h_str, p.folded and C.bad or COL_GOLD, L.f_sm)

      local line2 = (state == "player")
        and string.format("RAISE TARGET: $%d  [Up/Down]", I(raise_to))
        or (p.status ~= "" and ("STATUS: " .. p.status) or "WAITING FOR TABLE...")
      cv:text(info_x + pad_in, info_y + I((info_h - L.lh_xs) / 2) + 1, line2, C.accent, L.f_xs)

      local line3 = "[F]Fold  [C]Call/Chk  [R]Raise  [A]All-In"
      cv:text(info_x + pad_in, info_y + info_h - L.lh_xs - (DEV.scale >= 2 and 6 or 1), line3, C.sub, L.f_xs)
    end
  end

  -- Bottom button bar
  local by = H - bot_h
  cv:rect(0, by, W, bot_h, COL_BOTBAR, true)
  cv:line(0, by, W, by, 0x1F2933, 1)

  local nb = #active_btns
  if nb > 0 then
    local gap = L.btn_gap
    local pad_v = DEV.scale >= 2 and 8 or 3
    local bw = I((W - gap * (nb + 1)) / nb)
    local bh = bot_h - pad_v * 2
    local btn_fsz = DEV.scale >= 2 and L.f_md or L.f_sm
    local btn_lh  = text_h(btn_fsz)
    local btn_rad = DEV.scale >= 2 and 8 or 4

    for i = 1, nb do
      local b = active_btns[i]
      local bx = gap + (i - 1) * (bw + gap)
      local bby = by + pad_v
      b.x, b.y, b.w, b.h = bx, bby, bw, bh

      local bg = not b.enabled and COL_BTN_DIS or (b.primary and COL_BTN_ACT or COL_BTN)
      cv:rect(bx, bby, bw, bh, bg, true, btn_rad)

      if i == focus_idx and b.enabled then
        cv:rect(bx, bby, bw, bh, b.primary and COL_GOLD or C.accent, false, btn_rad)
      elseif b.enabled then
        cv:rect(bx, bby, bw, bh, 0x2B3642, false, btn_rad)
      end

      local tcol = not b.enabled and COL_TEXT_DIM or (b.primary and COL_GOLD or C.text)
      local lbl = b.label
      local tw = text_w(lbl, btn_fsz)
      if tw > bw - 6 and lbl:find(" %[") then
        lbl = lbl:gsub(" %[.*%]", "")
        tw = text_w(lbl, btn_fsz)
      end
      local tx = bx + math.max(2, I((bw - tw) / 2))
      local ty = bby + math.max(1, I((bh - btn_lh) / 2))
      cv:text(tx, ty, lbl, tcol, btn_fsz)
    end
  end
end

local function cycle_focus(dir)
  local n = #active_btns
  if n == 0 then return end
  for _ = 1, n do
    focus_idx = ((focus_idx - 1 + dir) % n) + 1
    if active_btns[focus_idx] and active_btns[focus_idx].enabled then
      break
    end
  end
  draw_screen()
end

local function trigger_focused()
  local b = active_btns[focus_idx]
  if b and b.enabled and b.fn then
    b.fn()
  end
end

-- WADAMESH Lifecycle Callbacks
function app.on_open(w, h)
  local brd = (sys.board and sys.board()) or {}
  W = I((w and w > 0) and w or ((brd.w and brd.w > 0) and brd.w or 320))
  H = I((h and h > 0) and h or ((brd.h and brd.h > 0) and brd.h or 208))

  compute_layout()

  seats[1].stack = I(tonumber(store.get("he_bank", START_STACK)) or START_STACK)
  best_bank      = I(tonumber(store.get("he_best", START_STACK)) or START_STACK)
  hands_won      = I(tonumber(store.get("he_wins", 0)) or 0)
  hands_played   = I(tonumber(store.get("he_hands", 0)) or 0)
  blind_idx      = I(clamp(tonumber(store.get("he_blind", 1)) or 1, 1, #BLIND_LEVELS))

  local _, bb = get_blinds()
  if seats[1].stack < bb then seats[1].stack = START_STACK end
  for i = 2, 4 do seats[i].stack = START_STACK end

  cv = create_screen_canvas(W, H)

  build_deck()
  state = "title"
  rebuild_buttons()
  draw_screen()
end

function app.on_tick(dt)
  if state ~= "ai" then
    timer.stop()
    return
  end

  local active, can_act = count_players()
  if active <= 1 then
    resolve_hand(true)
    return
  end

  if can_act < 2 then
    next_street_or_showdown()
    return
  end

  local p = seats[turn_seat]
  if p and not p.is_human and not p.folded and not p.all_in then
    ai_decide(turn_seat)
  else
    advance_turn()
  end
end

function app.on_input(ev)
  if not ev then return end

  if ev.type == "down" then
    local ex, ey = tonumber(ev.x) or 0, tonumber(ev.y) or 0
    for i = 1, #active_btns do
      local b = active_btns[i]
      if b.x and ex >= b.x and ex <= b.x + b.w and ey >= b.y and ey <= b.y + b.h then
        if b.enabled and b.fn then
          focus_idx = i
          b.fn()
        end
        return
      end
    end
    if ey <= L.top_h and ex >= W - I(W * 0.28) then
      sound_on = not sound_on
      sys.toast(sound_on and "Sound ON" or "Sound OFF")
      draw_screen()
      return
    end
    if state == "ai" then
      app.on_tick(0)
      return
    end
    if (state == "done" or state == "title") and ey > L.top_h + 2 and ey < H - L.bot_h - 2 then
      start_hand()
      return
    end

  elseif ev.type == "swipe" then
    local _, bb = get_blinds()
    local d = ev.dir
    if d == "left" then
      cycle_focus(-1)
    elseif d == "right" then
      cycle_focus(1)
    elseif d == "up" then
      if state == "player" then adjust_raise(bb) end
    elseif d == "down" then
      if state == "player" then adjust_raise(-bb) end
    end

  elseif ev.type == "key" then
    local _, bb = get_blinds()
    local k = tostring(ev.key or ""):lower()
    if state == "ai" then
      app.on_tick(0)
      return
    end
    if k == "left" then
      cycle_focus(-1)
    elseif k == "right" or k == "l" then
      cycle_focus(1)
    elseif k == "up" or k == "w" or k == "+" or k == "=" then
      if state == "player" then adjust_raise(bb) end
    elseif k == "down" or k == "z" or k == "-" then
      if state == "player" then adjust_raise(-bb) end
    elseif k == "enter" or k == " " then
      trigger_focused()
    elseif k == "m" then
      sound_on = not sound_on
      sys.toast(sound_on and "Sound ON" or "Sound OFF")
      draw_screen()
    elseif state == "player" then
      if k == "f" then perform_action(1, "fold")
      elseif k == "c" then perform_action(1, "call")
      elseif k == "r" then
        if seats[1].stack > (cur_bet - seats[1].street_bet) then
          perform_action(1, "raise", raise_to)
        end
      elseif k == "a" then perform_action(1, "allin")
      end
    elseif state == "done" or state == "title" then
      if k == "d" or k == "h" then start_hand()
      elseif k == "b" then cycle_blinds()
      elseif k == "n" then reset_table()
      end
    end
  end
end

function app.on_close()
  save_stats()
end

return app
