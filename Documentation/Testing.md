# Verification record

Verified locally on macOS 27.0.1 with Xcode 27.1 Release Candidate and the macOS 27 SDK. Initial checks: 29 October 2026; arrow lifecycle regression checks: 2 November 2026.

## Build and isolation

- The `Markup` app and embedded `MarkupAction` extension build in Debug and Release with local ad-hoc signing.
- The entire source directory was copied into a fresh temporary directory outside the Telegram checkout. Its checked-in `Markup.xcodeproj` built successfully in Release without the parent repository, Bazel, downloaded packages, UIKit or SwiftUI.
- Tool images, original marker texture, spectrum images, text icons, license and compiled `default.metallib` are included in both targets.
- `Scripts/make-fixtures.sh` builds a small local fixture bundle with the same shader library and resources, then generates `Sample.png`, `Example.markup` and `Example.png` through the application renderer.

## Core and native event tests

`TestResults/ArrowLifecycle4.xcresult`: **45 tests passed, 0 failures** (including the original 39). Run again with `Scripts/test.sh`.

Coverage includes source-image dimensions and EXIF orientation; image/project validation and round-tripping; source-preserving erasing; crop/redaction/blur/pixelation; undo/redo/branching/dirty state; text styles and connected multiline frames; exports to PNG/JPEG/TIFF/PDF; extension image-provider round-trip; native AppKit drawing, selection and crop events; original brush defaults; velocity taper; arrowhead size/direction; vector midpoint behavior; sparse mouse-input adaptation; marker incremental/replayed GPU consistency; neon white core and colored glow; bundled resources, palette boundaries, and grid/spectrum mouse coordinates.

## Arrow input and animation regression (2 November)

The source comparison found three omitted contracts: DrawingView's 16 ms changed-event gate, PenTool.RenderView's drying/reveal layers, and a distinct terminal sample. Raw adjacent mouse-event velocities changed width smoothing with device event rate; all animations were explicitly disabled; replay sent the final new sample as both `.changed` and `.ended`.

`StrokeLifecycleTests` verifies:

- A 1,000 Hz stream delivered in position bursts produces the same accepted positions and velocities as the source cadence, including a terminal event inside the throttle interval.
- In an actual on-screen AppKit window, both rounded arrowhead layers have partial `strokeEnd` values during their 200 ms ease-in/ease-out animation. This tests the presentation tree, not just animation settings.
- Pen and arrow retain the original 400 ms linear drying layers and width factor.
- Release waits 50 ms, starts both wings, and automatically hands off after reveal/drying without another pointer event.
- Native mouse release commits exactly once; Save/reopen matches the complete stroke during animation; Undo cancels the preview and no delayed callback re-adds the stroke.
- Incremental and fresh replay match for pen, arrow, marker, neon, eraser and blur. New pen/arrow recordings also match direct source-engine `.began`/`.changed`/`.ended` replay.

A native mouse drag was also exercised in an isolated `dev.nikstar.Markup.ArrowTesting` app and its complete arrow inspected. The user's existing running app was not terminated or replaced. The new release build is in `build/ArrowRelease/Build/Products/Release/Markup.app`.

## Native UI testing

The UI suite uses `dev.nikstar.Markup.UITesting` and a separate build directory, so it cannot terminate the ordinary installed app. Use `Scripts/test-ui.sh`.

- Draw → Undo → Redo → Copy passed in `SourcePortUI3.xcresult`.
- Insert rectangle → Duplicate → Delete → Add text passed in `SourcePortUI4.xcresult` and `SourcePortUI5.xcresult`.
- The full UI suite is **not consistently green in this active desktop session**. XCTest records Codex windows as input interruptions; on repeated runs its synthesized initial drag sometimes never reaches the canvas. The core suite separately dispatches real `NSEvent` objects directly to the AppKit canvas, including the source arrow workflow, without foreground-window dependence. This is a testing limitation, not a claimed all-green UI run.

