PREFIX ?= $(HOME)/.local

.PHONY: build run test install uninstall default-browser install-cef

build:
	cargo build --release

run:
	cargo run --release --

test:
	cargo test

install: build
	install -Dm755 target/release/qi $(PREFIX)/bin/qi
	install -Dm644 data/qi.desktop $(PREFIX)/share/applications/qi.desktop
	install -Dm644 data/qi.svg $(PREFIX)/share/icons/hicolor/scalable/apps/qi.svg
	ln -sfn qi $(PREFIX)/bin/omaweb
	rm -f $(PREFIX)/share/applications/omaweb.desktop \
		$(PREFIX)/share/icons/hicolor/scalable/apps/omaweb.svg
	-update-desktop-database $(PREFIX)/share/applications
	@cur=$$(xdg-settings get default-web-browser 2>/dev/null || true); \
	if [ "$$cur" = "omaweb.desktop" ]; then xdg-settings set default-web-browser qi.desktop || true; fi

uninstall:
	rm -f $(PREFIX)/bin/qi $(PREFIX)/bin/omaweb \
		$(PREFIX)/share/applications/qi.desktop \
		$(PREFIX)/share/icons/hicolor/scalable/apps/qi.svg

install-cef:
	PREFIX=$(PREFIX) ./cef/install.sh

default-browser:
	xdg-settings set default-web-browser qi.desktop
