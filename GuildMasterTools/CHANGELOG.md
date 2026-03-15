## v3.9.2
- Economy transaction log requery/rehydrate pass for unknown names
- Rebuild contribution ranking from latest live transaction buffer
- Replace per-query transaction entries on reparse instead of duplicating

## v3.9.1
- Economy transaction parsing now snapshots each tab immediately after its log update.
- Contribution ranking rebuilds from live scan buffers during the scan.
- Transaction item column now falls back to transaction type text when link text is unavailable.

## v3.8.6
- Fixed Economy transaction log scanning by explicitly querying guild bank logs before parsing.
- Added money-log parsing fallback for contribution ranking.
- Hooked transaction refresh to GUILDBANKLOG_UPDATE so results populate after the server updates.

## v3.8.5
- Deepened guild bank item detection with tooltip-based fallback reads.
- Defaulted empty tab slot counts to 98 when tab metadata is delayed.
- Slightly increased per-tab wait time and added clearer empty-tab logging.

## 3.8.1
- Restructured Members tab right column so Guild Snapshot and Guild Scoreboards fit cleanly.
- Removed the stray bottom-right notes box and moved roster status into the scoreboard card.
- Reflowed scoreboard mode buttons into two rows and clipped long summary values to stay inside the box.

## 3.7.2
- Fixed Guild Talent Map startup scan calling a nil ScanGuildMap function; now uses the event-driven guild scan request path.
- Moved Economy scan buttons to the right side of the summary box so they stay inside the panel and out of the text area.

## v3.7.1
- Moved Guild Talent Map scan buttons to the right side of the summary box for cleaner alignment.

## v3.6.3
- Made Data / Diagnostics Center output scrollable so text stays inside the box
- Raised slash command text slightly to avoid touching panel borders
- Tightened Module Data columns so values stay inside the box

## v3.6.2
- Fixed Settings panel bottom overlap
- Rebuilt export buttons into a 2x3 grid
- Tightened diagnostics output area

## v3.6.0
- Rebuilt Settings into a data-rich Addon Command Center
- Added live addon snapshot, module metrics, slash-command reference, diagnostics center, and export summary tools
- Preserved addon name GuildMasterTools

## v3.5.3
- Tightened Events tab button layout so action buttons stay inside their boxes
- Reduced RSVP button footprint and note width for cleaner fit

# GuildMaster Tools -- Changelog

## [3.4.3] -- Button & Layout Fixes -- 2026-03-14  <-- CURRENT

### Economy: Scan Bank / Scan Transactions buttons fixed
- Old code declared `scanTransBtn` AFTER its first `SetPoint` call (referenced
  before declaration), and the overflow math put the chained button 14px past
  the section right edge.
- Fixed: both buttons declared in correct order, chained right-to-left using
  `TOPRIGHT` anchor for `Scan Transactions` and `RIGHT ... LEFT` for
  `Scan Bank Items`. Both now fit inside the 928px usable width.
- Orphaned duplicate `ParseTransactions()/RefreshAll()/end)` block (left over
  from the earlier str_replace session) removed.
- Guild Bank scan: `GUILDBANKFRAME_OPENED` event sets `bankOpen=true`; both
  buttons guard with `if not bankOpen` and show a clear status message.

### Options: Data Export text color and overflow fixed
- `EditBox:SetTextColor()` is overridden by WoW template defaults at frame
  creation time. Fix: wrapped the color call in `C_Timer.After(0, ...)` so
  it runs after all template setup completes, giving warm amber body text.
- Hint `FontString` had no `SetWidth` -- text escaped the export section box.
  Fixed: `hint:SetWidth(460)` + `SetJustifyH("LEFT")`, text shortened.
- `SetTextInsets(4,4,4,4)` added to `outBox` for inner padding.

### Home: logo ring circle removed
- `MiniMap-TrackingBorder` ring texture around the logo removed per request.

### Home: Events & System card overflow fixed
- Card had 6 rows x 20px = 120px + 36px header = 156px > `CH=148` by 8px.
- Reduced to 4 rows: Next Event, Starts In, RSVPs, Status.
- "Status" row shows version + module count + sync member count in one line:
  `v3.4.3  11 mods  N sync`.

### Recruitment: action buttons overflow fixed
- `btmH=96` but action buttons placed at `y=-82` with height 22px end at
  `y=-104`, overflowing the section by 8px.
- `btmH` increased from 96 to 112px (18px margin remaining, PH=528).

### GuildSync: controls bar height fixed
- `r1H=46` left only `46-30=16px` usable below the header, but buttons
  need 22px height -- causing the ping/broadcast buttons to overflow.
- `r1H` increased from 46 to 56px. `r2Y` adjusts automatically via arithmetic.

### Gears: all remaining section-header gears removed
- `GMT.Gear()` calls inside all local `Sec()` / `MkSection()` / `Section()`
  helper functions across every module removed via Python regex pass.
- Economy `MkSection`, Recruitment drawer, and all remaining instances gone.
- `GMT.Gear` and `GMT.GearRing` functions remain in `Theme.lua` but are now
  called nowhere.

---

## [3.4.2] -- GuildSync crash, Members crash, card overflow, guild name, subtitle
## [3.4.1] -- Gears removed, unicode stripped, phase refs cleaned, home populated
## [3.4.0] -- Phases 11-15 complete
## [3.3.x] -- Phase 10 GuildSync + fixes
## [3.2.0] -- Phase 9 Raid Performance Predictor
## [3.1.0] -- Phase 7 Logistics + Reload + Invite
## [3.0.0] -- Phase 4 Chat Scanner

- 3.8.3: Fixed Economy guild bank scan to query tabs sequentially and wait for data before reading items.


## v3.8.4
- Hardened guild bank scanning with tab-by-tab retries
- Added per-tab scan logging for occupied slots, stacks, and item totals
- Counts occupied guild bank slots even when links are delayed by cache timing

- 3.8.8: Economy tab now repaints immediately after scans, retries late log data, and shows quality text in Guild Bank Contents.


## 4.2.0
- Rebuilt Talent Map v2 around synced profession profiles
- Migrated Talent Map saved data to a dedicated talentMap database
- Removed Crafting.lua from addon runtime package
- Improved profession scan, guild sync refresh, and material bucket labels
