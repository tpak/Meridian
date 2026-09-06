.PHONY: build test clean clean-artifacts install release

SCHEME = Meridian
PROJECT = Meridian/Meridian.xcodeproj
BUILD_DIR = build
SIGNING = CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-derivedDataPath $(BUILD_DIR) $(SIGNING) build

debug:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(BUILD_DIR) $(SIGNING) build

test:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-only-testing:MeridianUnitTests \
		-parallel-testing-enabled NO -disable-concurrent-destination-testing \
		$(SIGNING) test

lint:
	swiftlint

install: build
	@app=$$(find $(BUILD_DIR) -name "Meridian.app" -type d | head -1); \
	if [ -z "$$app" ]; then echo "Error: Meridian.app not found. Run 'make build' first."; exit 1; fi; \
	pkill -x Meridian 2>/dev/null; sleep 0.5; \
	rm -rf /Applications/Meridian.app; \
	cp -R "$$app" /Applications/Meridian.app; \
	echo "Installed to /Applications/Meridian.app"

clean:
	rm -rf $(BUILD_DIR)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean 2>/dev/null || true

# Machine-wide cleanup: dead Xcode DerivedData (one per checkout path, never
# reaped by Xcode), leftover release staging in /tmp, and the orphan prefs plist
# unsigned builds leave behind. `make clean` only touches this checkout's
# build/ dir; this reclaims the rest. Run DRY=1 to preview.
#   make clean-artifacts          # prune
#   make clean-artifacts DRY=1    # show what would go
#   make clean-artifacts BETA=1   # also remove ~/Applications/Meridian-beta.app
clean-artifacts:
	@args=""; \
	if [ -n "$(DRY)" ]; then args="$$args --dry-run"; fi; \
	if [ -n "$(BETA)" ]; then args="$$args --beta"; fi; \
	bash scripts/cleanup-artifacts.sh $$args

# Hand the arguments to the recipe through the environment rather than interpolating them into the
# command text. A make variable expanded inline is parsed by the shell, so quotes, backticks or
# $(...) in NOTES/PR/VERSION would run as code on the machine holding the signing certificate and
# the notarization keychain (issue #196). As environment variables they are only ever read, and
# `set -- "$$@" ...` builds a real argv list, so release.sh receives them as literal text.
release: export MERIDIAN_NOTES = $(NOTES)
release: export MERIDIAN_PR = $(PR)
release: export MERIDIAN_VERSION = $(VERSION)
release:
	@if [ -z "$$MERIDIAN_VERSION" ]; then echo "Usage: make release VERSION=X.Y.Z [PR=123] [NOTES=\"...\"]"; exit 1; fi
	@set --; \
	if [ -n "$$MERIDIAN_NOTES" ]; then set -- "$$@" -n "$$MERIDIAN_NOTES"; fi; \
	if [ -n "$$MERIDIAN_PR" ]; then set -- "$$@" -p "$$MERIDIAN_PR"; fi; \
	bash scripts/release.sh "$$@" "$$MERIDIAN_VERSION"
