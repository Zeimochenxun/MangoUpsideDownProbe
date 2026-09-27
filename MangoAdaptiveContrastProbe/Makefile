ARCHS = arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = SpringBoard
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = MangoAdaptiveContrastProbe
MangoAdaptiveContrastProbe_FILES = Probe.m
MangoAdaptiveContrastProbe_CFLAGS = -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-deprecated-declarations
MangoAdaptiveContrastProbe_FRAMEWORKS = Foundation UIKit QuartzCore
include $(THEOS_MAKE_PATH)/tweak.mk
