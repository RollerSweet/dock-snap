BINARY = .build/release/DockSnap
APP_BUNDLE = $(HOME)/Applications/DockSnap.app
CONTENTS = $(APP_BUNDLE)/Contents
INSTALL_BIN = $(CONTENTS)/MacOS/DockSnap
BUNDLE_ID = com.tamirmadar.docksnap
# Stable self-signed signing identity (keeps Accessibility permission across reinstalls).
SIGN_IDENTITY = DockSnap Self-Signed
SIGN_KEYCHAIN = $(HOME)/Library/Keychains/docksnap-signing.keychain-db
SIGN_KC_PASS = docksnap-local
LSREGISTER = /System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
# Legacy LaunchAgent from the headless daemon era — removed on install.
LEGACY_PLIST = $(HOME)/Library/LaunchAgents/$(BUNDLE_ID).plist

.PHONY: build run cert install uninstall stop start logs reseticons

build:
	swift build -c release

# Run the built binary directly (no bundle; "Start at login" needs `make install`).
run: build
	$(BINARY)

# Create the stable self-signed code-signing identity (one-time; idempotent).
cert:
	@bash scripts/make-cert.sh

install: build cert
	@# Migrate away from the old KeepAlive LaunchAgent if present.
	@launchctl unload $(LEGACY_PLIST) 2>/dev/null || true
	@rm -f $(LEGACY_PLIST)
	@pkill -x DockSnap 2>/dev/null || true
	@mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	cp $(BINARY) $(INSTALL_BIN)
	cp Info.plist $(CONTENTS)/Info.plist
	cp AppIcon.icns $(CONTENTS)/Resources/AppIcon.icns
	@security unlock-keychain -p $(SIGN_KC_PASS) $(SIGN_KEYCHAIN) 2>/dev/null || true
	codesign --force --deep --sign "$(SIGN_IDENTITY)" --identifier $(BUNDLE_ID) $(APP_BUNDLE)
	@$(MAKE) --no-print-directory reseticons
	open $(APP_BUNDLE)
	@echo ""
	@echo "DockSnap installed and running (menu-bar app)."
	@echo "First install only: enable DockSnap once in System Settings > Privacy & Security > Accessibility."
	@echo "Thanks to stable signing, future 'make install' runs keep that permission."
	@echo ""

# Force LaunchServices + the icon cache to pick up the bundle icon.
reseticons:
	@$(LSREGISTER) -f $(APP_BUNDLE) 2>/dev/null || true
	@touch $(APP_BUNDLE)
	@rm -rf $(HOME)/Library/Caches/com.apple.iconservices.store 2>/dev/null || true
	@killall Dock 2>/dev/null || true
	@killall Finder 2>/dev/null || true

uninstall:
	@launchctl unload $(LEGACY_PLIST) 2>/dev/null || true
	@rm -f $(LEGACY_PLIST)
	@pkill -x DockSnap 2>/dev/null || true
	rm -rf $(APP_BUNDLE)
	@echo "DockSnap uninstalled. (If 'Start at login' was on, also remove it in System Settings > General > Login Items.)"

stop:
	@pkill -x DockSnap 2>/dev/null || true

start:
	open $(APP_BUNDLE)

logs:
	tail -f /tmp/docksnap.log
