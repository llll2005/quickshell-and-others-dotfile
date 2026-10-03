# voidbox — build into ~/.local/bin (voidbox-askpass is a symlink: sudo's SUDO_ASKPASS)
BIN ?= $(HOME)/.local/bin

build:
	go build -trimpath -o $(BIN)/voidbox .
	ln -sf voidbox $(BIN)/voidbox-askpass

# drives `voidbox pacman` in a pty against fake-pacman.sh (no sudo, no real pacman)
test:
	mkdir -p build && go build -o build/voidbox . && ln -sf voidbox build/voidbox-askpass && python3 test.py build/voidbox

.PHONY: build test
