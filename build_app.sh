#!/bin/bash

# Build CursorUsage.app
set -e

APP_NAME="CursorUsage"
APP_DIR="$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "🔨 Compiling..."

# Build for both Apple Silicon and Intel so the app works on any Mac
swiftc run.swift -o "${APP_NAME}_arm64" -target arm64-apple-macosx13.0 -framework Cocoa -framework WebKit -framework SwiftUI
swiftc run.swift -o "${APP_NAME}_x86_64" -target x86_64-apple-macosx13.0 -framework Cocoa -framework WebKit -framework SwiftUI

# Create a Universal Binary
lipo -create -output "$APP_NAME" "${APP_NAME}_arm64" "${APP_NAME}_x86_64"
rm "${APP_NAME}_arm64" "${APP_NAME}_x86_64"

echo "📦 Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"

mv "$APP_NAME" "$MACOS/$APP_NAME"

# Create Info.plist
cat > "$CONTENTS/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>CursorUsage</string>
    <key>CFBundleDisplayName</key>
    <string>Cursor Usage</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.CursorUsage</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>CursorUsage</string>
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
    """Create a minimal PNG of a donut chart icon."""
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
                angle = math.atan2(-dy, dx)
                angle_deg = math.degrees(angle)
                if angle_deg < 0:
                    angle_deg += 360
                # Convert to "clock" angle starting from top
                clock_angle = (90 - angle_deg) % 360
                
                # 70% fill - green/teal color
                fill_pct = 0.70
                if clock_angle / 360.0 < fill_pct:
                    r, g, b = 76, 205, 153  # Teal/green
                else:
                    r, g, b = 128, 128, 128  # Gray
                
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

create_icns('CursorUsage.app/Contents/Resources/AppIcon.icns')
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
echo "Then you can search for 'Cursor Usage' in Spotlight (Cmd+Space)"
echo ""
echo "Note: If a recipient gets a Gatekeeper warning, they can right-click"
echo "the app and choose 'Open' to bypass it, or run:"
echo "  xattr -cr $APP_DIR"
