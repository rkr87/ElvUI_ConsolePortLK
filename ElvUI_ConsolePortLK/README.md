# ElvUI_ConsolePortLK

An ElvUI plugin for **Wrath of the Lich King 3.3.5a** that skins the
[ConsolePortLK-Enhanced](https://github.com/SuttonX/ConsolePortLK-Enhanced) action bar so it
matches your ElvUI action bar buttons.

It works the same way as [ElvUI_AddOnSkins](https://github.com/ElvUI-WotLK/ElvUI_AddOnSkins):
it is a standalone addon that hooks into ElvUI, registers itself in
`ElvUI > Plugins` and stores its options in your ElvUI profile.

---

## Requirements

| Addon | Notes |
| --- | --- |
| [ElvUI for WotLK](https://github.com/ElvUI-WotLK/ElvUI) | required |
| [ConsolePortLK-Enhanced](https://github.com/SuttonX/ConsolePortLK-Enhanced) (`ConsolePort` + `ConsolePortBar`) | required |
| ElvUI_OptionsUI | **do not add it as a dependency**, see the note below |

> **Important:** `ElvUI_OptionsUI` is a LoadOnDemand addon and must never be listed in
> `RequiredDeps`/`OptionalDeps` of a plugin. Listing it makes the client force load the
> options addon at login, before ElvUI has built `E.data` and `E.Options.args.plugins`.
> That produces `AceDBOptions-3.0: attempt to index local 'db' (a nil value)` and
> `LibElvUIPlugin-1.0: attempt to index field 'plugins' (a nil value)` for **every**
> ElvUI plugin. This addon only declares `## RequiredDeps: ElvUI`; ElvUI loads its own
> options addon when you type `/elvui`.

## Installation

1. Copy the `ElvUI_ConsolePortLK` folder into `World of Warcraft/Interface/AddOns/`.
2. Make sure the folder is named exactly `ElvUI_ConsolePortLK` and that
   `ElvUI_ConsolePortLK.toc` is directly inside it.
3. Enable the addon and `/reload`.

On first login ElvUI's plugin installer offers to enable the skin, just like
ElvUI_AddOnSkins does. You can also turn it on later under
`ElvUI > Plugins > ConsolePort`.

## What it does

* Replaces ConsolePort's round crescent blobs and square button art with a
  clean ElvUI backdrop + border and a trimmed icon, matching
  `ElvUI > ActionBars` button styling.
* Uses your ElvUI action bar font, font size, font outline and count text
  position, so the buttons look identical to your ElvUI bars.
* Draws its border with **ElvUI's** border colour, so a theme change
  (`ElvUI > General > Media > Border Color`) repaints the ConsolePort bar too.
* Takes over the cooldown text: instead of ConsolePort's own CPCC countdown it
  renders ElvUI's action bar cooldown text (`30`, `1m`, `1h`) with ElvUI's
  colours and "seconds" threshold.
* Hides the macro text ConsolePort prints at the bottom of each button.
* Lets you control the border size.
* Optionally skins the pet ring as well.
* Re-applies itself whenever ConsolePort re-styles the bar (layout save,
  preset change, bar reload), so the skin does not get lost.

## Options

`/cplk config` (or `ElvUI > Plugins > ConsolePort`) opens:

| Group | Option | Default | Description |
| --- | --- | --- | --- |
| – | Enable Plugin | on | Master switch. Turning it off restores the ConsolePort art. |
| Bar Options | Apply Skin | – | Re-applies the skin and picks up new buttons. Safe in combat. |
| | Reset Settings | – | Resets every option of the plugin (asks first). |
| Border | Border Size | `1` | Border thickness, multiplied by ElvUI's pixel scale. `0` removes the border. |
| | Border Outside | off | Draws the border around the button bounds instead of on the ConsolePort art edge. |
| Font & Text | Hide Macro Text | on | Hides the macro name at the bottom of the button. |
| | Hide Count Text | off | Hides the stack/charge count. |
| | ElvUI Font | on | Uses the ElvUI action bar font, size, outline and colours. |
| | Text Size | `10` | Size used for the count and macro text. |
| | Font Outline | `OUTLINE` | Outline flag for the button text. |
| Cooldown Text | ElvUI CD Text | on | Replaces the ConsolePort cooldown text with ElvUI's. |
| | Use ElvUI Settings | on | Uses `ElvUI > Cooldown Text` for colours and threshold. Turn off to use the two options below. |
| | Cooldown Text Size | `12` | Font size when not using the ElvUI settings. |
| | Cooldown Threshold | `3` | Below this many seconds the text switches to one decimal (`2.4`). |
| Misc Options | Show Blizzard Swipe | on | Keeps ConsolePort's radial swipe under the text. |
| | Desaturate on Cooldown | off | Greys the icon while the ability is cooling down. |
| | Skin Pet Ring | on | Skins the pet action ring too. |

## Changelog

### 1.1.4

- **Fixed the crash that stopped cooldown text from ever appearing.**
  `Core/Skin.lua:475: <unnamed>:SetText(): Font not set` - the plugin cleared its
  own holder FontString while it had no font. On 3.3.5a that throws, and the
  error escaped `UseElvUICooldown`, so ElvUI's cooldown timer was aborted
  *before* it was ever given a font or shown. Every cooldown after that was
  silently text-free and the error was logged.
  - Font strings now get a font the moment they are created.
  - All text clearing goes through `SafeSetText`, which attaches a font if one
    is missing and cannot throw.
  - ElvUI's timer is configured and shown *before* our own holder is touched,
    and if ElvUI's own paint call draws nothing the plugin formats the first
    value itself, so text appears either way.
- **The test harness now reproduces the bug.** `mock.lua` throws
  `"Font not set"` from `FontString:SetText` exactly like 3.3.5a, and
  `SetFontObject` / `CreateFontString(name, layer, template)` now really apply a
  font. That strictness immediately caught the same latent crash in the debug
  window's title. This is why the earlier green test runs did not find it: the
  mock was more forgiving than the client.
- The debug report now prints ElvUI's cooldown settings and the timer's
  `fontScale`, flagging it when it is under the 0.5 that makes ElvUI hide
  cooldown text on small buttons.

### 1.1.3

- **Cooldown text now actually appears.** The previous version hooked
  ConsolePort's cooldown frame with `hooksecurefunc(cd, "SetCooldown")` and drew
  the text from that hook. That is not a reliable trigger:

  - `button.cooldown` is `_G[name..'Cooldown']`, and ConsolePort re-points it
    when it rebuilds a bar, so the skin can end up hooking a frame the button no
    longer uses;
  - a cooldown that is already running when the skin is applied never fires the
    hook at all, so it shows nothing until the ability is used again;
  - cooldown frames created after skinning are never hooked in the first place.

  ConsolePort's own cooldown text abandoned hooks for exactly this reason - its
  source says the previous implementation "meant square/slice modes had no
  reliable text driver" - and it now polls one throttled driver frame. This
  plugin does the same: a single driver frame reads each button's cooldown frame
  every 50 ms via `GetCooldownTimes` (the authoritative "what is this frame
  actually showing" call), re-hooks any frame it has not seen before, and only
  starts a new text timer when the cooldown really changed. Text therefore
  appears for cooldowns that were already running, for frames swapped in after
  skinning, and live when the option is toggled.
- Sub-1.5 s cooldowns get no numbers again, matching an ElvUI action button and
  ElvUI's own `MIN_DURATION`, so the global cooldown never flashes a "1".
- The cooldown driver starts and stops with the skin and with the cooldown-text
  option.
- `/cplk debug` -> `report` now shows the cooldown driver state, the cooldown
  frame and whether it is hooked, what `GetCooldownTimes` reports, the remaining
  time, and the ElvUI timer and text. That narrows any remaining cooldown
  problem to one line.

### 1.1.2

- **Every border is now exactly one pixel, on every button.** ConsolePort sizes
  its buttons from its own layout, and those sizes are rarely whole screen
  pixels (`10.35`, `17.999998`, ...). A frame whose edge falls between two
  pixels anti-aliases its 1px border across both of them, which is why only
  *some* borders looked 2px thick. The backdrop size and the icon inside it are
  now snapped to the screen pixel grid, and the edge thickness is converted
  from screen pixels to frame units using the button's effective scale, so the
  border covers exactly one real pixel on every side at any bar scale.
- **Macro text and count text toggles apply immediately.** The text visibility
  is now its own pass (`ApplyTextVisibility`) that runs on every option change
  and after every ConsolePort button update, instead of being decided once while
  the button was skinned. Both directions work without a reload.
- **"Use ElvUI Settings" now actually uses ElvUI's cooldown text.** The plugin
  no longer just *formats* text the way ElvUI does - it builds ElvUI's own
  cooldown timer (`E:Cooldown_Options`, `E:Cooldown_OnSizeChanged`,
  `E.Cooldown_OnUpdate`) and drives it exactly as `E:OnSetCooldown` does, so the
  global cooldown settings apply for real, including live changes.
- `noCooldownCount` is cleared on the ConsolePort cooldown frames in ElvUI
  mode; ConsolePort sets it from its own "cooldown text" setting, and ElvUI
  refuses to produce text for a frame that has it.
- Cooldowns shorter than 1.5 s are no longer silently dropped (`MIN_DURATION`
  1.5 -> 0.4).
- The macro name is re-read from the action on every restyle, so a region that
  ConsolePort skipped updating cannot keep a stale string (an empty-button hint)
  on a hidden button.
- The font size ElvUI uses for the timer is derived from a real width instead of
  a zero width, which made ElvUI hide the text on frames sized after creation.
- `/cplk debug` report now also prints the button size, its scale, the pixel
  grid it snapped to, the icon size and the edge thickness in both frame units
  and screen pixels.

### 1.1.1

- **The button now looks like an ElvUI action button because it is built the way
  ElvUI builds one.** From `Modules/ActionBars/ActionBars.lua`, ElvUI styles its
  action buttons with:

  ```lua
  button:CreateBackdrop(template, true)
  button.backdrop:SetAllPoints()
  icon:SetTexCoord(unpack(E.TexCoords))
  icon:SetInside()
  button:StyleButton()
  ```

  The plugin now uses `CreateBackdrop` (ElvUI's own mixin, which applies the
  `Default`/`Transparent` template, colours and `E.frames` registration) and
  positions the icon with `SetAllPoints`/inset points the same way, instead of
  hand-building frames with invented insets. Those invented insets are what made
  the border invisible for several versions.
- New **Backdrop Template** option: `Auto` (follows your ElvUI action bar
  `transparentButtons` setting), `Default`, or `Transparent`.
- The button frame no longer paints its own backdrop, so there is exactly one
  backdrop per button, as in ElvUI.
- Remove all the earlier border geometry experiments (child frame levels, raised
  markers, negative insets).

### 1.1.0

- **Fixed: the border was still invisible.** Two mistakes compounded. It
  inherited ElvUI's `bordercolor`, which is pure black on a stock profile - so it
  was drawn in the same colour as the gap between buttons - *and* it was drawn
  with negative insets, putting it outside the button bounds where the
  neighbouring ConsolePort satellite buttons overlap and cover it. The border is
  now a child frame inset within the button and raised above the art, which is
  the arrangement the debug overlay proved works.
- **Border colours now behave as expected:**
  - the base colour inherits ElvUI's border colour;
  - **hover and press** switch it to your **class colour**;
  - **Border Colour** overrides the base colour;
  - **Hover Colour** overrides the highlight colour;
  - **Class Colour on Hover** turns the highlight off entirely;
  - **Auto Border Contrast** is on by default and lifts a border that is
    indistinguishable from the backdrop, which is why a stock black-on-black
    theme looked like it had no border at all. Turn it off to use ElvUI's colour
    verbatim.
- The report prints the border frame's parent, frame level, visibility and the
  colour actually drawn.

### 1.0.12

- **Fixed: the border was invisible because it was drawn in pure black.** ElvUI's
  `bordercolor` is `0, 0, 0` on many profiles and the backdrop is near-black too,
  so the border was there the whole time but indistinguishable from the gap
  between buttons. In debug mode it was overridden to magenta, which is why it
  only ever showed there. The border colour is now contrast-adjusted against the
  backdrop when the two are too close, and the report prints the colour actually
  drawn.
- **Fixed: a 1px border could snap to 0.96px.** With ElvUI pixel mode on and a
  non-native UI scale, `E.mult` is below 1, so `E:Scale(1)` returns less than one
  physical pixel and a backdrop edge that thin does not render at all. The border
  thickness now has a floor of one physical pixel.
- **Fixed: the icon trim could be set to the wrong values.** All four texcoord
  values are now set explicitly instead of relying on `unpack(E.TexCoords)`.
- "Border Outside" now genuinely offsets the border by one further thickness; the
  negative inset already places it around the button.
- New tests: the border must be visibly distinguishable from the fill on a
  black-on-near-black profile, a 1px border must never snap below one physical
  pixel, and the icon trim must match `E.TexCoords` exactly.

### 1.0.11

- **`/cplk debug report` now opens a scrollable, copyable window** instead of only
  writing to chat. Chat scrollback was losing the report, which is why the
  command looked like it did nothing. Click into the text, ctrl+a then ctrl+c.
- **The report starts with a hardcoded `BUILD:` string** read from the file that
  is actually running. The addon *folder* name is not reliable - if you replace
  files inside an existing folder and `/reload`, the folder name in error
  messages keeps the old version - so the build string is the only trustworthy
  way to confirm which code is live.
- The command always writes at least one chat line, so it can never appear
  silent. If the window cannot be created it falls back to printing every line
  to chat.
- **Fixed: the border was invisible** (from 1.0.10). A `SetBackdrop` edge with a
  positive `edgeSize` and zero insets draws *inwards* from the button bounds,
  underneath the icon. Borders now use negative insets, the way ElvUI's own
  toolkit draws them, so the edge sits around the button.

### 1.0.10

- **Fixed: the border was invisible.** A `SetBackdrop` edge with a positive
  `edgeSize` and zero insets is drawn *inwards* from the button bounds, which
  puts it underneath the icon. ElvUI's own toolkit draws its borders with
  negative insets for exactly this reason, and the plugin now does the same, so
  the border sits around the button instead of underneath its contents.
- **The report now identifies the install.** It prints the addon folder it was
  loaded from and warns loudly if more than one folder matching
  `*consoleportlk*` is enabled. Every released zip is extracted into a
  version-numbered folder, so an old copy left in `Interface/AddOns` loads
  alongside the new one and both fight over the same buttons. This is the
  likely reason some fixes appear to do nothing.
- The report now prints each button's icon texture path, marking
  `ability-empty`/`EmptyIcon` as **EMPTY SLOT**, so a genuinely empty action
  slot can be told apart from one whose art went missing.
- The report lists up to 20 buttons instead of 6.

### 1.0.9

- **Fixed: `/cplk debug report` printed nothing.** The command parser cut the
  argument with `command:sub(6)`, which leaves the separating space in place
  (`"debug report"` -> `" report"`), and the report path then did nothing.
  The argument is trimmed after being cut. `debug on`/`debug off` happened to
  work, which is why the overlay could be on while the report stayed silent.
- `/cplk` now always registers a plain slash fallback in addition to AceConsole,
  so the command cannot be missing.
- If `Core\Debug.lua` ever fails to load, the command now says so explicitly
  instead of silently doing nothing.
- The debug overlay also draws an explicit marker on every button - **magenta**
  outline for skinned buttons, **red** for buttons the plugin found but did not
  skin - on a frame above everything else. That is the ground truth for where
  the plugin thinks each button is, independent of the border and backdrop.
- The report is generated inside a protected call and kept in
  `/cplk debug saved`, so a formatting failure cannot swallow it and the chat
  scrollback can be re-read.

### 1.0.8

- **New: `/cplk debug`** — colour-codes every element the plugin adds, for
  screenshots, and `/cplk debug report` prints a full diagnostic report.
  - magenta = border edge, green = backdrop fill, orange = icon region,
    blue = hover highlight, red = cooldown text, yellow = count/macro text.
  - The report prints `E.mult`, `E.Border`, `E.PixelMode`, media textures and
    colours, every option value, and per-button geometry:
    `GetBackdrop()`, edge size, icon size, icon points, icon texcoords and how
    many textures were hidden.
- **Fixed: the backdrop did not match ElvUI and empty slots showed the world
  through.** Everywhere the code reads ElvUI's colour tables is now tolerant of
  a missing alpha channel (`E.media.backdropcolor` only carries three values),
  and the fill uses ElvUI's own backdrop colour at full alpha. A fallback
  background texture is used if ElvUI has not loaded `blankTex` yet.
- **Fixed: the border disappearing.** `SetBackdropEdge` skipped work based on a
  marker it had cached, so once ConsolePort's `ResetAllButtons()` called
  `SetBackdrop(nil)` on the buttons the border never came back. The backdrop is
  now re-applied whenever it is actually missing, and colours are refreshed on
  every update.

### 1.0.7

- **Fixed: the region sweep did nothing on the live client, so the extra white
  borders were still there.** `GetRegions()` returns *multiple values* in WoW,
  not a table - ElvUI's own `StripTextures` iterates it with
  `select(i, object:GetRegions())`. 1.0.6 wrapped the call in `pcall` and
  iterated the result with `ipairs`, so it only ever saw one frame. The sweep now
  enumerates the real return values.
- **Fixed: buttons losing their icons.** The sweep hid everything that was not
  the *cached* icon reference. When ConsolePort swaps a button's icon region the
  cached reference no longer matches, so the sweep hid the live icon and the
  button went blank - and adding the sweep is what made it worse. The sweep now
  follows `button.icon` at the time it runs.
- **Fixed: the white `Border` ring on the button overlay.** ConsolePort draws its
  button art on a child frame (`CPUIActionButtonTextureOverlayTemplate`, named
  `$parent_HOTKEY`) that `GetRegions()` on the button never sees. That frame is
  now stripped too, keeping its `parentKey="texture"` icon overlay art.
- Stripping now clears the texture as well as the alpha, because ConsolePort's
  `Border` is an ADD-blended white ring that alpha alone barely dims.
- The icon overlay art is kept in sync with ElvUI's trim, so a trimmed icon is
  not left sitting inside an untrimmed sliver.
- New tests: `GetRegions()` is consumed the way WoW returns it, a swapped icon
  region is never hidden, and the overlay's ring is stripped while its icon art
  survives. Each was verified to fail against the 1.0.6 code.

### 1.0.6

- **Fixed: white squares where an icon should be.** The border backdrop painted
  an opaque fill using ElvUI's `backdropcolor`, which is a user theme colour
  (a light theme makes it near-white). The icon covers the button, so the fill
  is now fully transparent.
- **Fixed: icons looked empty on the small modifier buttons.** The skin stretched
  the icon to the full button area, magnifying the transparent margins that
  ConsolePort builds into its art (it sizes its own icon at 40/45 of the button).
  The icon now keeps ConsolePort's size, is centred, and is never enlarged.
- **Fixed: an empty slot rendering as a blank box** when ConsolePort's
  `ability-empty2` texture is not present in the installed ConsolePortLK build.
  The texture is resolved first, and cleared if it cannot be.
- **Fixed: 2px borders on some edges.** The border used ElvUI's `E.Border` as its
  outside offset, but `E.Border` is `E.mult * 2` unless ElvUI's pixel mode is on,
  so the band was two pixels on the offset edges and one on the others. Edge
  thickness and offset now use the same `E:Scale()`-snapped value, so a 1px
  border is 1px on all four sides.
- New tests: the backdrop fill must be fully transparent and the icon must never
  be stretched beyond the button.

### 1.0.5

- **Fixed: `Core\Skin.lua:496: CPB_X_...:SetPoint(): trying to anchor to itself`.**
  For action buttons the border is drawn on the button frame itself, so the
  `SetPoint("TOPLEFT", button, ...)` call was anchoring the button to the
  button. WoW always rejects that. Because each button is guarded, the error was
  swallowed and everything after the throw - anchoring the icon, styling the
  text - never ran. That is what left a scattering of buttons **without icons**
  and without counts. The icon and hover overlay are now anchored through an
  `anchor` reference that is always a different frame.
- **Fixed: a second, white border inside the ElvUI one on every button.**
  ConsolePort draws regions the old hide-list never covered - `Flash`,
  `FakeChecked`, `Border`, pet-only regions - and which of them exist varies per
  frame. Every texture region is now hidden except the icon, the hotkey glyphs
  and the plugin's own hover overlay, and this is re-checked on every update so
  regions ConsolePort re-shows are caught.
- **Fixed: buttons without icons.** `NewActionTexture` is the icon art on some
  ConsolePort frames and was being hidden by name. The icon itself is now never
  touched, and "new action" is handled as a separate overlay only when it is
  genuinely a different region.
- The apply also no longer repositions a button that is already correct, so the
  bulk `RefreshCooldowns()` path stays cheap.
- New regression tests: anchoring never targets the button itself, stray texture
  regions get hidden, and the icon is never hidden. Each was verified to fail
  against the previous code.

### 1.0.4

- **Rolled back to the 1.0.4 code.** The 1.0.5 and 1.0.6 attempts (metatable
  hook, `Repair()` pass, texcoord polling) made the bar worse and have been
  removed. The border is a child frame at `frameLevel - 1`, the geometry
  watchdog only compares button widths, and there is no settle timer.
- **Fixed the crash:** `Core\Skin.lua:503: attempt to call method 'SetShown'
  (a nil value)`, raised from `SkinButton` via `SkinNewButtons`. ConsolePort
  frames are not uniform - `button.Count`, `button.Name` and
  `button.NewActionTexture` can be plain tables, or widgets that do not
  implement every method. They are now validated before use, so a region that
  is not a real widget is simply left alone. ConsolePort itself only ever calls
  `Show`/`Hide` on these regions, never `SetShown`.
- **A single bad frame can no longer abort the whole apply.** Every per-button
  step is guarded, so one odd ConsolePort button cannot leave the rest of the
  bar unskinned.
- A broken button is reported **once** rather than on every pass, which is what
  produced the repeated `9x ...` spam.

- **Fixed: nothing was applied unless you ran `/cplk skin`.** The module's
  `Initialize()` was defined but never called, so `PLAYER_ENTERING_WORLD`,
  `ADDON_LOADED` and the delayed first apply were never registered. The skin
  engine is now started from `OnInitialize`, and also applies immediately when
  the plugin is loaded into an already-running session.
- **Fixed: `/cplk skin` crawled through the buttons one at a time.** Skinning a
  button re-ran ConsolePort's `UpdateAction()` for that button, making
  ConsolePort rebuild its own art per button. That is no longer done; the
  cooldown text is driven by the plugin's own timer.
- The test harness called `Initialize()` by hand, which is why a dead-code bug
  could pass it. It now boots the module the way ElvUI does, asserts that
  nothing is skinned before login, asserts the bar is fully skinned after
  `PLAYER_ENTERING_WORLD`, and asserts that skinning does not trigger
  per-button ConsolePort rebuilds. Both bugs were re-introduced in a scratch
  copy to confirm the tests fail.

### 1.0.3

- **Fixed: the ConsolePort bar was never skinned.** Button discovery no longer
  goes through `ConsolePort:GetData().libs.registry` — that field does not exist
  (`GetData()` returns ConsolePort's *settings* table). The plugin now walks the
  real `ConsolePortBar` frame and recognises buttons by their
  `labtype-` attribute and `CPB_` name, so the skin applies on a stock install.
- Modifier satellites are picked up in both layouts. In the Minimal layout
  ConsolePort re-parents them onto the main button, so the walk descends into
  buttons instead of stopping at them.
- Pet-ring buttons are collected separately (the pet ring is not always a child
  of the bar) and are never counted twice.
- Added a geometry watchdog: buttons created later, or resized by ConsolePort,
  are re-styled within a second. It never runs in combat.
- `Reset Settings` and the unskin path now reload the bar art properly via
  `ConsolePortBar.OnLoad`.

### 1.0.2
* Fixed: `attempt to call method 'RegisterEvent' (a nil value)`. The module is now
  created with `E:NewModule("ConsolePortLK", "AceEvent-3.0")`; the missing embedded
  library meant none of the event driven skinning ever ran.
* Fixed: `ADDON_LOADED` handler used the wrong callback signature (AceEvent passes
  `(event, ...)`, there is no `self`), which would have errored on every addon load.
* Hardened: `OnInitialize` isolates each step and logs a single actionable line
  instead of an error popup, and `/cplk` falls back to a plain `SlashCmdList` entry
  if `E:RegisterChatCommand` is unavailable.

### 1.0.1
* Fixed: declaring `ElvUI_OptionsUI` in `OptionalDeps` force loaded the LoadOnDemand
  options addon at login, producing `AceDBOptions-3.0: attempt to index local 'db'`
  plus `LibElvUIPlugin-1.0: attempt to index field 'plugins'` for **every** ElvUI
  plugin. Only `ElvUI` is a dependency now.
* Plugin registration is retried when `ElvUI_OptionsUI` loads, and can no longer
  raise inside `LibElvUIPlugin-1.0`.

### 1.0.0
* Initial release.

## Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| `LibElvUIPlugin-1.0:134: attempt to index field 'plugins' (a nil value)` and `AceDBOptions-3.0: attempt to index local 'db' (a nil value)` for many plugins at login | Something force loaded `ElvUI_OptionsUI`. Make sure no addon lists `ElvUI_OptionsUI` in its `.toc` deps (this addon did in 1.0.0 and no longer does), then `/reload`. |
| `attempt to call method 'RegisterEvent' (a nil value)` | The module was created without `"AceEvent-3.0"` (1.0.1 and older). Update to 1.0.2. |
| Options panel missing under `ElvUI > Plugins` | Type `/elvui` once; if it is still missing, `/reload`. Registration is retried automatically when `ElvUI_OptionsUI` loads. |
| Nothing is skinned | 1.0.3 and older never started the skin engine at login and only worked via `/cplk skin`. Update to 1.0.4. If it still happens, check that ConsolePortLK-Enhanced is enabled and its bar is visible. |
| Buttons appear one at a time when applying | 1.0.3 and older re-ran ConsolePort's `UpdateAction` per button; 1.0.4 drew the border on a child frame that ConsolePort's satellite buttons hide. Update to 1.0.5. |
| Skin keeps disappearing and coming back, worse after `/reload` | 1.0.4 re-applied on every ConsolePort restyle signal. Update to 1.0.5 or later. |
| `Core\Skin.lua:503: attempt to call method 'SetShown' (a nil value)` | Fixed in 1.0.4. A ConsolePort `Count`/`Name` region was not a real widget. |
| Skin only appears after hovering a button | Improved in 1.0.5. The per-button refresh is re-applied on `UpdateAction`, and the geometry watchdog is unchanged. |
| Two borders, one of them white/internal | 1.0.4 and older only hid a fixed list of ConsolePort regions. Update to 1.0.5 or later. |
| White squares instead of icons | 1.0.5 filled the button background with ElvUI's theme colour and stretched the icon. Update to 1.0.6. |
| Border is 2px on some edges, 1px on others | 1.0.5 used `E.Border` (2px unless pixel mode) as the offset. Update to 1.0.6. |
| Border missing entirely, or backdrop not matching ElvUI | Fixed in 1.0.10 (the edge was drawn underneath the icon). |
| Some fixes seem to have no effect at all | More than one copy of the addon is installed. Each release extracts to a version-named folder, so delete every `ElvUI_ConsolePortLK*` folder in `Interface/AddOns` except one. `/cplk debug report` lists them. |
| Some buttons have no icon or no count text | 1.0.4 threw `SetPoint(): trying to anchor to itself`, which aborted the rest of that button. Update to 1.0.5. |
| Bar is skinned but some modifier buttons are not | 1.0.2 and older only found buttons that were children of the bar; in the Minimal layout ConsolePort parents the modifier buttons to the main button. Update to 1.0.3. |
| Skin applies, then ConsolePort art comes back after changing the layout | ConsolePort rebuilds the buttons on a layout change. 1.0.3 catches this with a watchdog; if you are on an older version, run `/cplk skin` after changing the layout. |

## Slash commands

| Command | Description |
| --- | --- |
| `/cplk` or `/cplk help` | Print the command list |
| `/cplk skin` | Skin every ConsolePort button now (also refreshes after a layout change) |
| `/cplk toggle` | Enable or disable the plugin |
| `/cplk config` | Open the options |

`/consoleportskin` and `/elvcp` are aliases.

## Public API

The plugin is a normal ElvUI module, so other addons can drive it:

```lua
local CPLK = ElvUI[1]:GetModule("ConsolePortLK")

CPLK:SkinAll()                       -- skin / refresh the whole bar
CPLK:UpdateState()                   -- re-read every option
CPLK:IsSkinned(button)               -- true when a ConsolePort button is skinned
CPLK:SkinActionButton(button)        -- skin a single action button
CPLK:UnskinActionButton(button)      -- restore a single action button
CPLK:Unskin()                        -- restore the original ConsolePort look
```

`_G.ElvUIConsolePortLK` points at the same module.

## How it works

* `Core/Profile.lua` puts the options into your ElvUI profile under
  `E.db.consolePortLK`, so copying an ElvUI profile carries the skin with it.
* `Core/Module.lua` registers the ElvUI module and resolves ConsolePort
  lazily, because ConsolePort and ConsolePortBar are optional load targets.
* `Core/Skin.lua` walks `ConsolePort:GetData().libs.registry` (ConsolePortBar's
  wrapper registry), hides the ConsolePort art for every action button, adds an
  ElvUI style backdrop and re-anchors the icon inside it. Cooldown text comes
  from hooking `SetCooldown` on each button's cooldown frame and driving an
  ElvUI formatted font string.
* ConsolePort's own cooldown text (`CPAPI.CPCC`) is suppressed while the skin
  owns the text, and handed back when you disable the option or the plugin.
* Hooks on `ConsolePortBar:OnLoad`, `wrapper:SetClassicBorders` and
  `wrapper:UpdateOrientation` re-apply the skin whenever ConsolePort rebuilds
  its art.

## Notes and limitations

* Because ElvUI's runtime does not expose a style-idle frame hook, the
  ConsolePort button width (and therefore the cooldown font size) is read from
  the button itself. Change `Border Size` or `Cooldown Text Size` if you want a
  different look than ElvUI would produce for the same button size.
* The round "Classic" ConsolePort layout keeps its crescent modifier wings,
  because those are clipped with ConsolePort's own mask renderer. The square
  presets (Minimal / Triple / Show All) are skinned completely.
* Disabling the plugin restores the ConsolePort art immediately. If anything
  still looks off, `/reload` rebuilds the bar from scratch.

## Credits

* Elv, Bunny and the [ElvUI-WotLK](https://github.com/ElvUI-WotLK/ElvUI) team.
* Azilroka, Sortokk and Bunny for [ElvUI_AddOnSkins](https://github.com/ElvUI-WotLK/ElvUI_AddOnSkins),
  which is the template this plugin follows.
* SuttonX for [ConsolePortLK-Enhanced](https://github.com/SuttonX/ConsolePortLK-Enhanced)
  and leoaviana / seblindfors for the original ConsolePort work.
