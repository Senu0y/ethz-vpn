APP_NAME   = ETHZ VPN
APP_BUNDLE = $(CURDIR)/dist/$(APP_NAME).app
SIGN_IDENTITY ?=
INSTALL_APP = /Applications/$(APP_NAME).app
RUNTIME_APP = /Library/Application Support/ETHZ VPN/Runtime.app
BINARY     = ETHZVPNMenuBar
PKG_PATH   = MenuBar
BUILD_DIR  = $(PKG_PATH)/.build/release
RESOURCES_DIR = $(PKG_PATH)/Sources/ETHZVPNMenuBar/Resources

OPENCONNECT_BREW_PATH ?= $(shell command -v openconnect 2>/dev/null || echo /opt/homebrew/bin/openconnect)

.PHONY: build bundle sign install uninstall clean fetch-openconnect dist test

fetch-openconnect:
	@echo "Bundling openconnect from Homebrew installation..."
	which dylibbundler >/dev/null || (echo "Run: brew install dylibbundler" && exit 1)
	@# Require openconnect to be installed (not just fetched) so dylib paths are real
	@OC_PATH=$$(brew --prefix openconnect 2>/dev/null)/bin/openconnect; \
	if [ ! -f "$$OC_PATH" ]; then echo "Run: brew install openconnect" && exit 1; fi; \
	mkdir -p $(RESOURCES_DIR)/lib; \
	cp "$$OC_PATH" $(RESOURCES_DIR)/openconnect; \
	chmod 755 $(RESOURCES_DIR)/openconnect; \
	echo "Copied openconnect from $$OC_PATH"
	xattr -d com.apple.quarantine $(RESOURCES_DIR)/openconnect 2>/dev/null || true
	dylibbundler -od -b -x $(RESOURCES_DIR)/openconnect \
		-d $(RESOURCES_DIR)/lib/ \
		-p @executable_path/../Resources/lib/
	cp "$(shell brew --prefix)/etc/vpnc/vpnc-script" "$(RESOURCES_DIR)/vpnc-script"
	@echo "Done: OpenConnect, libraries, and vpnc-script bundled."

build:
	swift build -c release --package-path $(PKG_PATH)

test:
	swift test --package-path $(PKG_PATH)
	bash -n ethz-vpn.sh ethz-vpn-legacy.sh
	sh -n Support/vpn-script Support/install.sh

bundle: build
	@test -f "$(RESOURCES_DIR)/openconnect" -a -f "$(RESOURCES_DIR)/vpnc-script" || (echo "Run make fetch-openconnect first."; exit 1)
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS" "$(APP_BUNDLE)/Contents/Resources" "$(APP_BUNDLE)/Contents/Library/HelperTools" "$(APP_BUNDLE)/Contents/Library/LaunchDaemons"
	cp "$(BUILD_DIR)/$(BINARY)" "$(APP_BUNDLE)/Contents/MacOS/$(BINARY)"
	cp "$(BUILD_DIR)/ETHZVPNCLI" "$(APP_BUNDLE)/Contents/MacOS/ETHZVPNCLI"
	cp "$(BUILD_DIR)/ETHZVPNHelper" "$(APP_BUNDLE)/Contents/Library/HelperTools/ETHZVPNHelper"
	cp Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	cp Support/com.dcamenisch.ethz-vpn-menubar.helper.plist "$(APP_BUNDLE)/Contents/Library/LaunchDaemons/"
	cp AppIcon.icns "$(APP_BUNDLE)/Contents/Resources/AppIcon.icns"
	cp -R "$(RESOURCES_DIR)/." "$(APP_BUNDLE)/Contents/Resources/"
	cp Support/vpn-script "$(APP_BUNDLE)/Contents/Resources/vpn-script"
	chmod 755 "$(APP_BUNDLE)/Contents/Resources/vpn-script" "$(APP_BUNDLE)/Contents/Resources/vpnc-script"
	python3 Support/check-runtime.py "$(APP_BUNDLE)"

sign: bundle
	@test -n "$(SIGN_IDENTITY)" || (echo 'Set SIGN_IDENTITY to your Apple Developer signing identity.'; exit 1)
	@for library in "$(APP_BUNDLE)/Contents/Resources/lib/"*.dylib; do codesign --force --options runtime --timestamp --sign "$(SIGN_IDENTITY)" "$$library" || exit 1; done
	codesign --force --options runtime --timestamp --sign "$(SIGN_IDENTITY)" "$(APP_BUNDLE)/Contents/Resources/openconnect"
	codesign --force --options runtime --timestamp --identifier com.dcamenisch.ethz-vpn-menubar.cli --sign "$(SIGN_IDENTITY)" "$(APP_BUNDLE)/Contents/MacOS/ETHZVPNCLI"
	codesign --force --options runtime --timestamp --identifier com.dcamenisch.ethz-vpn-menubar.helper --sign "$(SIGN_IDENTITY)" "$(APP_BUNDLE)/Contents/Library/HelperTools/ETHZVPNHelper"
	codesign --force --options runtime --timestamp --sign "$(SIGN_IDENTITY)" "$(APP_BUNDLE)"
	codesign --verify --deep --strict --verbose=2 "$(APP_BUNDLE)"

install: sign
	sudo /bin/sh Support/install.sh "$(APP_BUNDLE)"
	@echo "Launch /Applications/ETHZ VPN.app and enable VPN Access in Manage Profiles."

dist: sign
	ditto -c -k --keepParent "$(APP_BUNDLE)" "dist/ETHZ VPN.zip"
	@echo "Created signed dist/ETHZ VPN.zip. Notarize before distributing. See README."

uninstall:
	@echo "First disconnect and Disable VPN Access in Manage Profiles, then quit the app."
	@! launchctl print system/com.dcamenisch.ethz-vpn-menubar.helper >/dev/null 2>&1 || (echo "The helper is still registered. Disable VPN Access first."; exit 1)
	sudo rm -rf "$(INSTALL_APP)" "$(RUNTIME_APP)"
	@echo "Uninstalled; Keychain credentials and profiles retained."

clean:
	rm -rf $(PKG_PATH)/.build
