TARGET = iphone:clang:16.5:16.0
ARCHS = arm64e
THEOS_PACKAGE_SCHEME = roothide
include $(THEOS)/makefiles/common.mk
BUNDLE_NAME = MangoIslandAdaptiveColorPrefs
MangoIslandAdaptiveColorPrefs_FILES = Prefs.m
MangoIslandAdaptiveColorPrefs_FRAMEWORKS = UIKit Foundation
MangoIslandAdaptiveColorPrefs_PRIVATE_FRAMEWORKS = Preferences
MangoIslandAdaptiveColorPrefs_INSTALL_PATH = /Library/PreferenceBundles
MangoIslandAdaptiveColorPrefs_CFLAGS = -fobjc-arc -Wall -Wextra -Werror
include $(THEOS_MAKE_PATH)/bundle.mk