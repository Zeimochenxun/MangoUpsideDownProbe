ARCHS = arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MangoSplitGeometryProbe
MangoSplitGeometryProbe_FILES = Probe.m
MangoSplitGeometryProbe_CFLAGS = -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -Wno-deprecated-declarations
MangoSplitGeometryProbe_FRAMEWORKS = UIKit Foundation QuartzCore
MangoSplitGeometryProbe_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
