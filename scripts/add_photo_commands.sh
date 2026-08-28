#!/bin/bash
# ============================================================
# add_photo_commands.sh — Copy lệnh tuỳ biến của repo này vào WDA source
# FBPhotoCommands: /wda/importPhoto, /wda/importVideo
# FBPasteCommands: /wda/paste, /wda/setClipboard
# ============================================================

WDA_DIR="WebDriverAgent"
COMMANDS_DIR="$WDA_DIR/WebDriverAgentLib/Commands"

echo "========================================"
echo "Adding FBPhotoCommands + FBPasteCommands"
echo "========================================"

if [ ! -d "$COMMANDS_DIR" ]; then
    echo "ERROR: Commands directory not found at $COMMANDS_DIR"
    find "$WDA_DIR" -name "FBCustomCommands.m" -type f
    exit 1
fi

# Copy source files
for BASE in FBPhotoCommands FBPasteCommands; do
    cp "src/$BASE.h" "$COMMANDS_DIR/"
    cp "src/$BASE.m" "$COMMANDS_DIR/"
    echo "  Copied $BASE.h/.m → $COMMANDS_DIR/"

    if [ ! -f "$COMMANDS_DIR/$BASE.m" ]; then
        echo "  ERROR: Copy $BASE failed!"
        exit 1
    fi
done
echo "  ✅ Custom commands installed"

# Add Photos framework to Xcode project (link with Photos.framework)
# WebDriverAgentLib cần link Photos.framework để dùng PHPhotoLibrary
echo "=== Adding Photos.framework link ==="
PBXPROJ="$WDA_DIR/WebDriverAgent.xcodeproj/project.pbxproj"
if [ -f "$PBXPROJ" ]; then
    # Kiểm tra xem Photos.framework đã có chưa
    if grep -q "Photos.framework" "$PBXPROJ"; then
        echo "  Photos.framework already linked"
    else
        echo "  Will be linked via add_to_xcode.rb or build settings"
    fi
fi

# Thêm vào Xcode project nếu có xcodeproj gem
if command -v ruby &>/dev/null; then
    echo "=== Updating Xcode project ==="
    gem install xcodeproj 2>/dev/null || true
    ruby scripts/add_to_xcode.rb
fi

echo ""
echo "========================================"
echo "✅ Custom commands ready for build"
echo "   POST /wda/importPhoto  — import ảnh"
echo "   POST /wda/importVideo  — import video"
echo "   POST /wda/paste        — dán chữ qua bảng dán"
echo "   POST /wda/setClipboard — chỉ ghi bảng dán"
echo "========================================"
