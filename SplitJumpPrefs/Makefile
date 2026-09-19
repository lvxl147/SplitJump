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
SplitJumpPrefs_FRAMEWORKS = UIKit Foundation QuartzCore CoreFoundation
SplitJumpPrefs_CFLAGS = -fobjc-arc \
	-Wno-deprecated-declarations -Wno-unused-function -Wno-unused-variable \
	-Wno-objc-method-access
SplitJumpPrefs_RESOURCES = Resources/icon.png Resources/icon@2x.png Resources/Root.plist
# PSListController / PSSpecifier 由「设置」App 运行时提供，链接期不存在，
# 必须用 dynamic_lookup（注意：这要求所有其它符号都能在链接期解析出来）。

# PSListController 链接期不存在，必须交给运行时解析（v1.1.x 已验证可用）。
SplitJumpPrefs_LDFLAGS = -Wl,-undefined,dynamic_lookup

include $(THEOS_MAKE_PATH)/bundle.mk
