#!/bin/bash
# Shared functions for install.sh / test-theme.sh / uninstall.sh.
# Not meant to run directly.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/theme.conf}"

FONT_ROLES=(TITLE ITEM TIMEOUT TERMINAL)

load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "❌ Config file not found: $CONFIG_FILE"
        echo "   Copy a preset first, e.g.: cp presets/nord.conf theme.conf"
        exit 1
    fi
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"

    : "${THEME_NAME:?Missing THEME_NAME in $CONFIG_FILE}"
    : "${BG_IMAGE:?Missing BG_IMAGE in $CONFIG_FILE}"

    FONT_TITLE_SIZE="${FONT_TITLE_SIZE:-60}"
    FONT_ITEM_SIZE="${FONT_ITEM_SIZE:-16}"
    FONT_TIMEOUT_SIZE="${FONT_TIMEOUT_SIZE:-32}"
    FONT_TERMINAL_SIZE="${FONT_TERMINAL_SIZE:-16}"

    MENU_LEFT="${MENU_LEFT:--32%}"
    MENU_WIDTH="${MENU_WIDTH:-45%}"
    MENU_TOP="${MENU_TOP:-65%}"
    MENU_HEIGHT="${MENU_HEIGHT:-500}"

    ITEM_COLOR="${ITEM_COLOR:-#18191A}"
    SELECTED_ITEM_COLOR="${SELECTED_ITEM_COLOR:-#D9DBDC}"
    TIMEOUT_COLOR="${TIMEOUT_COLOR:-#18191A}"

    SELECT_PIXMAP="${SELECT_PIXMAP:-assets/select_c.png}"
    SELECT_PIXMAP_PATTERN="${SELECT_PIXMAP_PATTERN:-select_*.png}"

    if [ ! -f "$SCRIPT_DIR/$BG_IMAGE" ]; then
        echo "❌ BG_IMAGE not found: $SCRIPT_DIR/$BG_IMAGE"
        exit 1
    fi
    check_image_format "$SCRIPT_DIR/$BG_IMAGE" "BG_IMAGE"

    if [ -f "$SCRIPT_DIR/$SELECT_PIXMAP" ]; then
        check_image_format "$SCRIPT_DIR/$SELECT_PIXMAP" "SELECT_PIXMAP"
    fi

    # Every font role needs a font source: either a pre-built .pf2, or a
    # .ttf/.otf (role-specific or the global FONT_FILE fallback) to render
    # from. Validate all four up front so a typo surfaces before any work
    # is done, rather than failing halfway through an install.
    local role missing=0
    for role in "${FONT_ROLES[@]}"; do
        local pf2_var="FONT_${role}_PF2"
        local file_var="FONT_${role}_FILE"
        local pf2_val="${!pf2_var:-}"
        local file_val="${!file_var:-${FONT_FILE:-}}"

        if [ -n "$pf2_val" ]; then
            if [ ! -f "$SCRIPT_DIR/$pf2_val" ]; then
                echo "❌ $pf2_var not found: $SCRIPT_DIR/$pf2_val"
                missing=1
            fi
        elif [ -n "$file_val" ]; then
            local resolved="$file_val"
            [ -f "$SCRIPT_DIR/$file_val" ] && resolved="$SCRIPT_DIR/$file_val"
            if [ ! -f "$resolved" ]; then
                echo "❌ Font for role $role not found: $file_val"
                echo "   (checked as-is and relative to repo root)"
                missing=1
            fi
        else
            echo "❌ No font source for role $role."
            echo "   Set FONT_FILE (global), or FONT_${role}_FILE, or FONT_${role}_PF2 in $CONFIG_FILE"
            missing=1
        fi
    done
    [ "$missing" -eq 1 ] && exit 1
}

check_image_format() {
    local path="$1" label="$2"
    case "${path,,}" in
        *.png|*.jpg|*.jpeg|*.tga) : ;;
        *)
            echo "⚠ $label ($path) doesn't look like .png/.jpg/.tga — GRUB's"
            echo "  gfxmenu only supports those formats. It may fail to render."
            ;;
    esac
}

detect_mkfont() {
    if command -v grub-mkfont &>/dev/null; then
        echo "grub-mkfont"
    elif command -v grub2-mkfont &>/dev/null; then
        echo "grub2-mkfont"
    else
        echo ""
    fi
}

