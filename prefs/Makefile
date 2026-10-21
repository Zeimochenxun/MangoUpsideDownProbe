TARGET = iphone:clang:16.5:16.0
ARCHS = arm64e
THEOS_PACKAGE_SCHEME = roothide
DD_VERSION ?= $(shell sed -n 's/^Version: //p' ../control)

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = DoubleDockPrefs
DoubleDockPrefs_FILES = Prefs.m
DoubleDockPrefs_FRAMEWORKS = UIKit Foundation
DoubleDockPrefs_PRIVATE_FRAMEWORKS = Preferences
DoubleDockPrefs_LIBRARIES = roothide
DoubleDockPrefs_INSTALL_PATH = /Library/PreferenceBundles
DoubleDockPrefs_CFLAGS = -fobjc-arc -fblocks -Wall -Wextra -Werror -DDD_VERSION='"$(DD_VERSION)"'
DoubleDockPrefs_RESOURCE_DIRS = Resources

include $(THEOS_MAKE_PATH)/bundle.mk

# The Settings entry (PreferenceLoader).
internal-stage::
	$(ECHO_NOTHING)mkdir -p "$(THEOS_STAGING_DIR)$(THEOS_PACKAGE_INSTALL_PREFIX)/Library/PreferenceLoader/Preferences"$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist "$(THEOS_STAGING_DIR)$(THEOS_PACKAGE_INSTALL_PREFIX)/Library/PreferenceLoader/Preferences/DoubleDockPrefs.plist"$(ECHO_END)
