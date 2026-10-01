TARGET = iphone:clang:16.5:16.0
ARCHS = arm64e
THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = MangoSuitePrefs
MangoSuitePrefs_FILES = Prefs.m GlassPage.m
MangoSuitePrefs_FRAMEWORKS = UIKit Foundation CoreFoundation
MangoSuitePrefs_PRIVATE_FRAMEWORKS = Preferences
MangoSuitePrefs_INSTALL_PATH = /Library/PreferenceBundles
MangoSuitePrefs_CFLAGS = -fobjc-arc -fblocks -Wall -Wextra -Werror
MangoSuitePrefs_RESOURCE_DIRS = Resources

include $(THEOS_MAKE_PATH)/bundle.mk