# check_deps <need_qemu: 0|1>
check_deps() {
    local need_qemu="$1"
    local missing=0

    MKFONT_BIN="$(detect_mkfont)"
    if [ -z "$MKFONT_BIN" ]; then
        echo "❌ grub-mkfont/grub2-mkfont not found."
        echo "   Arch/Manjaro:  sudo pacman -S grub"
        echo "   Ubuntu/Debian: sudo apt install grub-common"
        echo "   Fedora/RHEL:   sudo dnf install grub2-tools"
        missing=1
    fi

    if [ "$need_qemu" = "1" ]; then
        for cmd in grub-mkrescue qemu-system-x86_64; do
            if ! command -v "$cmd" &>/dev/null; then
                echo "❌ '$cmd' not found. Install grub and qemu."
                missing=1
            fi
        done
        local plat_ok=""
        for plat in i386-pc x86_64-efi; do
            [ -d "/usr/lib/grub/$plat" ] && plat_ok=1
        done
        if [ -z "$plat_ok" ]; then
            echo "❌ GRUB platform modules not found in /usr/lib/grub/"
            missing=1
        fi
    fi

    [ "$missing" -eq 1 ] && exit 1
    return 0
}

# pf2_font_name <path>
# Reads the NAME chunk out of a PFF2 (.pf2) file's binary header — this is
# the exact string GRUB matches font requests against, not the filename.
# Format: 4-byte magic "PFF2", then a sequence of [4-byte tag][4-byte
# big-endian length][data] chunks. NAME is always one of the first chunks,
# well before the binary glyph data, so a short bounded scan is safe.
pf2_font_name() {
    local file="$1"
    local filesize
    filesize=$(wc -c < "$file" 2>/dev/null) || return 1

    local magic
    magic="$(dd if="$file" bs=1 count=4 status=none 2>/dev/null)"
    if [ "$magic" != "PFF2" ]; then
        return 1
    fi

    local offset=4
    local scan_limit=4096   # NAME should appear well within this; bail out if not
    [ "$scan_limit" -gt "$filesize" ] && scan_limit=$filesize

    while [ "$offset" -lt "$scan_limit" ]; do
        local tag len_hex len
        tag="$(dd if="$file" bs=1 skip="$offset" count=4 status=none 2>/dev/null)"
        [ -z "$tag" ] && break
        len_hex="$(od -An -tx1 -j $((offset + 4)) -N4 "$file" 2>/dev/null | tr -d ' \n')"
        [ -z "$len_hex" ] && break
        len=$((16#$len_hex))

        if [ "$tag" = "NAME" ]; then
            dd if="$file" bs=1 skip=$((offset + 8)) count="$len" status=none 2>/dev/null
            return 0
        fi

        offset=$((offset + 8 + len))
    done

    return 1
}

# resolve_font <ROLE> <target_dir>
# Fills in FONT_<ROLE>_NAME with the real, verified font name to use in
# theme.txt — either read from a supplied .pf2, or read back from one we
# just generated. Never assumes what grub-mkfont named it.
resolve_font() {
    local role="$1" target_dir="$2"
    local pf2_var="FONT_${role}_PF2"
    local file_var="FONT_${role}_FILE"
    local size_var="FONT_${role}_SIZE"
    local name_out_var="FONT_${role}_NAME"

    local pf2_path="${!pf2_var:-}"
    local font_file="${!file_var:-$FONT_FILE}"
    local size="${!size_var}"

    if [ -n "$pf2_path" ]; then
        local src="$SCRIPT_DIR/$pf2_path"
        local out_name
        out_name="pf2_${role,,}_$(basename "$pf2_path")"

        local name
        name="$(pf2_font_name "$src")"
        if [ -z "$name" ]; then
            echo "❌ $pf2_path doesn't look like a valid .pf2 (no NAME chunk found)."
            echo "   Verify it with: file \"$pf2_path\""
            exit 1
        fi

        cp "$src" "$target_dir/$out_name"
        printf -v "$name_out_var" '%s' "$name"
        echo "  → $role: existing $pf2_path (font name: \"$name\")"
    else
        local resolved_font_file="$font_file"
        [ -f "$SCRIPT_DIR/$font_file" ] && resolved_font_file="$SCRIPT_DIR/$font_file"

        local stem key out_file
        stem="$(basename "$resolved_font_file" | sed 's/\.[^.]*$//' | tr -c 'A-Za-z0-9' '-')"
        key="${stem}_${size}"
        out_file="$target_dir/font_${key}.pf2"

        if [ ! -f "$out_file" ]; then
            if ! "$MKFONT_BIN" --output="$out_file" --name="${stem} ${size}" \
                                --size="$size" "$resolved_font_file"; then
                echo "❌ $MKFONT_BIN failed on $resolved_font_file at size $size"
                exit 1
            fi
        fi

        local name
        name="$(pf2_font_name "$out_file")"
        if [ -z "$name" ]; then
            echo "❌ Generated $out_file has no readable NAME chunk."
            echo "   $MKFONT_BIN produced something unexpected — inspect it with:"
            echo "     file \"$out_file\""
            exit 1
        fi
        printf -v "$name_out_var" '%s' "$name"
        echo "  → $role: generated ${size}pt from $(basename "$resolved_font_file") (font name: \"$name\")"
    fi
}

# generate_fonts <target_dir>
# Resolves every font role and places the resulting .pf2 files flat in
# target_dir. GRUB auto-loads every .pf2 that sits next to theme.txt when
# a theme is applied — there's no explicit `loadfont` step — which is also
# why these must stay flat (no subdirectories) and matched by internal
# name rather than filename.
generate_fonts() {
    local target_dir="$1"
    local role
    for role in "${FONT_ROLES[@]}"; do
        resolve_font "$role" "$target_dir"
    done
}

# render_theme <target_dir>
# Writes theme.txt from the template and copies in bg/select pixmap/icons.
render_theme() {
    local target_dir="$1"
    local bg_name select_name

    bg_name="$(basename "$BG_IMAGE")"
    cp "$SCRIPT_DIR/$BG_IMAGE" "$target_dir/$bg_name"

    if [ -f "$SCRIPT_DIR/$SELECT_PIXMAP" ]; then
        select_name="$(basename "$SELECT_PIXMAP")"
        cp "$SCRIPT_DIR/$SELECT_PIXMAP" "$target_dir/$select_name"
    fi

    [ -d "$SCRIPT_DIR/icons" ] && cp -r "$SCRIPT_DIR/icons" "$target_dir/"

    sed \
        -e "s|__FONT_TITLE__|${FONT_TITLE_NAME}|g" \
        -e "s|__FONT_ITEM__|${FONT_ITEM_NAME}|g" \
        -e "s|__FONT_TIMEOUT__|${FONT_TIMEOUT_NAME}|g" \
        -e "s|__FONT_TERMINAL__|${FONT_TERMINAL_NAME}|g" \
        -e "s|__BG_IMAGE_NAME__|${bg_name}|g" \
        -e "s|__MENU_LEFT__|${MENU_LEFT}|g" \
        -e "s|__MENU_WIDTH__|${MENU_WIDTH}|g" \
        -e "s|__MENU_TOP__|${MENU_TOP}|g" \
        -e "s|__MENU_HEIGHT__|${MENU_HEIGHT}|g" \
        -e "s|__ITEM_COLOR__|${ITEM_COLOR}|g" \
        -e "s|__SELECTED_ITEM_COLOR__|${SELECTED_ITEM_COLOR}|g" \
        -e "s|__TIMEOUT_COLOR__|${TIMEOUT_COLOR}|g" \
        -e "s|__SELECT_PIXMAP_PATTERN__|${SELECT_PIXMAP_PATTERN}|g" \
        "$SCRIPT_DIR/theme.txt.template" > "$target_dir/theme.txt"

    # Safety net: GRUB is unforgiving of a malformed/half-templated
    # theme.txt. Catch it here — before it's ever handed to grub-mkconfig
    # or booted in QEMU — rather than debugging a blank boot menu later.
    if grep -qE '__[A-Z_]+__' "$target_dir/theme.txt"; then
        echo "❌ theme.txt still has unresolved placeholders — aborting."
        grep -nE '__[A-Z_]+__' "$target_dir/theme.txt"
        exit 1
    fi
}
