.PHONY: build test check app install clean

build:
	swift build

test:
	swift test

check:
	./scripts/check.sh

app:
	./scripts/build-app.sh

install: app
	ditto "dist/GrokBot.app" "/Applications/GrokBot.app"
	@echo "Installed /Applications/GrokBot.app"

clean:
	swift package clean
	rm -rf "dist/GrokBot.app"
