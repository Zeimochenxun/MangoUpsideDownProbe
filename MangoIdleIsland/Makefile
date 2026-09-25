ARCHS = arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = SpringBoard
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = MangoIdleIsland
MangoIdleIsland_FILES = Tweak.m TintMigration.m SpecularProbe.m
MangoIdleIsland_CFLAGS = -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-function -Wno-deprecated-declarations -include $(THEOS_PROJECT_DIR)/TweakForward.h
MangoIdleIsland_FRAMEWORKS = Foundation UIKit QuartzCore
MangoIdleIsland_LIBRARIES = substrate
include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += MangoIdleIslandPrefs
include $(THEOS_MAKE_PATH)/aggregate.mk
