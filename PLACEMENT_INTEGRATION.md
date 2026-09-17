# Integrated System Aperture placement

This branch folds the device-tested placement logic from the old standalone `MangoUpsideDownFix` into `MangoUpsideDownWorld`.

## Ownership split

- `Tweak.xm` continues to own the whole `SBSystemApertureWindow` half-turn, content normalization, hit-testing/gesture diagnostics, and orientation-lock behavior.
- `WorldPlacement.m` owns only Mango-confirmed `SBSystemApertureContainerView` translation.
- `Geometry.h` contains the platform-independent opposite-edge translation arithmetic previously used by the standalone Fix.

The placement module never adds another rotation. It requires all of the following before it can move a container:

1. Mango reports `UIInterfaceOrientationPortraitUpsideDown`.
2. The host was observed through `MangoPillElement -layoutHostContainerViewDidLayoutSubviews:` and resolves under `SBSystemApertureContainerView` inside `SBSystemApertureWindow`.
3. The aperture window already has an inverted basis in `UIScreen.fixedCoordinateSpace`, proving World's own window turn is active.
4. The container baseline still lies in the physical upper half of the screen. If World has already placed it in the physical lower half (visual top while the phone is upside down), the placement module is a no-op.

Compact/media hosts that are reported before attachment retain the old alpha2 weak pending queue behavior and are rechecked for up to 30 seconds.

## Package relationship

`MangoUpsideDownWorld` 1.1.0 still `Conflicts`/`Replaces` `com.chenxun.mangoupsidedownfix`. This is intentional: the standalone Fix must not be loaded at the same time because its container hooks are now inside World.

After installing World 1.1.0, only World should remain installed. Sileo removing the old Fix is expected and no longer removes the placement behavior.

## Logs

The integrated module writes to the existing World log:

`/var/mobile/Library/Logs/MangoUpsideDownWorld.log`

Placement lines begin with `PLACEMENT`, for example:

- `PLACEMENT INSTALLED ...`
- `PLACEMENT TRACK ...`
- `PLACEMENT PENDING ...`
- `PLACEMENT APPLY ...`
- `PLACEMENT SKIP already at physical lower edge`
- `PLACEMENT RESTORE ...`
- `PLACEMENT SUSPEND ...`

A normal case where World's window turn already places the island correctly should produce `SKIP already at physical lower edge`, not `APPLY`.
