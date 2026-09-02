#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run as root (use sudo):"
  echo "   sudo ./uninstall.sh"
  exit 1
fi

load_config

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

echo "=== Uninstalling GRUB Theme: $THEME_NAME ==="
echo "→ Removing $THEME_DIR"
rm -rf "$THEME_DIR"

if [ -f /etc/default/grub.bak ]; then
    echo "→ Restoring /etc/default/grub from grub.bak (written by install.sh)"
    cp /etc/default/grub.bak /etc/default/grub
else
    echo "⚠ No /etc/default/grub.bak found — removing GRUB_THEME line only."
    sed -i '/^GRUB_THEME=/d' /etc/default/grub
fi

echo "→ Regenerating $GRUB_DIR/grub.cfg"
if command -v "$GRUB_MKCONFIG" &>/dev/null; then
    "$GRUB_MKCONFIG" -o "$GRUB_DIR/grub.cfg"
else
    echo "⚠️  Could not find $GRUB_MKCONFIG. Run manually:"
    echo "   sudo grub-mkconfig -o $GRUB_DIR/grub.cfg"
    exit 1
fi

echo "✅ Theme removed, GRUB restored to its prior state."
