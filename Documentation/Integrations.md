# macOS entry points

## Finder and Quick Look

The app registers PNG, JPEG, TIFF, HEIC/HEIF, GIF, BMP, and WebP as alternate editable image types. After installation, select **Open With → Markup** in Finder. Drag a screenshot onto the app icon or the welcome window. In Quick Look, use its **Open With** control when the host offers a choice; alternatively close Quick Look and use Finder's Open With menu.

The built-in Quick Look/Preview **Markup** button belongs to Apple's editor. There is no public supported API to replace that button globally. This app does not inject into Preview or disable System Integrity Protection.

## Services and context menus

The registered **Open in Markup** service accepts image data and image file URLs. In Finder it is available through **Services → Open in Markup** when macOS exposes eligible Services in the selection's context menu. In Preview or another image app, use the application's **Services** menu if it supplies the selected image/file. A Services shortcut can be assigned in System Settings → Keyboard → Keyboard Shortcuts → Services.

Clipboard works consistently when a host does not expose a Service: Copy the image, then use Markup's **New from Clipboard** (`⇧⌘N`) or its menu-bar entry. Plain Paste in an existing editor inserts an image as a sticker.

## Action extension

`MarkupAction.appex` is embedded in the app. It declares `com.apple.ui-services`, editor role, single-image activation, and a toolbar item. It receives the host's image through `NSItemProvider`, displays the same AppKit editor, and returns a flattened PNG when the user selects Done. Cancel cancels the extension request and returns no edited content.

Install the containing app first. If the extension is not visible, inspect **System Settings → General → Login Items & Extensions** and the appropriate editing/sharing extension category. Host applications decide whether they expose editing extensions and whether they accept returned edits. Registration alone does not guarantee that Preview or Quick Look will list it. The Services, Open With, and clipboard entry points remain available independently.

The extension is sandboxed, with user-selected file access. The containing app is not sandboxed and is intended for direct installation. It does not need an App Store account. Ad-hoc builds are for this Mac; distribute a Developer ID signed and notarized build for normal Gatekeeper behavior on other Macs. Both the app and its extension should use the same signing identity.

## Capture

With Markup running, take a screenshot with the usual macOS shortcut. A translucent target appears eight points above the system thumbnail on the same display. It matches the thumbnail’s width and measures two-thirds of its height. Narrow thumbnails use a pencil icon. Drag the thumbnail onto it to open the editor. The target goes away when the thumbnail expires. This uses the **Show Floating Thumbnail** option in the macOS screenshot toolbar (⇧⌘5 → Options).

You can also drop images onto the menu-bar pencil at any time. Choose **Settings…** from the pencil or the Markup menu (⌘,). Enable **Launch at login** to start the pencil and screenshot monitor without opening a window or adding a Dock icon. Opening an image brings up the editor. Images dragged from Finder keep their file location. A screenshot supplied as a file promise opens as a new image with its suggested name and gets a PNG in the configured screenshot folder on the first edit. Later edits autosave there.

The menu-bar command and `⇧⌘2` run the macOS interactive screenshot picker. Drag a region; press Space to select a window; press Escape to cancel. Markup temporarily hides its own normal windows while the picker runs and opens the captured PNG afterward. macOS may request Screen Recording access; this project does not alter that privacy setting automatically.

## Command line

```sh
open -a Markup /path/to/screenshot.png
open -a Markup /path/to/project.markup
```

## References

- [Apple: Action extensions](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Action.html)
- [Apple: extension property-list keys](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/AppExtensionKeys.html)
- [Apple: Services properties](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/Articles/properties.html)
