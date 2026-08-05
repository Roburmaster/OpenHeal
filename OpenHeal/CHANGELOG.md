# OpenHeal Changelog

## Version 1.0.0

- Renamed the addon, public Lua identifiers, frames, slash commands, profile
  exports, media paths, and SavedVariables to OpenHeal.
- Added a one-time import for settings from the previous addon when it is
  enabled during the first OpenHeal login.
- Added the MIT open-source license.

## Version 0.5

Structural pass: shared foundations, four new frame features, and the removal
of dead code and dead configuration.

### New

- **Style tab** in Settings. One place for bar texture, font, font size and
  outline, applied to every frame set at once.
- **LibSharedMedia support** (optional, auto-detected). If any addon you run
  provides LSM — ElvUI, WeakAuras, Details, Plater — its textures and fonts
  appear in the Style tab automatically. LSM is *not* embedded, so the addon
  stays standalone and there is no bundled library to fall out of date.
- **Health-bar smoothing.** Damage slides instead of snapping, which is how you
  notice a bar dropping fast without staring at it. See the caveat below.
- **Aggro / threat borders.** Colour depends on whether the unit is supposed to
  be tanking: a non-tank climbing the threat table is orange, a non-tank
  actually being hit is red, a tank holding threat is blue (and hidden by
  default, since that is the normal state).
- **Resurrection and pending-summon icons.** Stops two healers casting a res on
  the same corpse.
- **Pet frames** (`UI/pet.lua`). `fading/range.lua` had been driving
  `ns.Pet.playerFrame` / `partyFrames` / `raidFrames` all along — the module it
  called into simply did not exist. Pets inherit their owner's range for fading.
- **Tank frames** (`UI/tanks.lua`). `db.raid.tankFrames`, `tankSide`, `tankW`,
  `tankH`, `tankSpacing`, `tankOffsetX` and `tankOffsetY` have had a checkbox, a
  dropdown and five sliders in Settings wired to nothing. They work now, as does
  "Keep tanks in Raid Grid".
- **Profile import / export** in the Profiles tab. Mainly a backup path: this is
  the only way to recover a layout after a corrupted SavedVariables file.
- **Class colour on background** option — bar shows health, background shows
  class. Reads "how hurt" first and "who" second.

### Fixes

- **`/openheal` opened a fifth, separate binding editor.** Bindings could be
  edited or displayed in five places: that window, the Settings Mouseover tab,
  the Multi Focus tab, the bind grid viewer, and the focus panel. `/openheal`
  (and the new `/oh`) now open the unified Settings. `/openheal legacy` still
  reaches the old window if you want it.
- **`cast.lua` had no access to the addon namespace.** It hardcoded the addon
  name instead of taking the loader vararg, so it could not see shared modules.
- **Members in vehicles froze or blanked.** Health moves to the vehicle token
  when someone mounts; the frame kept reading the player token. Display now
  follows the vehicle while the secure click-cast attribute deliberately stays
  on the stable token, because changing that in combat is blocked.
- **Sliders floored every value**, so any fractional setting collapsed to 0 or 1.
  `CreateModernSlider` now takes an optional precision.
- **Aggro colouring had a dead branch** and painted a non-tank holding the boss
  the same calm blue as the tank.
- `Enum.SummonStatus` is not guaranteed to exist on every build; reading through
  it unguarded would have errored inside an event handler.

### Structure

- **`core/util.lua`** — party.lua and raid.lua carried byte-identical copies of
  every secret-safe helper, the name/role/health getters, and the combat-safe
  show/hide logic. They had already drifted (raid checked `allowDrag` on drag
  start, party did not). Pet and tank frames would have made it four copies.
  Both files now pull the shared versions into file-scope locals, so call sites
  and upvalue lookups are unchanged.
- **`UI/theme.lua`** — colours, fonts and textures in one place instead of
  literals scattered across a dozen files.
- **`ns.util.IsSafeUnit`** — party.lua and raid.lua probed for this on every
  health-text update. It never existed. It does now.

### Removed

- `auras/auralib.lua` — 168 lines of sanitizers with zero callers.
- `migration_msg.lua` — one-time popup about a DB reset that is long past.
- `.directory` — a KDE folder-icon file, on a Windows install.

### Known limitations

- **Smoothing needs a readable health number.** Interpolation means reading the
  current value and stepping toward a target; secret health values cannot be
  read or compared in Lua at all. Where the game hides health, bars snap exactly
  as before. No addon can do better than this.
- **Tank frame unit assignment is out-of-combat only.** Changing a secure
  button's unit attribute in combat is blocked. If someone becomes a tank
  mid-pull their dedicated frame appears when combat ends; their normal raid
  frame is unaffected.
- **Export strings are uncompressed** (~600 bytes for a full profile) because
  LibDeflate is not embedded. They paste fine.

### Note on licensing

`LICENSE` is GPLv3 and `LICENSE.txt` is "All Rights Reserved". These contradict
each other. Both were left untouched — pick one.

---

## Version 0.4

### Fixes

- **Aura filter settings had no effect on the actual frames.** The Buff Filter /
  Debuff Filter dropdowns and the CUSTOM spell lists were only ever read by the
  settings preview. `debuffs.lua` ignored the profile entirely (hardcoded 6 icons
  at 16px) and `friendlybuffs.lua` always used the built-in preset. Both now read
  `enabled`, `mode`, `maxIcons`, `size`, `custom` and `customOnlyDispellable`, and
  the preview and the live frames resolve their lists through the same code.
- **`aura_filters.lua` loaded after the modules that use it**, so
  `local AF = ns.AuraFilters` captured `nil` and the filter module was dead code.
- **Raising "Max Icons" for friendly buffs threw a Lua error.** Icon frames were
  only created up to the value of `maxIcons` at attach time.
- **Deleted click-cast bindings kept firing until `/reload`.** Overlay attributes
  were only ever set, never cleared.
- **The legacy profile migration never ran.** `db.lua` created
  `OpenHealGlobalDB` at file scope, which made the migration's
  `not _G.OpenHealGlobalDB` guard permanently false.
- **SavedVariables were declared incorrectly.** `OpenHealDB` was listed as both
  account-wide and per-character.
- **Out-of-range frames kept a full-brightness health %.**
- **Turning range fading off left frames stuck dim.**

### Performance

- **Health events no longer trigger a full frame rebuild.** `UNIT_HEALTH` used to
  run the complete `Apply()` path including three separate scans over up to 40
  auras each.
- **Private aura cover detection no longer allocates** — roughly 1200 throwaway
  tables per second in a full raid.
- **Aura filter lists are resolved once, not once per frame.**

### Improvements

- Raid target markers, dead / ghost / disconnected status text, and a new `ALL`
  aura filter mode.

---

## Version 0.1

Initial public repository setup.

## v13

### Fixes
Silver fixed minimap postion saving.
