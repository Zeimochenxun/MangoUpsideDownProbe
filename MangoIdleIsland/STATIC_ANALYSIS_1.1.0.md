# MangoIdleIsland 1.1.0 — Island glass global parameter analysis

Scope: Mango 1.0-Beta7-1 supplied package, iPhoneOS arm64e binaries. This document records **static evidence** used by MangoIdleIsland 1.1.0. It is not a substitute for device validation.

## Verified refresh chain

The supplied Beta7-1 binaries contain two distinct Darwin notifications with different roles:

1. `com.go.mangoosprefs/Reload`
   - MangoOSRendering registers this notification.
   - Its callback re-reads `com.go.mangoosprefs` through the shared rendering parameter loader.
2. `go.mangoos/ParametersReloaded`
   - emitted after rendering parameters are reloaded;
   - existing `MGLiveBackdropView` instances register for this notification;
   - `MGLiveBackdropView` exposes `reapplyFilterForParameterReload`.

The binary also contains the diagnostic string `render parameters ready; refreshing %lu live filters`, consistent with the above cache-reload -> live-filter-refresh sequence.

This matters because writing CFPreferences and jumping directly to `go.mangoos/ParametersReloaded` is not equivalent to invalidating/reloading MangoOSRendering's parameter table first.

## Parameter-by-parameter answers

### `Island.Blur`

**A. MangoOSRendering direct consumer?** Yes. The rendering binary contains the group suffix `.Blur`; its shared parameter loader reads group-prefixed glass parameters, and Island maps to `go.mangoos.island`.

**B. Creation-only or runtime refresh?** Not creation-only by design. Existing `MGLiveBackdropView` objects have the ParametersReloaded -> `reapplyFilterForParameterReload` path. Separately, the known Beta7 device behavior for the MangoIdleIsland-owned Idle copy shows in-place blur reapply can make the Idle copy disappear, so Idle deliberately uses fresh-init.

**C. Existing Active glass after ParametersReloaded?** Static evidence says Mango has a native reapply path for existing live filters. 1.1.0 instruments that selector and logs whether each Island Active instance actually received it. Device validation is still required to prove every SystemAperture state receives the callback on the target phone.

**D. If Active does not reapply?** 1.1.0 does not rebuild Active glass. After the Rendering cache reload has had time to publish ParametersReloaded, it checks whether that exact Island object was observed in `reapplyFilterForParameterReload`. If not, and the runtime signature is exactly `void/no-args`, it invokes that same Mango method on the existing object as a fallback. If the method/signature is unavailable it logs `no-safe-runtime-refresh`.

**E. Idle vs Active loader?** Both are `MGLiveBackdropView` and use `filterType=go.mangoos.island`; the Idle copy is created with `groupName=Island`. They therefore enter the same Island render/material domain. 1.1.0 does not assume their owners/lifecycles are otherwise identical.

**F. Difference?** Active is Mango-owned SystemAperture content and remains under Mango lifecycle control. Idle is MangoIdleIsland-owned and can be safely discarded/re-created.

### Tint: `Island.LightTintColor`, `Island.DarkTintColor`, `.TintR/.TintG/.TintB/.TintStrength`

**A. MangoOSRendering direct consumer?** Yes for the tint parameter family. The rendering binary contains `.TintR`, `.TintG`, `.TintB`, `.TintStrength`, `.LightTintColor`, `.DarkTintColor` and passes tint data into the glass rendering uniforms.

**B/C. Runtime refresh?** Same native cache reload and live-filter reapply chain as Island glass parameters generally.

**Adaptive selection evidence.** `MGLiveBackdropView`/mangoos contains `lg_updateTint`, `traitCollectionDidChange:`, `userInterfaceStyle`, and `resolvedColorWithTraitCollection:`. This is direct evidence of a trait/style-aware tint path. The static sample does **not** prove that wallpaper luminance chooses Light vs Dark tint; MangoOSRendering does use luminance for other glass effects, but that must not be conflated with tint selection.

**1.1.0 design.** The UI changes only the alpha component of the existing Light and Dark RGBA strings and preserves each RGB independently. It never forces the two colors to the same RGB and never installs a fixed UIKit tint overlay. The old standalone `Island.TintStrength` value is cleared so the full Light/Dark RGBA values remain the single source of truth used by this control.

**Device validation still required.** Verify that Active glass retains the observed background-dependent Light/Dark appearance across notification, Live Activity and expanded states.

### `Island.SpecularEnabled`

