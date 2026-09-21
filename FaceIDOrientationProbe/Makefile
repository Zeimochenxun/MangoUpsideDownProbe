ARCHS = arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = biometrickitd coreauthd

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = FaceIDOrientationProbe
FaceIDOrientationProbe_FILES = Probe.m
FaceIDOrientationProbe_CFLAGS = -fobjc-arc -fblocks -Wall -Wextra -Werror
FaceIDOrientationProbe_FRAMEWORKS = Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
