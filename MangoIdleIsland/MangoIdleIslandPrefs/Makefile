TARGET = iphone:clang:16.5:16.0
ARCHS = arm64e
THEOS_PACKAGE_SCHEME = roothide
include $(THEOS)/makefiles/common.mk
BUNDLE_NAME = MangoIdleIslandPrefs
MangoIdleIslandPrefs_FILES = Prefs.m
MangoIdleIslandPrefs_FRAMEWORKS = UIKit Foundation
MangoIdleIslandPrefs_PRIVATE_FRAMEWORKS = Preferences
MangoIdleIslandPrefs_INSTALL_PATH = /Library/PreferenceBundles
MangoIdleIslandPrefs_CFLAGS = -fobjc-arc -Wall -Wextra -Werror
include $(THEOS_MAKE_PATH)/bundle.mk
