TARGET = iphone:clang:16.5:16.0
ARCHS = arm64e
THEOS_PACKAGE_SCHEME = roothide
DI_VERSION ?= $(shell sed -n 's/^Version: //p' ../control)

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = DynamicIslandPrefs
DynamicIslandPrefs_FILES = Prefs.m
DynamicIslandPrefs_FRAMEWORKS = UIKit Foundation
DynamicIslandPrefs_PRIVATE_FRAMEWORKS = Preferences
DynamicIslandPrefs_LIBRARIES = roothide
DynamicIslandPrefs_INSTALL_PATH = /Library/PreferenceBundles
DynamicIslandPrefs_CFLAGS = -fobjc-arc -fblocks -Wall -Wextra -Wno-unused-parameter -Wno-unused-function -Wno-deprecated-declarations -DDI_VERSION='"$(DI_VERSION)"'
DynamicIslandPrefs_RESOURCE_DIRS = Resources

include $(THEOS_MAKE_PATH)/bundle.mk

# The Settings entry (PreferenceLoader).
internal-stage::
	$(ECHO_NOTHING)mkdir -p "$(THEOS_STAGING_DIR)$(THEOS_PACKAGE_INSTALL_PREFIX)/Library/PreferenceLoader/Preferences"$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist "$(THEOS_STAGING_DIR)$(THEOS_PACKAGE_INSTALL_PREFIX)/Library/PreferenceLoader/Preferences/DynamicIslandPrefs.plist"$(ECHO_END)
