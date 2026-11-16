PREFIX ?= $(HOME)/.local

.PHONY: build run test install uninstall default-browser

build:
	cargo build --release

run:
	cargo run --release --

test:
	cargo test

install: build
	install -Dm755 target/release/omaweb $(PREFIX)/bin/omaweb
	install -Dm644 data/omaweb.desktop $(PREFIX)/share/applications/omaweb.desktop
	install -Dm644 data/omaweb.svg $(PREFIX)/share/icons/hicolor/scalable/apps/omaweb.svg
	-update-desktop-database $(PREFIX)/share/applications

uninstall:
	rm -f $(PREFIX)/bin/omaweb $(PREFIX)/share/applications/omaweb.desktop $(PREFIX)/share/icons/hicolor/scalable/apps/omaweb.svg

default-browser:
	xdg-settings set default-web-browser omaweb.desktop
