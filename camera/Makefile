ARCHS = arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = roothide
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = MangoUpsideDownCamera
MangoUpsideDownCamera_FILES = Tweak.xm
MangoUpsideDownCamera_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations
MangoUpsideDownCamera_FRAMEWORKS = UIKit Foundation AVFoundation
MangoUpsideDownCamera_LIBRARIES = substrate
include $(THEOS_MAKE_PATH)/tweak.mk