Manual native UI checks on an isolated preview app confirmed tool selection, pen drawing, a freehand arrow after mouse coalescing adaptation, original brush dragging (21 px → 49.728 px), inserting and bending a filled vector arrow, and project save. Color-grid/spectrum rendering was inspected, and native mouse coordinates and selected RGB values are covered by the event test. Earlier shell-level checks confirmed image opening, editable project reopen, text editing/duplicate/delete/undo/redo, clipboard image import, and native PNG export at original dimensions. Temporary smoke artifacts are in `/tmp/Markup-Source-Curve.markup`, `/tmp/Markup-Source-Arrow-Final.markup`, `/tmp/Markup-Smoke.markup` and `/tmp/Markup-Smoke-export.png`.

## Integration and fidelity limits

LaunchServices image types and the embedded extension register locally. The shared extension data transport is tested. Host-mediated invocation and return from Preview/Quick Look, Finder's actual Services context menu, and interactive screen capture have not been fully exercised. Their availability and setup are documented in `Integrations.md`; registration alone is not proof of host support.

This verifies copied algorithms, platform adaptations and desktop workflows. It is not a side-by-side pixel-equivalence test against a running iOS Telegram editor. `Provenance.md` explicitly identifies the reused code, adaptations and UI differences. Cloud stickers, animated/video/story/account features are outside this still-image app.

## Quick markup, selection and zoom (19 November 2026)

The macOS target was recorded at normal speed using ScreenCaptureKit restricted to the recorder's own AppKit window. The window stayed at desktop level and the foreground application was the same before and after recording. Reference expectations were eight screen-sized shape handles, a stationary opposite corner during resize, paired text handles rotating around the text center, and zoom pinned to the indicated image point.

The 109 recorded frames use the capture timestamps reported by ffprobe. Frames 0–12 (0.000–0.765 s) show the red rectangle expanding down and right with the opposite corner fixed. Frames 14–26 (1.198–1.648 s) show the text rotating clockwise, with both handles following it. Across frames 27–38 (1.897–2.282 s), the midpoint of the two blue handles stays within one screen point of (477, 258) as the canvas magnifies. Frames 39–108 cover ellipse and star resizing, bubble tail movement, emoji scaling/rotation and the curved vector handle. The flagged intervals at frames 27 and 39 include intentional rests before zoom and Fit. The jumps at 53, 67 and 81 are switches between test objects.

The hosted tests invoke NSDocument's Save action on a temporary PNG, check the bytes at the original URL, reopen the flattened image and editable project copy, and undo in the open document. Additional cases cover JPEG/TIFF format selection, multipage import, rotated and mirrored handle geometry and pixel-scale zoom with a crop and pan.

## Inline editing and UIKit reference comparison (19 November 2026)

The Markup scheme passed all 61 hosted tests on macOS. The text tests exercise insertion by click, typing, selection-range color, multiline layout, resizing, undo, cancellation and Save during an edit. Four image fixtures in `Tests/Fixtures` came from Telegram’s `DrawingTextView`, `DrawingTextLayoutManager` and `DrawingTextStorage` on an isolated iOS 27 simulator. Each renders “Check this” and “label” on consecutive lines in 48-point semibold system type on a gray 400 × 220 canvas.

AppKit and UIKit produced the same visible bounding box for each style. Counting pixels where any RGB channel differs by more than 16 out of 255, the differences were 52 pixels for Filled, 37 for Semi, zero for Stroke and zero for Regular, out of 88,000 per fixture. These fixtures caught a background stroke inheriting the brush width, double-counted line padding and a baseline difference from AppKit rounding font metrics.

`Scripts/test-visual.sh` recorded the production editor views using a private, nonactivating AppKit window. The three recordings registered zero recorder activations. Frame numbers below use ffprobe presentation timestamps.

