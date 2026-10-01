.PHONY: bootstrap generate lint format-fix test build clean

XCODEGEN := $(shell command -v xcodegen 2> /dev/null || echo $(HOME)/.local/bin/xcodegen)
PROJECT := GHallelujah.xcodeproj
SCHEME := GHallelujah Development
DESTINATION := platform=iOS Simulator,name=iPhone 17 Pro

# Regenerate the Xcode project, then stop — run this first after a clone.
bootstrap: generate
	@echo "Bootstrapped. Open $(PROJECT), or run 'make test'."

# GHallelujah.xcodeproj is generated from project.yml (D8 in progress.md) and
# is gitignored — this must run after every clone and after editing project.yml.
generate:
	$(XCODEGEN) generate --spec project.yml

# swiftlint/swiftformat aren't vendored: install via `brew install swiftlint
# swiftformat` normally. On a machine where Homebrew is broken (see D8 for
# why that's the case on the machine this Makefile was written on), install
# from the GitHub release binaries instead, same as xcodegen was.
lint:
	@command -v swiftlint >/dev/null 2>&1 || { echo "swiftlint not found — see the comment above this target"; exit 1; }
	swiftlint lint --strict
	@command -v swiftformat >/dev/null 2>&1 || { echo "swiftformat not found — see the comment above this target"; exit 1; }
	swiftformat --lint .

# Applies SwiftFormat's fixes in place — not part of `lint`, which only checks.
format-fix:
	swiftformat .

test: generate
	xcodebuild test -project $(PROJECT) -scheme "$(SCHEME)" -destination '$(DESTINATION)' -only-testing:GHallelujahTests

build: generate
	xcodebuild build -project $(PROJECT) -scheme "$(SCHEME)" -destination '$(DESTINATION)'

clean:
	rm -rf ~/Library/Developer/Xcode/DerivedData/GHallelujah-*
