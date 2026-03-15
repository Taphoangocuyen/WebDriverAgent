#!/bin/bash
# ============================================================
# add_photo_commands.sh — Copy FBPhotoCommands vào WDA source
# Thêm route /wda/importPhoto và /wda/importVideo
# ============================================================

WDA_DIR="WebDriverAgent"
COMMANDS_DIR="$WDA_DIR/WebDriverAgentLib/Commands"

echo "========================================"
echo "Adding FBPhotoCommands (importPhoto/importVideo)"
echo "========================================"

if [ ! -d "$COMMANDS_DIR" ]; then
    echo "ERROR: Commands directory not found at $COMMANDS_DIR"
    find "$WDA_DIR" -name "FBCustomCommands.m" -type f
    exit 1
fi

# Copy source files
cp src/FBPhotoCommands.h "$COMMANDS_DIR/"
cp src/FBPhotoCommands.m "$COMMANDS_DIR/"

echo "  Copied FBPhotoCommands.h → $COMMANDS_DIR/"
echo "  Copied FBPhotoCommands.m → $COMMANDS_DIR/"

# Verify
if [ -f "$COMMANDS_DIR/FBPhotoCommands.m" ]; then
    echo "  ✅ FBPhotoCommands installed"
else
    echo "  ERROR: Copy failed!"
    exit 1
fi

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
echo "✅ FBPhotoCommands ready for build"
echo "   POST /wda/importPhoto — import ảnh"
echo "   POST /wda/importVideo — import video"
echo "========================================"
