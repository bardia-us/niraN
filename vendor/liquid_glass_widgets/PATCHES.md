# Local Windows compatibility patches

Source: published `liquid_glass_widgets` 1.8.1, MIT license retained.
Upstream: https://github.com/sdegenaar/liquid_glass_widgets
This package is vendored locally in niraN; shared Pub-cache files are not changed.

## Geometry coverage

Upstream computes smoothstep coverage across the edge, then discards every
pixel with sdN >= 0, removing the outer half of the antialiasing window.
On native Windows at DPR 1, tool/edge_coverage_probe.dart measures alpha 0
where the existing 1px smoothstep should produce alpha approximately 40/255.

Keep that coverage and clamp only the optical surface distance to zero.
No changes to blur, frost, rim strength, refraction or material presets.
Native probe and visual review are separate checks; this patch is experimental
until the visible dotted edge is checked in the app.

## Subpixel rim sampling

The user confirmed the coverage patch improves the edge but a little aliasing
remains. The original hairline profile spans 0.25 to 0.667 physical pixels at
DPR 1. A native two-stage probe on constant white, moving the same edge through
eight 1/8px phases, measures total shade [29,60,68,55,40,25,13,5]: spread 63.
This isolates rim sampling from interleaved frost and changing backgrounds.

When the profile is narrower than a projected pixel footprint, average its
existing smoothstep analytically across that footprint. The width, intensity,
lighting recipe, blur and refraction settings remain unchanged; well-resolved
profiles use the unchanged original sample. No global supersampling is added.
The analytic SDF-normal footprint avoids derivatives after the alpha early-out.

Patched tool/rim_sampling_probe.dart: [37,45,48,45,39,32,29,30], spread 19
(regression budget 30): PASS. This is reduced sampling instability, not proof
that all visual aliasing is eliminated or that the user approved the final rim.

## niraN startup readiness (no optics changes)

Expose `LiquidGlassWidgets.premiumShadersReady` as a read-only cache check.
The upstream precache loader can report errors yet complete normally. niraN
uses this to select the shader-free fallback after failure/timeout instead of
mistaking initialization completion for a usable premium renderer. Material
settings, rendering algorithms and shaders remain the sandbox recipe.

## Stable desktop menu hover

`GlassFocusRegion` uses physical `MouseRegion` entry/exit for hover instead of
`FocusableActionDetector.onShowHoverHighlight`. The latter follows the global
keyboard/touch focus-highlight mode and can clear hover with a stationary mouse.
Keyboard focus rings and activation remain with `FocusableActionDetector`.
Track pointer presence separately so disabling/re-enabling a control under the
same pointer updates its hover correctly. App regression tests cover sustained
hover, input-mode changes, exit/re-entry and enabled-state changes.
