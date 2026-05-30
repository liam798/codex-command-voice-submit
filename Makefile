SWIFTC ?= swiftc
BUILD_DIR := .build
BIN := $(BUILD_DIR)/codex-voice-auto-send
SRC := Sources/main.swift

.PHONY: build run clean install uninstall package

build:
	mkdir -p $(BUILD_DIR)
	$(SWIFTC) $(SRC) -o $(BIN) -framework AppKit -framework ApplicationServices

run: build
	$(BIN)

clean:
	rm -rf $(BUILD_DIR)

install: build
	./install.sh

uninstall:
	./uninstall.sh

package:
	./package.sh
