ARCHS = arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = roothide
include $(THEOS)/makefiles/common.mk
TOOL_NAME = systemflip-capture
systemflip-capture_FILES = main.c
systemflip-capture_CFLAGS = -Wall -Wextra -Werror
systemflip-capture_INSTALL_PATH = /usr/bin
include $(THEOS_MAKE_PATH)/tool.mk
