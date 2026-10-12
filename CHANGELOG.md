# Changelog

## 0.4.7 — 2026-10-12

- Fix editing shortcuts in Go to Folder.
- Show colored tags in every view and preserve their colors through Undo.
- Add folders to Favorites by dropping them onto the sidebar.
- Refresh bundle icon registration after updates.

## 0.4.6 — 2026-10-11

- Fix mouse Back/Forward buttons.
- Reorder sidebar favorites with a live drag preview; order is saved.
- Add sidebar right-click menus to open, reveal, remove, or eject.

## 0.4.5 — 2026-10-11

### Cut, paste, and keep your place

- **Cut text again:** Cmd+X works in the search field and other text editors.
- **Move files with Cmd+X → Cmd+V:** cut files and folders, then paste them into another location, tab, or window. Items stay put until the move succeeds, with conflict handling and Undo available.
- **See what is cut:** pending items appear dimmed in icon, list, column, and gallery views. Pasting or copying something else clears the dimming; failed or skipped items remain ready to retry.
- **Keep your clipboard safe:** copying an empty selection leaves it intact, and finishing a move never replaces something you copied afterward.

### More reliable cloud-folder indexing

- **Recover after granting Full Disk Access:** restart this installation’s restricted search daemon once per app session so previously skipped folders, including `~/Library/CloudStorage`, can be rescanned. The existing index is preserved, and other fsearch installations are left alone.
- Clarify Dropbox setup and cloud-only folder limitations in the usage guide. Folders must be locally enumerable; indexing does not intentionally download cloud file contents.

Verified with 115 passing tests and manual checks of text cutting, file/folder moves, Undo, and cut appearance in all four views.

## 0.4.3 — 2026-10-10

- **Faster folder loading:** bulk metadata reads are ~14× faster for regular files and ~36× faster for APFS subfolders; subfolder listing plus sorting is ~8× faster.
- **Faster sorting:** reuse filename order after metadata refreshes (~15×) and reverse valid cached order when changing direction (~21–71×).
- **Faster selection:** indexed row lookups make sparse selection updates ~1,700× faster in large folders.
- **Faster bulk-action UI updates:** batch trash removals (~397×) and index move/copy updates (~657×/~345×), preserving operation order and failure reconciliation.
- **Less main-thread work:** stop prefetch discovery after three folders; measured post-load work is ~16× faster.

Benchmarks use release builds and 10,000–30,000-entry fixtures. Figures compare individual stages with their previous implementations; they are not whole-app or disk-transfer speedups. Filesystem measurements use warm local caches. Verified with 109 passing tests.

## 0.4.2

- Reduced combined icon and thumbnail cache budgets by 75%, bounded image decoding resolution, and released offscreen images sooner.
