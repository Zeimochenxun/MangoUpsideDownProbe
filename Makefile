ARCHS = arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MangoSplitUpsideDownFix
MangoSplitUpsideDownFix_FILES = Fix.m
MangoSplitUpsideDownFix_CFLAGS = -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -Wno-deprecated-declarations
MangoSplitUpsideDownFix_FRAMEWORKS = UIKit Foundation QuartzCore
MangoSplitUpsideDownFix_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
