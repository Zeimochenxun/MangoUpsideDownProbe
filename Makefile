ARCHS = arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = roothide
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SystemFlipProbeSB SystemFlipProbeBB
SystemFlipProbeSB_FILES = Probe.m
SystemFlipProbeSB_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter -DSF_SPRINGBOARD=1
SystemFlipProbeSB_FRAMEWORKS = Foundation UIKit QuartzCore
SystemFlipProbeBB_FILES = Probe.m
SystemFlipProbeBB_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter
SystemFlipProbeBB_FRAMEWORKS = Foundation QuartzCore
include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += capture
include $(THEOS_MAKE_PATH)/aggregate.mk
