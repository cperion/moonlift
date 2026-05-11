# Build libdasm.so — the DynASM x86 encoding engine
#
# Usage:
#   make -f back/dasm/Makefile

LUAJIT_DIR = .vendor/LuaJIT
DASM_DIR   = $(LUAJIT_DIR)/dynasm
SRC_DIR    = $(LUAJIT_DIR)/src
CC         = gcc
CFLAGS     = -shared -fPIC -O2 -DNDEBUG -DDASM_CHECKS
INCLUDES   = -I$(DASM_DIR) -I$(SRC_DIR)
TARGET     = back/libdasm.so
SOURCE     = back/dasm_lib.c

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SOURCE)
	$(CC) $(CFLAGS) $(INCLUDES) -o $@ $<

clean:
	rm -f $(TARGET)
