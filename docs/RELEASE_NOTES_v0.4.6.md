# FinderSearch v0.4.6 — Navigate and organize your sidebar

## Mouse Back and Forward

Use your mouse’s side buttons to navigate the active tab, just like the toolbar. Navigation respects open sheets and file operations, while other mouse buttons keep their existing behavior.

## Favorites, in your order

Drag any favorite, including the standard folders, into the order you prefer. A floating row follows your pointer, and a blue insertion marker shows where it will land. Release to place it, or press Esc to cancel.

Your order and removed shortcuts are saved across launches and synchronized between windows. Existing custom favorites carry over automatically, and the selection highlight stays with the folder you are viewing.

## Useful sidebar menus

Right-click a favorite to open it, open it in a new tab, reveal it in Finder, or remove it from the sidebar. Removing a shortcut leaves the folder and its contents intact. Location menus also provide navigation actions and Eject for removable volumes.

## Download and install

Download **FinderSearch-0.4.6-AppleSilicon.dmg**, open it, and drag FinderSearch into Applications. Requires Apple Silicon and macOS 15 or newer. A SHA-256 checksum is included.

This release uses an ad-hoc signature and is not notarized by Apple. If macOS blocks it, use System Settings → Privacy & Security → Open Anyway.

## Validation

**119 release-mode tests passed.** The regression checks cover mouse event routing, favorite migration and persistence, synchronization between windows, drag preview movement and cleanup, and Escape cancellation. Sidebar reordering and selection were also checked in the built app.

One pre-existing icon-grid layout test is excluded; its failure was reproduced on unchanged `main`.
