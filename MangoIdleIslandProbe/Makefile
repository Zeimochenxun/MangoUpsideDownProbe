ARCHS = arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = SpringBoard
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = MangoIdleIslandProbe
MangoIdleIslandProbe_FILES = Probe.m
MangoIdleIslandProbe_CFLAGS = -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-deprecated-declarations
MangoIdleIslandProbe_FRAMEWORKS = Foundation UIKit QuartzCore
include $(THEOS_MAKE_PATH)/tweak.mk
