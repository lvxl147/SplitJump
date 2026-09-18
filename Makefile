TARGET := iphone:clang:latest:15.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

TWEAK_NAME = SplitJump
SplitJump_FILES = Tweak.xm \
	Sources/SJCompat.m \
	Sources/SJRules.m \
	Sources/SJAppList.m \
	Sources/SJPicker.m
SplitJump_CFLAGS = -fobjc-arc -ISources \
	-Wno-deprecated-declarations -Wno-unused-function -Wno-objc-method-access
SplitJump_FRAMEWORKS = UIKit Foundation QuartzCore

SUBPROJECTS += SplitJumpPrefs

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/subprojects.mk

after-install::
	install.exec "killall -9 SpringBoard" || true
