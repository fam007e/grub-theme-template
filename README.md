# GRUB Theme Template

A configurable GRUB theme base: swap the background, font(s), colors, and
menu layout via one config file — no hand-editing `theme.txt`, no
hex-managing `.pf2` fonts.

## How this actually works with GRUB (read this before editing)

GRUB's theme engine has two behaviors this repo depends on, and getting
either wrong produces a theme that silently fails to render text — not a
crash, just missing labels — which is a nasty thing to debug on a
bootloader. So, stated plainly:

1. **Fonts are matched by name, not filename.** Every `.pf2` font file has
   a name string baked into its binary header (a `NAME` chunk). When
   `theme.txt` says `item_font = "Foo Bold 16"`, GRUB looks for a loaded
   font registered under that exact string — the file could be called
   anything. `common.sh` never assumes what `grub-mkfont` named the file
   it just built; it reads the name back out of the generated `.pf2`
   before writing `theme.txt`, so the two can never mismatch.

2. **GRUB auto-loads every `.pf2` sitting flat next to `theme.txt`** when
   the theme is applied — there's no `loadfont` command anywhere in this
   repo's `grub.cfg` snippet, and there doesn't need to be. This is also
   why generated/copied fonts always land directly in the theme directory
   with no subfolders — a `.pf2` one level down wouldn't be picked up.

3. **A broken theme doesn't break booting.** If `theme.txt` is missing or
   malformed, GRUB falls back to its plain text menu — it does not fail
   to boot. The only things in this repo that touch boot-critical config
   are `GRUB_THEME`/`GRUB_GFXMODE` in `/etc/default/grub`, which
   `install.sh` backs up first (`/etc/default/grub.bak`), and
   `grub-mkconfig`, which is GRUB's own well-tested config generator —
   this repo never hand-edits `grub.cfg`'s boot entries.

## What's configurable

- **Fonts**: point `FONT_FILE` at any `.ttf`/`.otf` — a system font path
  or one dropped in `fonts/`. A `.pf2` per size the theme needs
  (title/item/timeout/terminal) is generated at install/test time via
  `grub-mkfont`. Each role can also override the typeface
  (`FONT_ITEM_FILE`) or skip generation entirely and use an existing
  `.pf2` (`FONT_ITEM_PF2`) — see the commented examples in
  `theme.conf.example`.
- **Background / highlight pixmap**: `BG_IMAGE` / `SELECT_PIXMAP`, any
  `.png`/`.jpg`/`.tga` (the formats GRUB's gfxmenu actually supports —
  the scripts warn if an extension looks off, though extension isn't a
  perfect proxy for actual format).
- **Colors**: `ITEM_COLOR`, `SELECTED_ITEM_COLOR`, `TIMEOUT_COLOR` — plain
  hex.
- **Layout**: `MENU_LEFT/WIDTH/TOP/HEIGHT`.
- **`theme.txt.template`** holds the real GRUB theme syntax with
  `__PLACEHOLDER__` tokens; `common.sh` fills them in. Edit this file
  directly if you want to change the layout structure itself (add labels,
  move the terminal, etc.) rather than just colors/fonts/position.

## Quick start

1. Pick a starting point:
   ```bash
   cp presets/haikyuu.conf theme.conf     # or nord.conf / dracula.conf
   ```
   or start blank: `cp theme.conf.example theme.conf`
2. Edit `theme.conf`: set `FONT_FILE`, drop your background into
   `assets/bg.png` (or point `BG_IMAGE` elsewhere), tweak colors.
3. **Test before touching your real bootloader:**
   ```bash
   ./test-theme.sh
   ```
   This builds an ISO and boots it in QEMU — nothing on your system is
   modified.
4. Install for real:
   ```bash
   sudo ./install.sh
   ```
5. To remove it and restore your prior GRUB config:
   ```bash
   sudo ./uninstall.sh
   ```

## Repo layout

```
theme.conf.example   # documented config template
presets/             # ready-made configs (color scheme + layout)
theme.txt.template   # GRUB theme syntax with __PLACEHOLDERS__
common.sh            # config loading, font resolution/generation, template rendering
install.sh           # installs to /boot/grub/themes/<name>, updates GRUB
uninstall.sh         # removes the theme, restores prior GRUB config
test-theme.sh        # builds a QEMU-bootable ISO, no system changes
assets/              # your bg image + selected-item pixmap
fonts/               # your .ttf/.otf/.pf2, if not using a system font
icons/               # distro/menu icons (generic, shared across configs)
```

## Requirements

- `grub-mkfont` (or `grub2-mkfont`) — ships with `grub`/`grub2-tools`,
  needed unless every font role uses a pre-supplied `.pf2`.
- Bash 4+, `dd`, `od`, `wc` (all present on any standard Linux install) —
  used to read font names out of `.pf2` binary headers.
- For `test-theme.sh` only: `grub-mkrescue`, `qemu-system-x86_64`, and
  GRUB platform modules (`grub-pc-bin`/`grub-efi-amd64-bin` or
  equivalent).

## If something goes wrong

- Test-theme failures are inert — nothing on your system changed.
- If `install.sh` produces a broken-looking menu, your prior config is at
  `/etc/default/grub.bak`; `sudo ./uninstall.sh` restores it and
  regenerates `grub.cfg` automatically. `grub-mkconfig` regenerating
  `grub.cfg` is what actually keeps boot entries intact — this repo never
  edits that file by hand.

## Publishing your own variant

Add `presets/yourname.conf` with your color/layout/font choices and open
a PR, or just fork and change `theme.conf` — the template itself only
needs to change if you're altering the menu structure.
