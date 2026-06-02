BINARY        = OhbeeEditor
APP           = Ohbee\ Editor.app
BUNDLE        = $(APP)/Contents
VERSION       = 1.1.7
LSREGISTER    = /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
DEVELOPER_ID ?= "Developer ID Application: Your Name (XXXXXXXXXX)"

.PHONY: build test selftest bundle run dev install clean icon codesign notarize

build:
	swift build -c release

test:
	swift run OhbeeEditorSelfTests

selftest:
	swift run OhbeeEditorSelfTests

bundle: build
	rm -rf $(APP)
	mkdir -p $(BUNDLE)/MacOS $(BUNDLE)/Resources
	cp .build/release/$(BINARY) $(BUNDLE)/MacOS/$(BINARY)
	cp Support/Info.plist $(BUNDLE)/Info.plist
	cp Sources/OhbeeEditor/Resources/logo.png $(BUNDLE)/Resources/ 2>/dev/null || true
	@if [ -f Support/AppIcon.icns ]; then \
	  cp Support/AppIcon.icns $(BUNDLE)/Resources/AppIcon.icns; \
	elif [ -f Sources/OhbeeEditor/Resources/logo.png ]; then \
	  mkdir -p /tmp/AppIcon.iconset; \
	  sips -z 16 16     Sources/OhbeeEditor/Resources/logo.png --out /tmp/AppIcon.iconset/icon_16x16.png >/dev/null; \
	  sips -z 32 32     Sources/OhbeeEditor/Resources/logo.png --out /tmp/AppIcon.iconset/icon_16x16@2x.png >/dev/null; \
	  sips -z 32 32     Sources/OhbeeEditor/Resources/logo.png --out /tmp/AppIcon.iconset/icon_32x32.png >/dev/null; \
	  sips -z 64 64     Sources/OhbeeEditor/Resources/logo.png --out /tmp/AppIcon.iconset/icon_32x32@2x.png >/dev/null; \
	  sips -z 128 128   Sources/OhbeeEditor/Resources/logo.png --out /tmp/AppIcon.iconset/icon_128x128.png >/dev/null; \
	  sips -z 256 256   Sources/OhbeeEditor/Resources/logo.png --out /tmp/AppIcon.iconset/icon_128x128@2x.png >/dev/null; \
	  sips -z 256 256   Sources/OhbeeEditor/Resources/logo.png --out /tmp/AppIcon.iconset/icon_256x256.png >/dev/null; \
	  sips -z 512 512   Sources/OhbeeEditor/Resources/logo.png --out /tmp/AppIcon.iconset/icon_256x256@2x.png >/dev/null; \
	  sips -z 512 512   Sources/OhbeeEditor/Resources/logo.png --out /tmp/AppIcon.iconset/icon_512x512.png >/dev/null; \
	  sips -z 1024 1024 Sources/OhbeeEditor/Resources/logo.png --out /tmp/AppIcon.iconset/icon_512x512@2x.png >/dev/null; \
	  iconutil -c icns /tmp/AppIcon.iconset -o $(BUNDLE)/Resources/AppIcon.icns; \
	fi
	@if [ -d .build/release/OhbeeEditor_OhbeeEditor.bundle ]; then \
	  cp -R .build/release/OhbeeEditor_OhbeeEditor.bundle $(BUNDLE)/Resources/; \
	fi
	@echo "Bundle created: $(APP)"

# Open the release bundle for quick testing (registers file types at dev path — use 'make dev' during development)
run: bundle
	open $(APP)

# Run during development — uses swift run, no app bundle, no file type registration
dev:
	swift run

# Copy to /Applications and register file type associations with Finder
install: bundle
	cp -R $(APP) /Applications/
	$(LSREGISTER) -f "/Applications/Ohbee Editor.app"
	@echo "Installed to /Applications/Ohbee Editor.app"

icon:
	mkdir -p /tmp/OhbeeAppIcon.iconset
	sips -z 16   16   Sources/OhbeeEditor/Resources/logo.png --out /tmp/OhbeeAppIcon.iconset/icon_16x16.png      >/dev/null
	sips -z 32   32   Sources/OhbeeEditor/Resources/logo.png --out /tmp/OhbeeAppIcon.iconset/icon_16x16@2x.png   >/dev/null
	sips -z 32   32   Sources/OhbeeEditor/Resources/logo.png --out /tmp/OhbeeAppIcon.iconset/icon_32x32.png      >/dev/null
	sips -z 64   64   Sources/OhbeeEditor/Resources/logo.png --out /tmp/OhbeeAppIcon.iconset/icon_32x32@2x.png   >/dev/null
	sips -z 128  128  Sources/OhbeeEditor/Resources/logo.png --out /tmp/OhbeeAppIcon.iconset/icon_128x128.png    >/dev/null
	sips -z 256  256  Sources/OhbeeEditor/Resources/logo.png --out /tmp/OhbeeAppIcon.iconset/icon_128x128@2x.png >/dev/null
	sips -z 256  256  Sources/OhbeeEditor/Resources/logo.png --out /tmp/OhbeeAppIcon.iconset/icon_256x256.png    >/dev/null
	sips -z 512  512  Sources/OhbeeEditor/Resources/logo.png --out /tmp/OhbeeAppIcon.iconset/icon_256x256@2x.png >/dev/null
	sips -z 512  512  Sources/OhbeeEditor/Resources/logo.png --out /tmp/OhbeeAppIcon.iconset/icon_512x512.png    >/dev/null
	sips -z 1024 1024 Sources/OhbeeEditor/Resources/logo.png --out /tmp/OhbeeAppIcon.iconset/icon_512x512@2x.png >/dev/null
	iconutil -c icns /tmp/OhbeeAppIcon.iconset -o Support/AppIcon.icns
	rm -rf /tmp/OhbeeAppIcon.iconset
	@echo "Generated Support/AppIcon.icns — commit it to skip on-the-fly generation during bundle."

# Sign with hardened runtime (required for notarization).
# Set DEVELOPER_ID before calling: make codesign DEVELOPER_ID="Developer ID Application: You (TEAMID)"
codesign: bundle
	codesign --deep --force --options runtime \
	  --entitlements Support/Entitlements.plist \
	  --sign $(DEVELOPER_ID) \
	  "$(APP)"
	@echo "Signed: $(APP)"
	@echo "Verify: codesign --verify --deep --strict \"$(APP)\""

# Submit for Apple notarization then staple the ticket.
# Requires 'notarytool-profile' stored in Keychain (xcrun notarytool store-credentials).
notarize: codesign
	xcrun notarytool submit "$(APP)" \
	  --keychain-profile "notarytool-profile" \
	  --wait
	xcrun stapler staple "$(APP)"
	@echo "Notarized and stapled: $(APP)"

clean:
	$(LSREGISTER) -u $(APP) 2>/dev/null || true
	rm -rf .build $(APP)
