TARGET := iphone:clang:latest:15.0
ARCHS := arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = SplitJumpPrefs
SplitJumpPrefs_FILES = RootListController.m \
	SJRuleListController.m \
	SJRuleEditorController.m \
	SJAppPicker.m \
	SJRuleStore.m
SplitJumpPrefs_INSTALL_PATH = /Library/PreferenceBundles
SplitJumpPrefs_FRAMEWORKS = UIKit Foundation
# 不要写 PRIVATE_FRAMEWORKS = Preferences：现代 iOS SDK 已不再自带
# Preferences.framework，链接期会报 `ld: framework 'Preferences' not found`。
# 头文件由 Theos 的 vendor/include 提供，符号交给运行时 dyld 解析即可。
SplitJumpPrefs_CFLAGS = -fobjc-arc
SplitJumpPrefs_RESOURCES = Resources/icon.png Resources/icon@2x.png Resources/Root.plist
# PSListController 由「设置」App 在运行时提供，链接期不存在。
# 用 dynamic_lookup 让 dyld 运行时解析，避免 -U 里 $_ 被 make 展开的问题。
SplitJumpPrefs_LDFLAGS = -Wl,-undefined,dynamic_lookup

include $(THEOS_MAKE_PATH)/bundle.mk
