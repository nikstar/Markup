# Telegram source provenance

Upstream: [TelegramMessenger/Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS), revision `f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838`. Telegram identifies the iOS client as [GPL v2 or later](https://www.telegram.org/apps). This independent project uses that license and retains Telegram attribution in the adapted files.

The files below are on the editor's active rendering/input path. They are not unused reference copies. Every dependency needed to compile them is inside this directory.

| Local file in `Vendor/` | Original source | What is retained |
| --- | --- | --- |
| `TelegramPenTool.swift` | `DrawingUI/Sources/DrawingPenTool.swift` | Velocity smoothing, four-point spline sampling, variable-width segment envelopes, rounded caps, active-stroke taper, eraser, arrow tangent/length/arms, committed rendering, and the original RenderView with 0.4-second ink drying and 0.2-second arrowhead strokeEnd animation. |
| `../Core/TelegramStrokeInput.swift` | `DrawingUI/Sources/DrawingView.swift`, `DrawingGesture.swift` | Original 16 ms changed-event gate and image-coordinate input contract; mouse velocity is measured over accepted sample intervals. |
| `TelegramNeonTool.swift` | `DrawingUI/Sources/DrawingNeonTool.swift` | Curve accumulation, white core, colored border, shadow geometry, black-neon color behavior. |
| `TelegramMarkerTool.swift` | `DrawingUI/Sources/DrawingTools.swift` | Brush range, filtered points, minimum stroke validity, marker event forwarding. |
| `TelegramMarkerRenderer.swift` | `DrawingUI/Sources/DrawingMetalView.swift` | `Drawable`, `Brush`, `Stroke`, `BezierGenerator`, `Line`, and texture rendering; original stamp spacing, fixed rotation, overlap alpha and blend factors. |
| `Drawing.metal` | `DrawingUI/MetalResources/Drawing.metal` | Unmodified point-sprite vertex and fragment shaders. |
| `TelegramMetalTypes.swift` | `DrawingUI/Sources/DrawingUtils.swift` | Matrix, vertex/point structures and Metal coordinate conversions. |
| `TelegramGeometry.swift` | `DrawingUI/Sources/DrawingUtils.swift` | Point operations, star/bubble/arrow/curve paths and spline control-point solver. |
| `TelegramDrawingState.swift` | `DrawingUI/Sources/DrawingScreen.swift` | `DrawingToolState`/`DrawingState`, Codable state, per-tool colors and normalized sizes, update methods and original defaults. |
| `TelegramToolsPanel.swift` | `DrawingUI/Sources/ToolsComponent.swift` | AppKit port of the 40×176 brush artwork, shadows, tinted tips, gradient size bands and vertical size gesture. The Mac shelf uses fixed 44-point pointer targets, edge-aligned barrels, and pointer-driven rise and magnification. |
| `TelegramVectorEntity.swift` | `TelegramUI/Components/MediaEditor/Sources/Drawing/DrawingVectorEntity.swift` | Vector entity, Codable representation, relative midpoint, duplication and equality. |
| `TelegramVectorGeometry.swift` | `DrawingUI/Sources/DrawingVectorEntityView.swift` | Filled curved arrows, source width range and arrow proportions, normalized midpoint and three-handle drag mathematics. |
| `TelegramEntitySelection.swift` | `DrawingUI/Sources/DrawingSimpleShapeEntityView.swift`, `DrawingBubbleEntityView.swift`, `DrawingTextEntityView.swift`, `DrawingStickerEntityView.swift`, `DrawingVectorEntityView.swift` | Per-entity handle layouts, blue and green controls, screen-point sizes, dashed text and sticker outlines, and AppKit mouse transforms. |
| `TelegramShapeGeometry.swift` | `DrawingUI/Sources/DrawingSimpleShapeEntityView.swift`, `DrawingBubbleEntityView.swift` | Rectangle/ellipse/star insets, line-width ranges, bubble corner/tail geometry and tail-handle constraints. |
| `TelegramTextLayoutManager.swift` | `DrawingUI/Sources/DrawingTextEntityView.swift` | Layout-manager subclass: per-line frames, connected rounded multiline backgrounds, rectangle preprocessing and glyph stroke drawing. |
| `TelegramTextSettings.swift` | `DrawingUI/Sources/TextSettingsComponent.swift`, `DrawingScreen.swift` | Static-image style controls, original icon assets, alignment glyph dimensions, style cycling and eight font choices. |
| `TelegramColorPicker.swift` | `DrawingUI/Sources/ColorPickerScreen.swift` | Original 120-color grid, grid selection, spectrum/grayscale artwork and composition, Grid/Spectrum/Sliders modes; AppKit controls for RGB, alpha, hex and screen sampling. |
| `../Core/TelegramTextLayout.swift`, `../Editor/InlineTextView.swift` | `DrawingUI/Sources/DrawingTextEntityView.swift`, `TelegramUI/Components/MediaEditor/Sources/Drawing/DrawingTextEntity.swift`, `DrawingUI/Sources/DrawingEntitiesView.swift` | Live TextKit storage, style and contrast rules, selected-range colors, natural sizing, cancel/delete semantics, dimming and upright editing pose. The click supplies the caption center on macOS. |
| `DrawingEntitySnapTool.swift` | `DrawingUI/Sources/DrawingEntitySnapTool.swift`, `DrawingEntitiesView.swift` | Telegram’s position and rotation state machine, speed thresholds, skipped displacement, timeout, center/edge guides and selection pulse. |
| `TelegramSizeSlider.swift` | `DrawingUI/Sources/TextSettingsComponent.swift` | Tapered track, resting and tracking offsets, shadowed knob, 240-point travel area, normalized gesture mapping and 200 ms transition. |
| `../Editor/EyedropperView.swift` | `DrawingUI/Sources/EyedropperView.swift` | 148-point lens, 15× nearest-neighbor pixels, sampled ring, adaptive grid, center cell, spring entry and shrinking dismissal. |
| `TelegramFastColorButton.swift` | `DrawingUI/Sources/ColorPickerScreen.swift`, `DrawingScreen.swift` | Spectrum-ring artwork, 400 ms hold, drag sampling, circle-mask reveal and closing fill. |
| `../Editor/CanvasView.swift` | `DrawingUI/Sources/DrawingView.swift` | Hold-to-fill timing, drawing-layer separation, marker alpha, erase and blur behaviors. Existing single-layer projects retain their compositing order. |

Paths in the Original source column are relative to upstream `submodules/`. Exact paths and hashes are recorded in `SourceManifest.json`.

## Platform adaptations

`TelegramPlatform.swift` provides a small AppKit/Core Graphics adapter for the original names (`UIColor`, `UIImage`, `UIBezierPath`, `DrawingPoint`). These are local aliases/wrappers, not UIKit imports. AccountContext, ComponentFlow, UIKit view classes, touch recognizers, and Telegram's build graph are removed. Core Graphics calculations and Metal stamping are preserved; their presentation surfaces become AppKit views and an offscreen Metal texture.

The marker's texture readback waits for its command queue. Metal matrix identity returns a fresh instance instead of shared mutable state. Neon uses a larger offscreen shadow displacement for screenshots above 3,000 pixels; the source's fixed displacement would leave a duplicate on large Mac screenshots. Core Graphics shadow Y offsets are converted from UIKit to the bitmap coordinate convention for neon and text. The text layout manager enumerates glyph count instead of UTF-16 character count so emoji and ligatures remain valid under AppKit. Vector midpoint dragging guards coincident endpoints. Color-grid boundaries clamp to the last valid cell.

`Core/TelegramStrokeRenderer.swift` adapts editable document samples to the copied tools and caches their output. Mouse input stores velocity and normalized brush size, uses the source zoom adjustment, and passes a distinct terminal mouse-up sample. Changed events use the source 16 ms gate instead of feeding every high-frequency mouse event into the per-sample width filter. Velocity is measured over that accepted interval to suppress device delivery jitter; UIKit's private pan-velocity estimator is not available on AppKit. New recordings mark the terminal sample so replay sends it once as .ended; older projects keep their recorded replay semantics. If AppKit coalesces a fast drag to two distant endpoints, the input adapter supplies one midpoint for the original spline engine; the engine itself is unchanged. No pressure-width substitute is used.

The window/document/export shell, selection of raster strokes, crop, source blur preparation, system-wide sampler, offline sticker picker and desktop integrations are AppKit code. The pen/arrow live RenderView is now ported, including original drying paths, 512-segment accumulation, the 50 ms release delay and rounded wings revealed from tip to end with 200 ms ease-in/ease-out strokeEnd animations. AppKit callbacks replace Display animation helpers. The desktop model commits immediately for Save/Copy/Undo, while the canvas temporarily hides that model stroke behind its preview until the animation settles. Completed wings remain visible during the last drying frames, avoiding a disappearance before the bitmap handoff.

## Artwork and verification

Original tool bodies, tips and shadows, marker texture, spectrum/grayscale images, and four text-style icons are copied unchanged into `Resources/`. `SourceManifest.json` records their upstream paths and SHA-256 hashes, together with hashes of all source files used. The app name and application icon are independent.

`Tests/TelegramPortTests.swift` exercises source defaults, velocity taper, arrow dimensions and tangents, vector midpoint persistence, GPU replay consistency, glyph backgrounds, input adaptation, palette boundaries and persisted fields. The caption suite also compares AppKit output against four iOS reference rasters in `Tests/Fixtures`. See `Testing.md` for the reference inputs and measured differences.

The AppKit toolbar effect adapts the alpha-mask Core Animation filter configuration from [VariableBlur](https://github.com/nikstar/VariableBlur). The canvas supplies the composited screenshot and annotations. Its layout determines both mask directions and keeps the central image and toolbar controls sharp. The MIT notice is included in `Resources/NOTICE.txt`.
