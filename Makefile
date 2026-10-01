ARCHS = arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = SpringBoard Preferences

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AMangoSuiteLoader
AMangoSuiteLoader_FILES = src/Loader.m
AMangoSuiteLoader_CFLAGS = -fobjc-arc -fblocks -Wall -Wextra -Werror
AMangoSuiteLoader_FRAMEWORKS = Foundation CoreFoundation
AMangoSuiteLoader_LIBRARIES = roothide

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
