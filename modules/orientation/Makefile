ARCHS = arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = roothide
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = MangoUpsideDownWorld MangoSplitUpsideDownFix
MangoUpsideDownWorld_FILES = World.m WorldPlacement.m XiaoMang.m
MangoUpsideDownWorld_CFLAGS = -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-function
MangoUpsideDownWorld_FRAMEWORKS = Foundation CoreFoundation UIKit QuartzCore
MangoUpsideDownWorld_LIBRARIES = substrate roothide
MangoSplitUpsideDownFix_FILES = Split.m
MangoSplitUpsideDownFix_CFLAGS = -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-function
MangoSplitUpsideDownFix_FRAMEWORKS = Foundation CoreFoundation UIKit QuartzCore
MangoSplitUpsideDownFix_LIBRARIES = substrate roothide
include $(THEOS_MAKE_PATH)/tweak.mk
