HOST_ARCH ?= $(shell uname -m)
TOOLCHAIN ?= $(HOME)/Android/android-ndk-r28c/toolchains/llvm/prebuilt/linux-$(HOST_ARCH)/bin
TARGET ?= aarch64-linux-android28

CC = $(TOOLCHAIN)/$(TARGET)-clang
AR = $(TOOLCHAIN)/llvm-ar
RANLIB = $(TOOLCHAIN)/llvm-ranlib

CFLAGS = -Wall -std=gnu99 -shared -fPIC -I.
OUTPUT_DIR = build-aarch64
OUTPUT = $(OUTPUT_DIR)/libandroid-sysvshm.so

SRC = android_sysvshm.c
HEADERS = sys/shm.h

.PHONY: all clean

all: $(OUTPUT)

$(OUTPUT_DIR):
	mkdir -p $(OUTPUT_DIR)

$(OUTPUT): $(SRC) $(HEADERS) | $(OUTPUT_DIR)
	@echo "Building android_sysvshm for aarch64..."
	$(CC) $(CFLAGS) -o $@ $(SRC)
	@echo "Build successful! Output: $@"
	@ls -lh $@

clean:
	rm -rf $(OUTPUT_DIR)

install: $(OUTPUT)
	@echo "Installing to $(DESTDIR)..."
	mkdir -p $(DESTDIR)
	cp $(OUTPUT) $(DESTDIR)/
	@echo "Installed to $(DESTDIR)/libandroid-sysvshm.so"
