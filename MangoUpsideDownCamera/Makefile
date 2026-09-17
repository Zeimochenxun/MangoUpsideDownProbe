ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MangoUpsideDownCamera

MangoUpsideDownCamera_FILES = Tweak.xm
MangoUpsideDownCamera_FRAMEWORKS = Foundation AVFoundation
MangoUpsideDownCamera_CFLAGS = -fobjc-arc -Wno-deprecated-declarations

include $(THEOS_MAKE_PATH)/tweak.mk
