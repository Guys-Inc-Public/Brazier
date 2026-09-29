# Brazier iOS app. Runs on the Mac mini as the `claude` build user; from mitochondria use scripts/remote.sh.
SHELL := /bin/bash
export PATH := /opt/homebrew/bin:$(PATH)

SCHEME    := Brazier
PROJECT   := Brazier.xcodeproj
DERIVED   ?= /Users/claude/work/DerivedData/brazier
# Simulators are per macOS user; the build user has its own set, so resolve by name, newest iOS first.
SIM_NAME  ?= iPhone 17 Pro
SIM_UDID  ?= $(shell xcrun simctl list devices available -j | python3 -c 'import sys,json; d=json.load(sys.stdin)["devices"]; c=[(rt,dev["udid"]) for rt,devs in d.items() if "iOS" in rt for dev in devs if dev["name"]=="$(SIM_NAME)"]; print(sorted(c)[-1][1] if c else "")')
BUNDLE_ID := org.guysinc.brazier
SHOT      ?= /Users/Shared/brazier/app-screenshot.png
# Optional, DEBUG builds only: mount a token-mode server at launch (see AppModel.seedFromEnvironment).
SEED_URL  ?=
SEED_TOKEN ?=
SEED_NAME ?=

# App Store Connect API key (Admin), under the claude user. Cloud signing, no .p12 on the Mac.
ASC_KEY_PATH := /Users/claude/.appstoreconnect/private_keys/AuthKey_9258LNDGUM.p8
ASC_KEY_ID   := 9258LNDGUM
ASC_ISSUER   := f98b49e4-67e6-4f4b-84a6-864b64b6b03e
ASC_AUTH     := -allowProvisioningUpdates -authenticationKeyPath $(ASC_KEY_PATH) -authenticationKeyID $(ASC_KEY_ID) -authenticationKeyIssuerID $(ASC_ISSUER)

# The build user's own keychain (login.keychain-db is unusable headless, see docs/mac-setup in Honeywick).
# Signing needs it unlocked, and any key Xcode creates in it needs codesign on its access list, or
# xcodebuild fails with "User interaction is not allowed".
KEYCHAIN    := /Users/claude/Library/Keychains/claude.keychain-db
KEYCHAIN_PW  = $(shell cat /Users/claude/.config/login.pw)

.PHONY: generate build-sim run-sim unlock grant-keys archive upload clean

unlock:
	@security unlock-keychain -p "$(KEYCHAIN_PW)" $(KEYCHAIN)
	@security set-keychain-settings $(KEYCHAIN)

grant-keys:
	@security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$(KEYCHAIN_PW)" $(KEYCHAIN) >/dev/null 2>&1 || true

generate:
	xcodegen generate --spec project.yml --quiet

build-sim: generate
	@echo "simulator: $(SIM_NAME) $(SIM_UDID)"
	set -o pipefail; xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
	  -destination "platform=iOS Simulator,id=$(SIM_UDID)" \
	  -derivedDataPath $(DERIVED) CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO build | xcbeautify

run-sim: build-sim
	xcrun simctl boot $(SIM_UDID) 2>/dev/null || true
	xcrun simctl bootstatus $(SIM_UDID) -b
	xcrun simctl terminate $(SIM_UDID) $(BUNDLE_ID) 2>/dev/null || true
	xcrun simctl install $(SIM_UDID) "$(DERIVED)/Build/Products/Debug-iphonesimulator/Brazier.app"
	SIMCTL_CHILD_BRAZIER_SEED_URL="$(SEED_URL)" SIMCTL_CHILD_BRAZIER_SEED_TOKEN="$(SEED_TOKEN)" SIMCTL_CHILD_BRAZIER_SEED_NAME="$(SEED_NAME)" xcrun simctl launch $(SIM_UDID) $(BUNDLE_ID)
	sleep 5
	xcrun simctl io $(SIM_UDID) screenshot "$(SHOT)"
	@echo "screenshot: $(SHOT)"

# Archive for the store (the app record exists since 2026-09-29).
# The first run may create a development certificate and key; the retry grants codesign access to it.
archive: generate unlock grant-keys
	set -o pipefail; xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
	  -destination "generic/platform=iOS" -archivePath "$(DERIVED)/Brazier.xcarchive" \
	  $(ASC_AUTH) archive | xcbeautify \
	|| { $(MAKE) grant-keys; set -o pipefail; xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
	  -destination "generic/platform=iOS" -archivePath "$(DERIVED)/Brazier.xcarchive" \
	  $(ASC_AUTH) archive | xcbeautify; }

# Upload the archive to TestFlight with the API key; distribution signing is cloud-managed.
upload: unlock grant-keys
	xcodebuild -exportArchive -archivePath "$(DERIVED)/Brazier.xcarchive" \
	  -exportOptionsPlist ExportOptions.plist -exportPath "$(DERIVED)/export" $(ASC_AUTH)

clean:
	rm -rf "$(DERIVED)" $(PROJECT)
