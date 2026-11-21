# Editing screenshots


Drop a screenshot into the compact glass window or choose **Open Image…**. The document uses the same translucent backdrop around the image and behind the bottom tool shelf. At Fit the full image sits between the toolbars. Zoom or pan and it continues beneath them, with progressively stronger blur toward either window edge. The window follows the system appearance.

- **Pen, arrow, marker, neon, blur, eraser:** the six screenshot drawing tools in Telegram's editor, directly ported from Telegram. The original velocity-sensitive pen/arrow, spline neon, and textured Metal marker run behind AppKit mouse/trackpad input with the source event cadence. Pen and arrow preserve Telegram’s live ink-drying transition; releasing an arrow reveals its two wings over 0.2 seconds. Pause at the end of a pen stroke to recognize a line, rectangle, or ellipse.
- **Line, rectangle, ellipse, star, speech bubble:** editable shapes, with color, width, opacity, and fill controls. Line supports no, one, or two arrowheads. Vector arrows use Telegram’s filled curve; drag their green center handle to bend and blue endpoints to redirect. Speech bubbles have an editable tail handle.
- **Text.** Press **T** or choose **Text**, click the screenshot, and type. Return adds a line. Click outside the caption, choose Done, or press ⌘Return to apply. Escape or Cancel restores the previous caption. Double-click a caption to edit it. The shelf changes font, style, and alignment. Drag the size control on the left to resize. Select a word before picking a color to change just that word. ⌘S includes what you are typing.
- **Stickers:** local image stickers, transparency, emoji, and drag-and-drop images. They can be resized, moved, rotated, flipped, duplicated, or reordered.
- **Select:** drag to move; drag a blue edge or corner handle to resize a shape. Drag a side handle on text or stickers to scale and rotate around the center. Shift constrains proportions or rotation. Arrow keys nudge; Shift-arrow moves ten pixels. Drag slowly to snap to the screenshot center or edges. A guide shows the alignment. Option frees the drag. Right-click an object for its actions.
- **Pixelate, redact, fill:** additional tools in the inspector's tool menu. Redact draws opaque black rectangles regardless of the opacity control.
- **Crop:** drag a region. Crop retains the full source and all annotations; Reset Crop in Properties or the Crop button’s context menu restores the full image. Undo/redo includes cropping.
- **Navigation:** pinch or Command-scroll to zoom around the pointer. Actual Pixels (⌘1) maps an image pixel to a display pixel. Zoom in or out to reveal Fit beside Crop. Fit (⌘0) restores the default zoom and centers the image. Space-drag or scroll to pan; Fit resets the view. Drawing and export coordinates are original image pixels.

Holding a brush still for 0.7 seconds fills the drawing layer. Marker applies a translucent fill, Blur blurs the screenshot, and Eraser clears the ink. Captions and shapes stay above this layer. Each fill can be undone. Single-click an existing object with a brush to select it.

The bottom shelf centers Telegram’s six brushes at the window edge. Hover to magnify a brush. The active brush stays raised and enlarged, and dragging it vertically changes its size. Draw and Text switch the center controls in place. The two-row palette includes nine quick colors, with black below the spectrum ring. On narrow windows, the palette and controls sit above the centered brushes. The Shapes button beside Stickers includes Select Objects. Click the spectrum ring to open the color picker, or hold it and drag to choose a color in one gesture. Pick from Image samples original image pixels at the current zoom. Brush colors and sizes carry over to new windows. Text selection replaces the shelf with the source style icons, alignment control and font choices. Additional desktop controls are in Properties. All UI uses AppKit.

Open **Markup → Settings…** (⌘,) or choose **Settings…** from the menu-bar pencil. **Pan direction** follows system scrolling by default. Choose **Reversed** for the previous behavior. **Launch at login** starts the pencil and screenshot monitor with no window. Opening an image or clicking the app in Finder opens the regular interface.

## Files and shortcuts

| Action | Shortcut |
| --- | --- |
| Open image/project | ⌘O |
| New from clipboard | ⇧⌘N |
| Capture region/window with system picker | ⇧⌘2 |
| Save the current image or project | ⌘S |
| Save As | ⇧⌘S |
| Export image | ⇧⌘E |
| Copy rendered image | ⌘C |
| Undo / redo | ⌘Z / ⇧⌘Z |
| Duplicate selected object | ⌘D |
| Import image sticker | ⇧⌘I |
| Select / pen / arrow / marker / neon | V / P / A / M / N |
| Blur / eraser / rectangle / ellipse / text / crop | B / E / R / O / T / C |

`.markup` projects store the normalized source image plus editable annotations. Single-frame PNG, JPEG, and TIFF images autosave in place after a short pause and when closing. With **Keep edit history** enabled (the default), Markup keeps the editable source, layers, and up to 80 undo steps in its private Application Support folder. Reopening the image on this Mac restores the history, including redo. Markup checks the saved image’s SHA-256 digest before restoring its history. Turn history off to save only the flattened image. Undo continues to work while the image is open. The next save clears that image’s local history. Other images retain theirs. Choose **File → Save Editable Project Copy…** for a portable layered document.

Screenshot thumbnails, clipboard images, and blank canvases get a named PNG in the macOS screenshot folder on the first edit. Other input formats and multi-frame images get a separate PNG beside the input file on the first edit. Name collisions use a numbered suffix. ⌘C copies the rendered image including the current caption. **Edit → Copy Selected Text** copies just a text selection. Export flattens to PNG, JPEG, TIFF, or a one-page PDF; JPEG receives a white background. The Copy button copies PNG at original resolution. Only the first frame of animated image input is imported, appropriate for still screenshots. Images are normalized for EXIF orientation; source metadata is not copied to exports. Imports are limited to 16,384 pixels per side and 80 megapixels.

Blur and pixelate sample the source screenshot. Use an opaque redaction for material that must not remain readable. Editable projects retain the original source; share a flattened export when redaction matters.
