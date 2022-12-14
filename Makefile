CC           ?= gcc
ASMBLR	     := nasm

TARGET       := cotg

SRC_DIR      := src
INC_DIRS     := $(shell find $(SRC_DIR) -mindepth 1 -type d) include
BUILD_DIR    := build
CSRC_EXT     := c
ASMSRC_EXT   := asm
OBJ_EXT      := o
CFLAGS       := -std=c11 -Wall -Wextra -pedantic -Wshadow -Wunknown-pragmas
ASMFLAGS     := -felf64
LDFLAGS      := -no-pie
LIB          := -lm
INC          := $(foreach d, $(INC_DIRS), -I$d)

CSRC         := $(shell find $(SRC_DIR) -mindepth 1 -type f -name *.$(CSRC_EXT))
ASMSRC		 := $(shell find $(SRC_DIR) -mindepth 1 -type f -name *.$(ASMSRC_EXT))
COBJ         := $(patsubst $(SRC_DIR)/%, $(BUILD_DIR)/%, $(CSRC:.$(CSRC_EXT)=.$(OBJ_EXT)))
ASMOBJ       := $(patsubst $(SRC_DIR)/%, $(BUILD_DIR)/%, $(ASMSRC:.$(ASMSRC_EXT)=.$(OBJ_EXT)))


all: $(TARGET)

$(TARGET): $(COBJ) $(ASMOBJ)
	$(info Linking $@)
	@$(CC) -o $@ $^ $(LIB) $(LDFLAGS)

$(BUILD_DIR)/%.$(OBJ_EXT): $(SRC_DIR)/%.$(CSRC_EXT) | dirs
	$(info Compiling $@)
	@mkdir -p $(dir $@)
	@$(CC) $(CFLAGS) $(INC) -MD -MP -c -o $@ $<

$(BUILD_DIR)/%.$(OBJ_EXT): $(SRC_DIR)/%.$(ASMSRC_EXT) | dirs
	$(info Assembling $@)
	@mkdir -p $(dir $@)
	@$(ASMBLR) $(ASMFLAGS) -o $@ $<

.PHONY: run clean dirs

run: $(TARGET)
	@./$(TARGET)

clean:
	$(info Cleaning $(TARGET))
	@rm -f $(OBJ) $(TARGET); rm -rf $(BUILD_DIR)

dirs:
	@mkdir -p $(BUILD_DIR)

-include $(OBJ:.o=.d)
