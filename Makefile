.PHONY: build test clean install

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
		-only-testing:ClockerUnitTests \
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
