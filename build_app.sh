#!/bin/bash

# Build AI Usage Mac.app
set -e

APP_DISPLAY_NAME="AI Usage Mac"
APP_EXECUTABLE="AIUsageMac"
APP_DIR="$APP_DISPLAY_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "🔨 Compiling..."

SOURCES=(
    "CursorUsageMenuBar/AppDelegate.swift"
    "CursorUsageMenuBar/CursorUsageService.swift"
    "CursorUsageMenuBar/UsagePopoverView.swift"
    "CursorUsageMenuBar/MenuBarController.swift"
)

# Build for both Apple Silicon and Intel so the app works on any Mac
swiftc "${SOURCES[@]}" -o "${APP_EXECUTABLE}_arm64" -target arm64-apple-macosx13.0 -framework Cocoa -framework WebKit -framework SwiftUI -parse-as-library
swiftc "${SOURCES[@]}" -o "${APP_EXECUTABLE}_x86_64" -target x86_64-apple-macosx13.0 -framework Cocoa -framework WebKit -framework SwiftUI -parse-as-library

# Create a Universal Binary
lipo -create -output "$APP_EXECUTABLE" "${APP_EXECUTABLE}_arm64" "${APP_EXECUTABLE}_x86_64"
rm "${APP_EXECUTABLE}_arm64" "${APP_EXECUTABLE}_x86_64"

echo "📦 Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"

mv "$APP_EXECUTABLE" "$MACOS/$APP_EXECUTABLE"

# Create Info.plist
cat > "$CONTENTS/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>AI Usage Mac</string>
    <key>CFBundleDisplayName</key>
    <string>AI Usage Mac</string>
    <key>CFBundleIdentifier</key>
    <string>com.amanjaiman.AIUsageMac</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>AIUsageMac</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Generate an app icon (a donut/circle icon)
# We'll use a Python script to create a simple .icns file
python3 - << 'PYEOF'
import struct, os, io

def create_png(size):
    """Create a minimal PNG of a three-segment usage icon."""
    import zlib
    
    width = height = size
    
    # Create RGBA pixel data
    pixels = bytearray()
    cx, cy = width / 2, height / 2
    outer_r = width * 0.42
    inner_r = width * 0.24
    
    for y in range(height):
        pixels.append(0)  # Filter byte for PNG
        for x in range(width):
            dx = x - cx
            dy = y - cy
            dist = (dx * dx + dy * dy) ** 0.5
            
            if inner_r <= dist <= outer_r:
                # Anti-aliasing at edges
                alpha = 255
                if dist > outer_r - 1.5:
                    alpha = max(0, min(255, int((outer_r - dist) / 1.5 * 255)))
                elif dist < inner_r + 1.5:
                    alpha = max(0, min(255, int((dist - inner_r) / 1.5 * 255)))
                
                import math
                angle = math.degrees(math.atan2(-dy, dx))
                segments = [
                    (140, 40, (88, 103, 232)),
                    (20, -80, (52, 168, 109)),
                    (-100, -200, (229, 115, 55)),
                ]

                r, g, b = 128, 128, 128
                for start, end, color in segments:
                    norm_angle = angle
                    norm_start = start
                    norm_end = end
                    while norm_angle > norm_start:
                        norm_angle -= 360
                    while norm_angle < norm_end:
                        norm_angle += 360
                    if norm_end <= norm_angle <= norm_start:
                        r, g, b = color
                        break
                
                pixels.extend([r, g, b, alpha])
            else:
                pixels.extend([0, 0, 0, 0])
    
    # Build PNG file
    def make_chunk(chunk_type, data):
        chunk = chunk_type + data
        crc = zlib.crc32(chunk) & 0xffffffff
        return struct.pack('>I', len(data)) + chunk + struct.pack('>I', crc)
    
    png = b'\x89PNG\r\n\x1a\n'
    # IHDR
    ihdr_data = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)
    png += make_chunk(b'IHDR', ihdr_data)
    # IDAT
    compressed = zlib.compress(bytes(pixels), 9)
    png += make_chunk(b'IDAT', compressed)
    # IEND
    png += make_chunk(b'IEND', b'')
    
    return png

def create_icns(filename):
    """Create an .icns file with multiple sizes."""
    sizes = {
        b'ic07': 128,   # 128x128
        b'ic08': 256,   # 256x256
        b'ic09': 512,   # 512x512
        b'ic11': 32,    # 16x16@2x
        b'ic12': 64,    # 32x32@2x
        b'ic13': 256,   # 128x128@2x
        b'ic14': 512,   # 256x256@2x
    }
    
    icon_data = b'icns'
    entries = b''
    
    for ostype, size in sizes.items():
        png = create_png(size)
        entry = ostype + struct.pack('>I', len(png) + 8) + png
        entries += entry
    
    total_size = len(entries) + 8
    icon_data = b'icns' + struct.pack('>I', total_size) + entries
    
    with open(filename, 'wb') as f:
        f.write(icon_data)

create_icns('AI Usage Mac.app/Contents/Resources/AppIcon.icns')
print("✅ App icon created")
PYEOF

# Ad-hoc code sign the app bundle so macOS will allow it to open
echo "🔏 Code signing..."
codesign --force --deep --sign - "$APP_DIR"

# Remove quarantine attribute if present (e.g. from previous builds)
xattr -cr "$APP_DIR" 2>/dev/null || true

echo ""
echo "✅ Built successfully: $APP_DIR"
echo ""
echo "To install, run:"
echo "  cp -r $APP_DIR /Applications/"
echo ""
echo "Then you can search for 'AI Usage Mac' in Spotlight (Cmd+Space)"
echo ""
echo "Note: If a recipient gets a Gatekeeper warning, they can right-click"
echo "the app and choose 'Open' to bypass it, or run:"
echo "  xattr -cr $APP_DIR"
