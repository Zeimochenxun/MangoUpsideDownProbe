ARCHS = arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = SpringBoard
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = MangoUpsideDownWorld
MangoUpsideDownWorld_FILES = Tweak.xm WorldPlacement.m
MangoUpsideDownWorld_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter
MangoUpsideDownWorld_FRAMEWORKS = UIKit Foundation QuartzCore
MangoUpsideDownWorld_LIBRARIES = substrate
include $(THEOS_MAKE_PATH)/tweak.mk
