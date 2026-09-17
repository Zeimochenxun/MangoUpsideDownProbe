ARCHS = arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MangoOrientationProbe
MangoOrientationProbe_FILES = Probe.m
MangoOrientationProbe_CFLAGS = -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -Wno-deprecated-declarations
MangoOrientationProbe_FRAMEWORKS = UIKit Foundation
MangoOrientationProbe_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
