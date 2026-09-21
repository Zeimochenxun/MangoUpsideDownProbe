ARCHS = arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = biometrickitd

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = FaceIDOrientationProbe
FaceIDOrientationProbe_FILES = RuntimeProbe.m
FaceIDOrientationProbe_CFLAGS = -fobjc-arc -fblocks -Wall -Wextra -Werror
FaceIDOrientationProbe_FRAMEWORKS = Foundation
FaceIDOrientationProbe_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