**A. MangoOSRendering direct consumer?** No direct string evidence in `MangoOSRendering.dylib`. `.SpecularEnabled` is present in mango/mangoos and `MGLiveBackdropView` exposes `setLgSpecularEnabledOverride:`. The safe conclusion is that this parameter is consumed in the live backdrop/view layer rather than proven to be read directly by the Metal rendering module.

**B/C. Runtime refresh?** Existing live backdrop views have the native reapply path. Mango Beta7 also places an explicit specular override on some activity glass instances.

**1.1.0 handling.** The existing hook remains strictly Island-scoped through `lgFilterType == go.mangoos.island`. On a parameter reload, each existing Island Active view gets its override updated (`nil` when explicitly enabled, `@NO` when disabled) and then follows the native reapply path. Other Mango glass domains are untouched.

### `Island.SpecularOpacity`

**A. MangoOSRendering direct consumer?** No direct string evidence in `MangoOSRendering.dylib`; `.SpecularOpacity` is present in mango/mangoos. It belongs to the same MGLiveBackdropView/specular configuration path as the enable switch.

**B–F.** Same Active/Idle lifecycle split as above. Active remains in place and is re-applied; Idle fresh-inits. No second Active glass is created.

### `Island.DispersionEnabled`

**A. MangoOSRendering direct consumer?** Yes. The rendering binary contains `.DispersionEnabled` and dispersion shader/render parameters.

**B/C. Runtime refresh?** It participates in the same Rendering cache reload and live-filter reapply model.

**D–F.** Active is re-applied in place; Idle fresh-inits; filterType scope is `go.mangoos.island`.

### `Global.DispersionStrength`

**A. MangoOSRendering direct consumer?** Yes. `Global.DispersionStrength` appears directly in MangoOSRendering together with `.DispersionStrength`.

**Scope warning.** `Global.DispersionStrength` is genuinely global. MangoIdleIsland 1.1.0 keeps the settings label “光斑强度（全局）” and does not claim it is Island-only.

The existence of the suffix `.DispersionStrength` is a static lead that a group-specific key format may exist, but the supplied evidence does not establish precedence/default semantics for a real `Island.DispersionStrength` strongly enough to silently replace the known global key. 1.1.0 therefore does not invent or write an unverified key.

## Active vs Idle instance policy

Parameter scope is global to the Island material domain; instances are not global.

- **Mango Active:** retain Mango's original `MGLiveBackdropView`; never remove, replace or reconstruct it.
- **MangoIdleIsland Idle:** retain the existing safe fresh-init policy after parameter reload.
- **Handoff:** the Idle backing continues to fade against the effective opacity of the Mango-owned Island glass. It is not forced to alpha=1 under Active glass.
- **Detection:** only `MGLiveBackdropView` objects whose `lgFilterType` equals `go.mangoos.island` participate in global-Island refresh and in the idle/active handoff. Other Mango glass domains are ignored.

## Runtime diagnostics added in 1.1.0

On `go.mangoos/ParametersReloaded`:

- `[PARAMETERS] ... island-glass-count=N idle=I active=A`
- `[ISLAND-GLASS] owner=idle/active class=... ptr=... filterType=... window=... host=... alpha=... hidden=...`
- `[GLASS-REFRESH] owner=active method=reapplyFilterForParameterReload result=observed-mango-refresh`
- `[GLASS-REFRESH] owner=active ... result=invoked-fallback`
- `[GLASS-REFRESH] owner=active result=no-safe-runtime-refresh`
- `[GLASS-REFRESH] owner=idle method=fresh-init result=rebuilt`

The reapply hook records timestamps only for Island glass and does not log per-frame. The existing 500 ms bounded fallback scan and one-second transition DisplayLink remain unchanged in cadence.

## Still requires device verification

Static analysis cannot prove visual behavior on the target SpringBoard compositor. The 1.1.0 device pass must verify:

1. Idle and Active both visibly respond to Blur/Tint/Specular/Dispersion changes.
2. Active Light/Dark adaptation is retained.
3. Idle -> Active -> Idle never leaves two full-strength glass layers, duplicate specular, permanent blanking or residual views.
4. Rapid parameter changes do not crash SpringBoard or leave MGLiveBackdropView missing.
5. Status.log shows Active `observed-mango-refresh` in normal cases; repeated `invoked-fallback` would indicate Mango's native observer path is not firing as expected and should be investigated from the log rather than papered over with Active reconstruction.
