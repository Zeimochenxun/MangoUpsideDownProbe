ARCHS = arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = roothide
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = FaceIDLabSB FaceIDLabBio
FaceIDLabSB_FILES = SpringBoardLab.m
FaceIDLabSB_CFLAGS = -fobjc-arc -fblocks -Wall -Wextra -Werror
FaceIDLabSB_FRAMEWORKS = Foundation UIKit
FaceIDLabSB_LIBRARIES = substrate
FaceIDLabBio_FILES = BiometricLab.m
FaceIDLabBio_CFLAGS = -fobjc-arc -fblocks -Wall -Wextra -Werror
FaceIDLabBio_FRAMEWORKS = Foundation
FaceIDLabBio_LIBRARIES = substrate
include $(THEOS_MAKE_PATH)/tweak.mk
