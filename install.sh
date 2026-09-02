#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run as root (use sudo):"
  echo "   sudo ./install.sh"
  exit 1
fi

load_config
check_deps 0

if [ -d "/boot/grub" ]; then
  GRUB_DIR="/boot/grub"
  GRUB_MKCONFIG="grub-mkconfig"
elif [ -d "/boot/grub2" ]; then
  GRUB_DIR="/boot/grub2"
  GRUB_MKCONFIG="grub2-mkconfig"
else
  echo "❌ GRUB directory not found in /boot/grub or /boot/grub2."
  exit 1
fi

THEME_DIR="$GRUB_DIR/themes/$THEME_NAME"
echo "=== Installing GRUB Theme: $THEME_NAME ==="
echo "→ Target: $THEME_DIR"

mkdir -p "$THEME_DIR"

echo "→ Generating fonts from $FONT_FILE..."
generate_fonts "$THEME_DIR"

echo "→ Rendering theme.txt..."
render_theme "$THEME_DIR"

echo "→ Backing up /etc/default/grub to /etc/default/grub.bak..."
cp /etc/default/grub /etc/default/grub.bak

echo "→ Configuring /etc/default/grub..."
set_grub_default() {
    local key="$1" value="$2"
    if grep -q "^${key}=" /etc/default/grub; then
        sed -i "s|^${key}=.*|${key}=\"${value}\"|" /etc/default/grub
    elif grep -q "^#${key}=" /etc/default/grub; then
        sed -i "s|^#${key}=.*|${key}=\"${value}\"|" /etc/default/grub
    else
        echo "${key}=\"${value}\"" >> /etc/default/grub
    fi
}
set_grub_default "GRUB_THEME" "$THEME_DIR/theme.txt"
set_grub_default "GRUB_GFXMODE" "${GRUB_GFXMODE:-1920x1080,1280x720,auto}"
if grep -q "^#GRUB_GFXPAYLOAD_LINUX=" /etc/default/grub; then
    sed -i "s|^#GRUB_GFXPAYLOAD_LINUX=.*|GRUB_GFXPAYLOAD_LINUX=keep|" /etc/default/grub
fi

echo "→ Updating GRUB configuration..."
if command -v "$GRUB_MKCONFIG" &>/dev/null; then
    "$GRUB_MKCONFIG" -o "$GRUB_DIR/grub.cfg"
else
    echo "⚠️  Could not find $GRUB_MKCONFIG. Run manually:"
    echo "   sudo grub-mkconfig -o $GRUB_DIR/grub.cfg"
    exit 1
fi

echo "✅ Theme '$THEME_NAME' installed and configured."
