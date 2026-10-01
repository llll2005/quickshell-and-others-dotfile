# Rebuild after every Hyprland update (the plugin refuses to load otherwise):  make
imecaret.so: main.cpp
	$(CXX) -shared -fPIC --no-gnu-unique -O2 -std=c++2b main.cpp -o $@ \
		`pkg-config --cflags pixman-1 libdrm hyprland pangocairo libinput libudev wayland-server xkbcommon`
clean:
	rm -f imecaret.so
# swap a fresh build into the running Hyprland
reload:
	./reload.sh
.PHONY: clean reload
