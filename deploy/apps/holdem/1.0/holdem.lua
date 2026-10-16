-- Texas Hold'em Poker — WADAMESH Lua app for LilyGo T-Deck & MeshCore boards
-- No-Limit 4-Max Table (You vs. 3 AI Bots: TEX, VIPER, DUKE)
-- Controls:
--   Touch:     Tap any bottom-bar button, tap during AI turn to fast-forward, tap table after hand to deal
--   Keyboard:  [F] Fold  [C] Check/Call  [R] Bet/Raise  [A] All-In  [D/H] Deal
--              [W/Up/+] Increase Raise  [Z/Down/-] Decrease Raise  [B] Cycle Blinds  [N] New Table  [M] Mute
--   Trackball: Left/Right cycle buttons, Up/Down adjust raise size, Click to activate focused button

local ui, sys, store, timer = wada.ui, wada.sys, wada.store, wada.timer
local C = ui.colors

local app = {}

-- Screen & canvas state
local W, H = 320, 208
local cv

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

-- Build & shuffle a single 52-card deck
local function build_deck()
  deck = {}
  local idx = 1
  for s = 1, 4 do
    for r = 1, 13 do
      deck[idx] = { r = r, s = s }
      idx = idx + 1
    end
  end
  for i = #deck, 2, -1 do
    local j = rand_int(1, i)
    deck[i], deck[j] = deck[j], deck[i]
  end
end

