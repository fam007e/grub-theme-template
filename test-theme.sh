#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

TEST_DIR="/tmp/grub-test"
ISO_FILE="/tmp/grub-test.iso"

echo "=== GRUB Theme Tester ==="
load_config
check_deps 1
echo "✅ All checks passed."

echo ""
echo "Test Options:"
read -p "Use VNC instead of window? (y/N): " use_vnc
read -p "Screen resolution (e.g. 1280x720, 1920x1080): " resolution
[ -z "$resolution" ] && resolution="1280x720"
echo "→ Using resolution: $resolution"

echo "Stopping old QEMU..."
pkill -f qemu-system-x86_64 || true
sleep 1

echo "Cleaning old test files..."
rm -rf "$TEST_DIR"
rm -f "$ISO_FILE"

THEME_DIR="$TEST_DIR/boot/grub/themes/$THEME_NAME"
mkdir -p "$THEME_DIR"

echo "→ Generating fonts from $FONT_FILE..."
generate_fonts "$THEME_DIR"

echo "→ Rendering theme.txt..."
render_theme "$THEME_DIR"

cat > "$TEST_DIR/boot/grub/grub.cfg" << EOF
set timeout=10
set default=0

set gfxmode=${resolution}
insmod all_video
insmod gfxterm
insmod png
terminal_output gfxterm

set theme=/boot/grub/themes/${THEME_NAME}/theme.txt
export theme

menuentry "Test Boot Entry" {
    echo "GRUB Theme Test Successful!"
    sleep 5
}

menuentry "Reboot" {
    reboot
}
EOF

echo "Building GRUB ISO..."
if ! grub-mkrescue -o "$ISO_FILE" "$TEST_DIR" 2>&1; then
    echo "❌ Failed to create ISO!"
    exit 1
fi

if [ ! -f "$ISO_FILE" ]; then
    echo "❌ ISO not produced."
    exit 1
fi

echo "✅ ISO built. Starting QEMU..."

KVM_FLAG=""
if [ -r /dev/kvm ]; then
    KVM_FLAG="-enable-kvm -cpu host"
else
    echo "⚠ /dev/kvm not available; running without KVM (slow)."
fi

if [[ "$use_vnc" =~ ^[Yy]$ ]]; then
    DISPLAY_FLAGS="-display vnc=:1 -k en-us"
    echo "→ VNC on :1 (port 5901)"
else
    DISPLAY_FLAGS="-display gtk,gl=on,full-screen=on"
fi

qemu-system-x86_64 \
    -cdrom "$ISO_FILE" \
    -m 1024 \
    -vga std \
    -boot d \
    -machine q35 \
    $KVM_FLAG \
    -smp 2 \
    -no-shutdown \
    -no-reboot \
    $DISPLAY_FLAGS

echo "Test session ended."
