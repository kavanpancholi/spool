.PHONY: build test app run install clean

build:
	swift build

test:
	swift test

app:
	scripts/bundle.sh release

run: app
	-pkill -x Spool
	open build/Spool.app

install: app
	-pkill -x Spool
	rm -rf ~/Applications/Spool.app
	mkdir -p ~/Applications
	cp -R build/Spool.app ~/Applications/Spool.app
	open ~/Applications/Spool.app

clean:
	rm -rf .build build
