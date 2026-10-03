# voidbox — build into ~/.local/bin; two symlinks: voidbox-askpass (the askpass for sudo,
# ssh and git) and pinentry-void (gpg-agent's pinentry-program)
BIN ?= $(HOME)/.local/bin

build:
	go build -trimpath -o $(BIN)/voidbox .
	ln -sf voidbox $(BIN)/voidbox-askpass
	ln -sf voidbox $(BIN)/pinentry-void

# drives `voidbox pacman` in a pty against fake-pacman.sh (no sudo, no real pacman)
test:
	mkdir -p build && go build -o build/voidbox . && ln -sf voidbox build/voidbox-askpass && python3 test.py build/voidbox

.PHONY: build test
