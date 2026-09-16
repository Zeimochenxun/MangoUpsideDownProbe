# Source-only diagnostic build for the supplied arm64e Mango image.
ARCHS = arm64e
TARGET = iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MangoUpsideDownProbe
MangoUpsideDownProbe_FILES = Tweak.xm
MangoUpsideDownProbe_CFLAGS = -fobjc-arc -Wextra -Wno-deprecated-declarations
MangoUpsideDownProbe_FRAMEWORKS = UIKit Foundation QuartzCore
MangoUpsideDownProbe_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
