ARCHS = arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = SpringBoard
export DD_VERSION := $(shell sed -n 's/^Version: //p' control)

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DoubleDock
DoubleDock_FILES = Tweak.m
DoubleDock_CFLAGS = -fobjc-arc -fblocks -Wall -Wextra -Werror -DDD_VERSION='"$(DD_VERSION)"'
DoubleDock_FRAMEWORKS = Foundation CoreFoundation UIKit QuartzCore
DoubleDock_LIBRARIES = substrate roothide

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