- **Typing and zoom.** In `text.mp4`, frames 19–24 show two lines appearing in place and the selected word changing color. Across frames 25–32 (1.838–2.065 s), the text and its background enlarge together at the indicated point, without rewrapping. Frames 33–48 show Done restoring the screenshot brightness around the caption. Frame 68 (3.012 s) restores the saved words on Escape, and frame 80 shows the settled selection. The longer intervals are between scripted typing, zoom and keyboard events.
- **Rotation, sizing and fill.** In `controls.mp4`, frames 2–24 bring the rotated caption upright and frames 25–47 (0.933–1.343 s) return it to its saved angle. Frame 48 starts another edit. Frames 66–92 show the left size control changing the caption around its center, and frame 93 applies the edit. Frames 136–143 show the eyedropper following sampled pointer positions. Frame 154 applies the color, and frame 156 changes tools. Frames 181–198 (4.327–4.627 s) show the brush fill spreading below the caption. Frame 200 switches to the undo and object-selection case.
- **Color controls.** In `colors.mp4`, frames 1, 3 and 4 show the grid, spectrum and RGB controls. Frame 6 dismisses the picker. Frames 27–45 (1.823–2.145 s) show the spectrum expanding from the held color swatch. At frame 58 the release begins the reverse reveal, with the chosen color filling the closing field.

The UIKit pixel comparison covers the caption fixtures. The macOS recordings exercise the surrounding interaction and motion. Finder, Preview and Quick Look invocation still depend on the host checks described above.

## Quick Look window appearance (21 November 2026)

All 63 hosted tests passed. The window tests exercise the Open button through the title-bar hit region, dropped PNG file URLs and pasted image data on a private drag pasteboard, and export at the smallest document window size in both system appearances.

ScreenCaptureKit recorded the two production window layouts over a separate test window that supplied the backdrop. The recorder used a prohibited activation policy and registered zero activations. The empty window measured 372 × 224 points. Its close and expand buttons and Open Image action stayed fixed when the test backdrop changed in frame 27 (0.525 s). Frame 57 (1.108 s) switched to the editor. Comparing frames 77 and 105 across the next backdrop change, a patch in the left glass margin changed from RGB (151, 174, 241) to (225, 172, 148). The 564 × 343 point interior of the image had identical decoded pixels in both frames.

Frame 114 selected Text, frame 144 began inline editing, and the longer interval before frame 155 occurred during the editing dimmer. The shelf stayed below the canvas. Frames 193 and 217 show the dark editor and the dark empty window. The sharp transitions at frames 27, 57, 88, 114, 193 and 217 correspond to deliberate backdrop, window, tool and appearance switches.

## Zoom beneath the toolbars (21 November 2026)

The zoom scenario in `Scripts/test-visual.sh` exercises a native titled window, pointer-anchored magnification, space-drag panning and Fit. Hosted tests also exercise the extension layout, partial overlaps, toolbar hit testing and the original image export.

A separate 175-frame recording used a synthetic desktop behind the production window. Frames 21–22 (0.367–0.383 s) show the first two zoom steps. The second step pauses with just a sliver of image under the title bar. The glass side margins stay clear. Frames 39–69 (0.675–1.200 s) continue to 250%. In frames 89–113 (1.550–1.975 s) the color boundaries travel beneath the stationary controls. Frame 131 switches to dark appearance, and frame 151 restores Fit. The flagged changes correspond to these gesture endpoints and appearance changes. The recorder registered zero activations.

A same-position capture with both blur layers hidden provided a sharp reference. Its central 1,270 × 779 pixel rectangle matched the normal zoomed window pixel for pixel. In a sample of 10-point-wide repeating stripes, measured contrast fell to 1% of the reference 20 points into the title bar and 8% at 24 points into the bottom shelf. Restricting the backdrop layers to the image’s intersection with each toolbar fixed a black fringe visible in early whole-canvas filter trials.
