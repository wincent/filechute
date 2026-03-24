.PHONY: build run app clean test uitest

APP_NAME = Filechute
APP_DIR = build/$(APP_NAME).app
CONTENTS = $(APP_DIR)/Contents
MACOS = $(CONTENTS)/MacOS
RESOURCES = $(CONTENTS)/Resources

build:
	swift build

test:
	swift test

app: build
	mkdir -p $(MACOS) $(RESOURCES)
	cp .build/debug/$(APP_NAME) $(MACOS)/$(APP_NAME)
	cp Info.plist $(CONTENTS)/Info.plist
	cp Resources/AppIcon.icns $(RESOURCES)/AppIcon.icns
	@echo "Built $(APP_DIR)"

run: app
	open $(APP_DIR)

UITEST_DIR = /tmp/filechute-uitest
UITEST_SUITE = dev.wincent.Filechute.UITesting

uitest:
	rm -rf $(UITEST_DIR)
	mkdir -p $(UITEST_DIR)
	defaults delete $(UITEST_SUITE) 2>/dev/null || true
	xcodebuild -project Filechute.xcodeproj -scheme Filechute -configuration Debug test \
		-only-testing:FilechuteUITests

clean:
	swift package clean
	rm -rf build
