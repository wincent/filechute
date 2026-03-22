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

uitest:
	xcodebuild -project Filechute.xcodeproj -scheme Filechute -configuration Debug test -only-testing:FilechuteUITests

clean:
	swift package clean
	rm -rf build
