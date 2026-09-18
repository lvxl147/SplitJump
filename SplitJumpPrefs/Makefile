TARGET := iphone:clang:latest:15.0
ARCHS := arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = SplitJumpPrefs
SplitJumpPrefs_FILES = RootListController.m \
	SJRuleEditorController.m \
	SJAppPicker.m \
	SJRuleStore.m
SplitJumpPrefs_INSTALL_PATH = /Library/PreferenceBundles
SplitJumpPrefs_FRAMEWORKS = UIKit Foundation
# 不要写 PRIVATE_FRAMEWORKS = Preferences：现代 iOS SDK 已不再自带
# Preferences.framework，链接期会报 `ld: framework 'Preferences' not found`。
# 现在的设置页是纯 UIKit UITableViewController，也不再引用 PSListController。
SplitJumpPrefs_CFLAGS = -fobjc-arc \
	-Wno-deprecated-declarations -Wno-unused-function -Wno-unused-variable \
	-Wno-objc-method-access
SplitJumpPrefs_RESOURCES = Resources/icon.png Resources/icon@2x.png
# 面板里所有符号都来自 UIKit/Foundation（系统自带），不需要 dynamic_lookup；
# 保留它无副作用，留作保险。
SplitJumpPrefs_LDFLAGS = -Wl,-undefined,dynamic_lookup

include $(THEOS_MAKE_PATH)/bundle.mk
