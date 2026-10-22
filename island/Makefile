ARCHS = arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = SpringBoard
export DI_VERSION := $(shell sed -n 's/^Version: //p' control)

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DynamicIsland
DynamicIsland_FILES = Tweak.m Disguise.m
DynamicIsland_CFLAGS = -fobjc-arc -fblocks -Wall -Wextra -Wno-unused-parameter -Wno-unused-function -Wno-deprecated-declarations -DDI_VERSION='"$(DI_VERSION)"'
DynamicIsland_FRAMEWORKS = Foundation CoreFoundation UIKit QuartzCore
DynamicIsland_LIBRARIES = roothide

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
