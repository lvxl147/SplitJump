TARGET := iphone:clang:latest:15.0
ARCHS := arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = SplitJumpPrefs
SplitJumpPrefs_FILES = RootListController.m \
	SJRuleEditorController.m \
	SJAppPicker.m \
	SJRuleStore.m
SplitJumpPrefs_INSTALL_PATH = /Library/PreferenceBundles
# 显式链接用到的全部框架 —— 千万不要用 -Wl,-undefined,dynamic_lookup：
# 那会把「链接期就能发现的缺符号」推迟到设备加载时才爆，表现为「设置」一打开就闪退。
SplitJumpPrefs_FRAMEWORKS = UIKit Foundation QuartzCore CoreFoundation
SplitJumpPrefs_CFLAGS = -fobjc-arc \
	-Wno-deprecated-declarations -Wno-unused-function -Wno-unused-variable \
	-Wno-objc-method-access
SplitJumpPrefs_RESOURCES = Resources/icon.png Resources/icon@2x.png

include $(THEOS_MAKE_PATH)/bundle.mk
