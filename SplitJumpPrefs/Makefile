TARGET := iphone:clang:latest:15.0
ARCHS := arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = SplitJumpPrefs
SplitJumpPrefs_FILES = RootListController.m RuleEditorController.m
SplitJumpPrefs_INSTALL_PATH = /Library/PreferenceBundles
SplitJumpPrefs_FRAMEWORKS = UIKit Foundation
SplitJumpPrefs_PRIVATE_FRAMEWORKS = Preferences
SplitJumpPrefs_CFLAGS = -fobjc-arc -I../Sources
SplitJumpPrefs_RESOURCES = Resources/icon.png Resources/icon@2x.png Resources/Root.plist
# PSListController 由「设置」App 在运行时提供，链接期不存在。
# 用 dynamic_lookup 让 dyld 运行时解析，避免 -U 里 $_ 被 make 展开的问题。
SplitJumpPrefs_LDFLAGS = -Wl,-undefined,dynamic_lookup

include $(THEOS_MAKE_PATH)/bundle.mk
