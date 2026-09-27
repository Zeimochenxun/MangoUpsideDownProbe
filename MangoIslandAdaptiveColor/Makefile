ARCHS = arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = SpringBoard
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = MangoIslandAdaptiveColor
MangoIslandAdaptiveColor_FILES = Tweak.m
MangoIslandAdaptiveColor_CFLAGS = -fno-objc-arc -Wall -Wextra -Werror
MangoIslandAdaptiveColor_FRAMEWORKS = Foundation Metal
MangoIslandAdaptiveColor_LIBRARIES = substrate
include $(THEOS_MAKE_PATH)/tweak.mk