local function draw_card()
  if #deck == 0 then build_deck() end
  local c = deck[#deck]
  deck[#deck] = nil
  return c
end

-- Convert internal rank (1=Ace, 2..13=2..K) to poker value (2..14, where 14=Ace)
local function pval(r)
  return r == 1 and 14 or r
end

-- Fast O(13) 5-to-7 card Poker Hand Evaluator
-- Returns: score (32-bit safe integer < 10,000,000), category (0..9), short_name
local function eval_best_hand( hole, comm )
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
      local paid = post_chips(idx, need)
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
      -- Everyone else who is still active and not all-in must act again
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

  -- Check if only 1 player remains
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

  -- Estimate hand strength 0..100
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

  -- Personality adjustments
  local roll = rand_int(1, 100)
  if p.style == "loose" then
    strength = strength + 10
  elseif p.style == "lag" then
    strength = strength + (roll > 65 and 18 or 4)
  elseif p.style == "tag" then
    strength = strength + (street > 0 and cat >= 1 and 8 or -3)
  end

  if to_call <= 0 then
    -- Can check or bet
    if strength >= 58 and p.stack > bb and roll <= 70 then
      local bet_sz = I(math.min(p.street_bet + p.stack, math.max(bb, I(pot * 0.5))))
      perform_action(idx, "raise", bet_sz)
    else
      perform_action(idx, "call")
    end
  else
    -- Facing a bet
    local pot_odds_penalty = I((to_call * 45) / math.max(bb, pot))
    local eff = strength - pot_odds_penalty
    if to_call >= p.stack then
      -- Facing all-in
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
        -- If everyone else is all-in and this player has already matched cur_bet, no further action needed
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

  -- Betting round complete!
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
  local active, can_act = count_players()
  -- If fewer than 2 players can make bets (e.g. all-in runout), deal remaining streets automatically
  if can_act < 2 then
    show_all_cards = true
    state = "ai"
    rebuild_buttons()
    draw_screen()
    timer.every(520)
    return
  end

  -- Post-flop action starts first active seat left of Dealer
  turn_seat = dealer_seat
  advance_turn()
end

-- Settle pot (with full side-pot & split-pot support)
resolve_hand = function(by_fold)
  timer.stop()
  state = "done"
  street = 4

  if by_fold then
    -- Single remaining non-folded player wins entire pot uncontested
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
      banner_sub = string.format("+$%d (Opponents Folded)", pot)
      banner_col = C.good
    else
      banner_title = seats[winner].name .. " WINS"
      banner_sub = string.format("Pot $%d (Folded)", pot)
      banner_col = C.accent
    end
    pot = 0
    save_stats()
    rebuild_buttons()
    draw_screen()
    return
  end

  -- Showdown: evaluate all non-folded hands
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

  -- Side-pot / main-pot slice distribution by total_bet levels
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

    -- Any uncalled residual chips above highest non-folded bettor go back
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
    banner_title = string.format("YOU WIN $%d!", won_amt[1])
    banner_sub = hnames[1] or "BEST HAND"
    banner_col = COL_GOLD
  else
    local w = best_overall_winner
    banner_title = string.format("%s WINS $%d", seats[w].name, won_amt[w])
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

  -- Top up human or AI bots if busted
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

  -- Rotate dealer button
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
  seats[sb_seat].status = string.format("SB $%d", seats[sb_seat].street_bet)

  post_chips(bb_seat, bb)
  seats[bb_seat].status = string.format("BB $%d", seats[bb_seat].street_bet)

  cur_bet = bb
  min_raise = bb
  raise_to = bb * 2
  last_aggressor = bb_seat

  sfx()
  -- Pre-flop action starts Under-the-Gun (left of BB)
  turn_seat = bb_seat
  advance_turn()
end

-- Adjust player raise target
local function adjust_raise(delta)
  if state ~= "player" then return end
  raise_to = I(raise_to + delta)
  sync_raise_bounds()
  sfx()
  rebuild_buttons()
  draw_screen()
end

-- Cycle blind levels ($5/$10, $10/$20, $25/$50)
local function cycle_blinds()
  blind_idx = (blind_idx % #BLIND_LEVELS) + 1
  local sb, bb = get_blinds()
  sys.toast(string.format("Blinds: $%d / $%d", sb, bb))
  sfx()
  save_stats()
  rebuild_buttons()
  draw_screen()
end

-- Reset entire table stacks to $500
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

  if state == "title" then
    active_btns = {
      { label = string.format("BLINDS $%d/$%d", sb, bb), key = "b", enabled = true, fn = cycle_blinds },
      { label = "RESET $500", key = "n", enabled = true, fn = reset_table },
      { label = "DEAL HOLD'EM [D]", key = "d", primary = true, enabled = true, fn = start_hand },
    }
    focus_idx = 3
  elseif state == "player" then
    local p = seats[1]
    local to_call = I(math.max(0, cur_bet - p.street_bet))
    local can_raise = (p.stack > to_call)
    sync_raise_bounds()

    local call_lbl
    if to_call <= 0 then
      call_lbl = "CHECK [C]"
    elseif to_call >= p.stack then
      call_lbl = string.format("ALL-IN $%d", p.stack)
    else
      call_lbl = string.format("CALL $%d", to_call)
    end

    local raise_lbl = (cur_bet == 0)
      and string.format("BET $%d", raise_to)
      or string.format("RAISE $%d", raise_to)

    active_btns = {
      { label = "FOLD [F]", key = "f", enabled = true, fn = function() perform_action(1, "fold") end },
      { label = call_lbl,   key = "c", primary = true, enabled = true, fn = function() perform_action(1, "call") end },
      { label = raise_lbl,  key = "r", enabled = can_raise, fn = function() perform_action(1, "raise", raise_to) end },
      { label = "+BB",      key = "+", enabled = can_raise, fn = function()
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
      { label = "ALL-IN",   key = "a", enabled = p.stack > 0, fn = function() perform_action(1, "allin") end },
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
      { label = "NEW TBL [N]", key = "n", enabled = true, fn = reset_table },
      { label = "NEXT HAND [D]", key = "d", primary = true, enabled = true, fn = start_hand },
    }
    focus_idx = 3
  end
end

-- Crisp solid-rect suit pip renderer for LVGL canvas
local function draw_suit_pip(x, y, suit, scale)
  x, y = I(x), I(y)
  local col = (suit == 2 or suit == 3) and COL_RED or COL_BLACK
  if scale == "mini" then
    if suit == 1 then -- Spade
      cv:rect(x, y - 2, 1, 1, col, true)
      cv:rect(x - 1, y - 1, 3, 1, col, true)
      cv:rect(x - 2, y, 5, 2, col, true)
      cv:rect(x, y + 2, 1, 2, col, true)
    elseif suit == 2 then -- Heart
      cv:rect(x - 2, y - 2, 2, 1, col, true)
      cv:rect(x + 1, y - 2, 2, 1, col, true)
      cv:rect(x - 2, y - 1, 5, 2, col, true)
      cv:rect(x - 1, y + 1, 3, 1, col, true)
      cv:rect(x, y + 2, 1, 1, col, true)
    elseif suit == 3 then -- Diamond
      cv:rect(x, y - 2, 1, 1, col, true)
      cv:rect(x - 1, y - 1, 3, 1, col, true)
      cv:rect(x - 2, y, 5, 1, col, true)
      cv:rect(x - 1, y + 1, 3, 1, col, true)
      cv:rect(x, y + 2, 1, 1, col, true)
    else -- Club
      cv:rect(x - 1, y - 2, 3, 2, col, true)
      cv:rect(x - 2, y, 5, 2, col, true)
      cv:rect(x, y + 2, 1, 2, col, true)
    end
  elseif scale == "small" then
    if suit == 1 then -- Spade
      cv:rect(x, y - 3, 1, 1, col, true)
      cv:rect(x - 1, y - 2, 3, 1, col, true)
      cv:rect(x - 2, y - 1, 5, 1, col, true)
      cv:rect(x - 3, y, 7, 2, col, true)
      cv:rect(x - 1, y + 2, 3, 2, col, true)
    elseif suit == 2 then -- Heart
      cv:rect(x - 2, y - 2, 2, 1, col, true)
      cv:rect(x + 1, y - 2, 2, 1, col, true)
      cv:rect(x - 3, y - 1, 7, 2, col, true)
      cv:rect(x - 2, y + 1, 5, 1, col, true)
      cv:rect(x - 1, y + 2, 3, 1, col, true)
      cv:rect(x, y + 3, 1, 1, col, true)
    elseif suit == 3 then -- Diamond
      for dy = -3, 3 do
        local hw = 3 - math.abs(dy)
        cv:rect(x - hw, y + dy, hw * 2 + 1, 1, col, true)
      end
    else -- Club
      cv:circle(x, y - 2, 1, col, true)
      cv:circle(x - 2, y, 1, col, true)
      cv:circle(x + 2, y, 1, col, true)
      cv:rect(x - 1, y, 3, 4, col, true)
    end
  else -- "large" center pip
    if suit == 1 then -- Spade
      for dy = -5, 1 do
        local hw = I((dy + 5) * 0.85)
        cv:rect(x - hw, y + dy, hw * 2 + 1, 1, col, true)
      end
      cv:circle(x - 2, y + 1, 2, col, true)
      cv:circle(x + 2, y + 1, 2, col, true)
      cv:rect(x - 1, y + 2, 3, 4, col, true)
    elseif suit == 2 then -- Heart
      cv:circle(x - 3, y - 2, 2, col, true)
      cv:circle(x + 3, y - 2, 2, col, true)
      for dy = -1, 5 do
        local hw = math.max(0, 5 - dy)
        cv:rect(x - hw, y + dy, hw * 2 + 1, 1, col, true)
      end
    elseif suit == 3 then -- Diamond
      for dy = -5, 5 do
        local hw = 5 - math.abs(dy)
        cv:rect(x - hw, y + dy, hw * 2 + 1, 1, col, true)
      end
    else -- Club
      cv:circle(x, y - 3, 2, col, true)
      cv:circle(x - 3, y + 1, 2, col, true)
      cv:circle(x + 3, y + 1, 2, col, true)
      cv:rect(x - 1, y, 3, 6, col, true)
    end
  end
end

-- Draw a playing card at (x, y) of size (cw, ch)
local function draw_card_box(x, y, cw, ch, card, hidden)
  x, y, cw, ch = I(x), I(y), I(cw), I(ch)
  cv:rect(x + 1, y + 1, cw, ch, COL_CARD_SHAD, true, 3)

  if hidden or not card then
    cv:rect(x, y, cw, ch, COL_CARD_BG, true, 3)
    cv:rect(x + 1, y + 1, cw - 2, ch - 2, COL_CARD_BACK, true, 2)
    if cw >= 26 then
      cv:rect(x + 3, y + 3, cw - 6, ch - 6, COL_CARD_TRIM, false, 2)
      cv:circle(I(x + cw / 2), I(y + ch / 2), 4, COL_GOLD, false)
    end
    return
  end

  cv:rect(x, y, cw, ch, COL_CARD_BG, true, 3)
  cv:rect(x, y, cw, ch, 0xCBD2D9, false, 3)

  local col = (card.s == 2 or card.s == 3) and COL_RED or COL_BLACK
  local rstr = RANKS[card.r]

  if cw <= 22 then
    -- Compact mini card (for AI showdown hole cards)
    cv:text(x + 2, y + 1, rstr, col, 10)
    draw_suit_pip(x + I(cw / 2), y + ch - 7, card.s, "mini")
  else
    cv:text(x + 3, y + 2, rstr, col, 12)
    if cw >= 32 then
      draw_suit_pip(x + cw - 7, y + 8, card.s, "small")
    end
    draw_suit_pip(x + I(cw / 2), y + I(ch / 2) + 5, card.s, "large")
  end
end

-- Render one AI opponent pod at (px, py, pw, ph)
local function draw_ai_pod(idx, px, py, pw, ph)
  px, py, pw, ph = I(px), I(py), I(pw), I(ph)
  local p = seats[idx]
  local is_turn = (state == "ai" and turn_seat == idx)
  local bg = p.folded and COL_POD_FOLD or COL_POD_BG
  local border = is_turn and COL_GOLD or (p.status == "WIN!" and C.good or 0x22303C)

  cv:rect(px, py, pw, ph, bg, true, 5)
  cv:rect(px, py, pw, ph, border, false, 5)

  -- Name & role badge (D / SB / BB)
  local head = p.role ~= "" and (p.name .. "·" .. p.role) or p.name
  local ncol = p.folded and COL_TEXT_DIM or (is_turn and COL_GOLD or C.text)
  cv:text(px + 4, py + 2, head, ncol, 10)

  -- Stack
  local scol = p.folded and COL_TEXT_DIM or COL_GOLD
  cv:text(px + 4, py + 14, string.format("$%d", I(p.stack)), scol, 11)

  -- Action / Hand status
  local st = p.status ~= "" and p.status or (p.all_in and "ALL-IN" or "WAIT")
  local st_col = p.folded and COL_TEXT_DIM
    or (p.status == "WIN!" and C.good or (is_turn and C.accent or C.sub))
  cv:text(px + 4, py + 27, st, st_col, 10)

  -- Hole cards on right side of pod
  if #p.cards == 2 and not p.folded then
    local reveal = show_all_cards
    if reveal then
      draw_card_box(px + pw - 39, py + 4, 18, 25, p.cards[1], false)
      draw_card_box(px + pw - 20, py + 4, 18, 25, p.cards[2], false)
    else
      draw_card_box(px + pw - 33, py + 5, 15, 22, p.cards[1], true)
      draw_card_box(px + pw - 20, py + 5, 15, 22, p.cards[2], true)
    end
  end
end

-- Render full screen
draw_screen = function()
  local top_h = 20
  local bot_h = 30
  local table_h = H - top_h - bot_h
  local sb, bb = get_blinds()

  cv:fill(COL_FELT)
  cv:rect(3, top_h + 2, W - 6, table_h - 4, COL_FELT_LINE, false, 7)

  -- Top bar
  cv:rect(0, 0, W, top_h, COL_TOPBAR, true)
  cv:line(0, top_h, W, top_h, 0x1F2933, 1)

  cv:text(6, 3, string.format("STACK $%d", I(seats[1].stack)), COL_GOLD, 12)

  local mid_top_str = (state == "title")
    and string.format("BLINDS $%d/$%d", sb, bb)
    or string.format("%s · $%d/$%d", STREET_NAMES[street] or "HOLD'EM", sb, bb)
  cv:text(I((W - ui.text_w(mid_top_str, 11)) / 2), 4, mid_top_str, C.accent, 11)

  local pk_str = string.format("PEAK $%d%s", I(best_bank), sound_on and "" or "[M]")
  cv:text(W - ui.text_w(pk_str, 11) - 6, 4, pk_str, C.sub, 11)

  if state == "title" then
    local pad_x = 12
    local box_w = W - pad_x * 2
    cv:rect(pad_x, top_h + 8, box_w, table_h - 16, COL_FELT_DARK, true, 8)
    cv:rect(pad_x, top_h + 8, box_w, table_h - 16, COL_FELT_LINE, false, 8)

    -- Royal Flush Aces & Kings flanking the title in clear zones
    draw_card_box(pad_x + 10, top_h + 18, 32, 44, { r = 1, s = 1 }, false)
    draw_card_box(W - pad_x - 42, top_h + 18, 32, 44, { r = 1, s = 2 }, false)

    local t1 = "TEXAS HOLD'EM"
    cv:text(I((W - ui.text_w(t1, 16)) / 2), top_h + 18, t1, COL_GOLD, 16)

    local t2 = "No-Limit 4-Max  ·  3 AI Opponents"
    cv:text(I((W - ui.text_w(t2, 11)) / 2), top_h + 42, t2, C.sub, 11)

    local pill = string.format("BLINDS: $%d / $%d   BUY-IN: $%d", sb, bb, I(seats[1].stack))
    local pw = ui.text_w(pill, 12)
    local py = top_h + 74
    cv:rect(I((W - pw) / 2) - 10, py, pw + 20, 24, COL_BTN_ACT, true, 5)
    cv:rect(I((W - pw) / 2) - 10, py, pw + 20, 24, C.accent, false, 5)
    cv:text(I((W - pw) / 2), py + 5, pill, C.text, 12)

    local hint = "Tap [DEAL HOLD'EM] or press [D] to play"
    cv:text(I((W - ui.text_w(hint, 11)) / 2), top_h + table_h - 25, hint, C.sub, 11)
  else
    -- 1. Top Row: 3 AI Opponent Pods (y = 24..64)
    local pod_y = top_h + 4
    local pod_w = I((W - 20) / 3)
    draw_ai_pod(2, 6, pod_y, pod_w, 40)
    draw_ai_pod(3, 6 + pod_w + 4, pod_y, pod_w, 40)
    draw_ai_pod(4, 6 + (pod_w + 4) * 2, pod_y, pod_w, 40)

    -- 2. Middle Row: Pot Info Box (Left) + 5 Community Cards (Right) (y = 68..118)
    local mid_y = top_h + 48
    local pot_w = 94
    cv:rect(6, mid_y, pot_w, 48, COL_FELT_DARK, true, 5)
    cv:rect(6, mid_y, pot_w, 48, COL_FELT_LINE, false, 5)
    cv:text(11, mid_y + 4, "TOTAL POT", C.sub, 10)
    cv:text(11, mid_y + 16, string.format("$%d", I(pot)), COL_GOLD, 14)

    local to_call = I(math.max(0, cur_bet - seats[1].street_bet))
    local call_info = (state == "done")
      and "HAND OVER"
      or (to_call > 0 and string.format("TO CALL: $%d", to_call) or "CHECK OK")
    cv:text(11, mid_y + 34, call_info, C.accent, 10)

    -- 5 Community Card Slots (x = 106..314)
    local cc_w = 37
    local cc_h = 48
    local cc_gap = 5
    local cc_start_x = 106
    for i = 1, 5 do
      local cx = cc_start_x + (i - 1) * (cc_w + cc_gap)
      if board[i] then
        draw_card_box(cx, mid_y, cc_w, cc_h, board[i], false)
      else
        cv:rect(cx, mid_y, cc_w, cc_h, COL_FELT_DARK, true, 3)
        cv:rect(cx, mid_y, cc_w, cc_h, COL_FELT_LINE, false, 3)
      end
    end

    -- 3. Bottom Player Row (y = 122..172)
    local py = top_h + 102
    local p = seats[1]

    -- Player's 2 Hole Cards (x = 8..74)
    if #p.cards == 2 then
      draw_card_box(8, py, 37, 48, p.cards[1], false)
      draw_card_box(38, py, 37, 48, p.cards[2], false)
    end

    -- Right of Player's Hole Cards: Info Panel OR Showdown Banner (x = 82..314)
    local info_x = 82
    local info_w = W - info_x - 6

    if state == "done" and banner_title ~= "" then
      cv:rect(info_x, py + 2, info_w, 44, 0x0D131A, true, 6)
      cv:rect(info_x, py + 2, info_w, 44, banner_col, false, 6)
      cv:text(info_x + I((info_w - ui.text_w(banner_title, 14)) / 2), py + 6, banner_title, banner_col, 14)
      cv:text(info_x + I((info_w - ui.text_w(banner_sub, 11)) / 2), py + 26, banner_sub, C.text, 11)
    else
      cv:rect(info_x, py + 2, info_w, 44, COL_POD_BG, true, 5)
      local p_border = (state == "player") and C.accent or 0x22303C
      cv:rect(info_x, py + 2, info_w, 44, p_border, false, 5)

      local you_hdr = p.role ~= "" and string.format("YOU [%s]  BET $%d", p.role, I(p.street_bet)) or string.format("YOU  BET $%d", I(p.street_bet))
      cv:text(info_x + 6, py + 5, you_hdr, C.text, 11)

      local _, _, hname = eval_best_hand(p.cards, board)
      local h_str = p.folded and "FOLDED" or hname
      cv:text(info_x + info_w - ui.text_w(h_str, 11) - 6, py + 5, h_str, p.folded and C.bad or COL_GOLD, 11)

      local line2 = (state == "player")
        and string.format("RAISE TARGET: $%d  [Up/Down]", I(raise_to))
        or (p.status ~= "" and ("STATUS: " .. p.status) or "WAITING FOR TABLE...")
      cv:text(info_x + 6, py + 19, line2, C.accent, 10)

      local line3 = "[F]Fold  [C]Call/Chk  [R]Raise  [A]All-In"
      cv:text(info_x + 6, py + 32, line3, C.sub, 10)
    end
  end

  -- Bottom button bar
  local by = H - bot_h
  cv:rect(0, by, W, bot_h, COL_BOTBAR, true)
  cv:line(0, by, W, by, 0x1F2933, 1)

  local nb = #active_btns
  if nb > 0 then
    local gap = 4
    local bw = I((W - gap * (nb + 1)) / nb)
    local bh = bot_h - 6
    for i = 1, nb do
      local b = active_btns[i]
      local bx = gap + (i - 1) * (bw + gap)
      local bby = by + 3
      b.x, b.y, b.w, b.h = bx, bby, bw, bh

      local bg = not b.enabled and COL_BTN_DIS or (b.primary and COL_BTN_ACT or COL_BTN)
      cv:rect(bx, bby, bw, bh, bg, true, 4)

      if i == focus_idx and b.enabled then
        cv:rect(bx, bby, bw, bh, b.primary and COL_GOLD or C.accent, false, 4)
      elseif b.enabled then
        cv:rect(bx, bby, bw, bh, 0x2B3642, false, 4)
      end

      local tcol = not b.enabled and COL_TEXT_DIM or (b.primary and COL_GOLD or C.text)
      local tw = ui.text_w(b.label, 11)
      local tx = bx + math.max(2, I((bw - tw) / 2))
      local ty = bby + I((bh - 11) / 2)
      cv:text(tx, ty, b.label, tcol, 11)
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
  W = I(w or 320)
  H = I(h or 208)

  seats[1].stack = I(tonumber(store.get("he_bank", START_STACK)) or START_STACK)
  best_bank      = I(tonumber(store.get("he_best", START_STACK)) or START_STACK)
  hands_won      = I(tonumber(store.get("he_wins", 0)) or 0)
  hands_played   = I(tonumber(store.get("he_hands", 0)) or 0)
  blind_idx      = I(clamp(tonumber(store.get("he_blind", 1)) or 1, 1, #BLIND_LEVELS))

  local _, bb = get_blinds()
  if seats[1].stack < bb then seats[1].stack = START_STACK end
  for i = 2, 4 do seats[i].stack = START_STACK end

  cv = ui.canvas(W, H)
  cv:pos(0, 0)

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
    -- All-in runout: deal next community street
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
    if ey <= 20 and ex >= W - 64 then
      sound_on = not sound_on
      sys.toast(sound_on and "Sound ON" or "Sound OFF")
      draw_screen()
      return
    end
    if state == "ai" then
      app.on_tick(0)
      return
    end
    if (state == "done" or state == "title") and ey > 22 and ey < H - 32 then
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
