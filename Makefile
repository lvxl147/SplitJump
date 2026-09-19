TARGET := iphone:clang:latest:15.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

# 必须先 include common.mk —— 它才会定义 THEOS_MAKE_PATH，
# 否则下面的 $(THEOS_MAKE_PATH)/tweak.mk 会展开成 /tweak.mk 而报错。
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SplitJump
SplitJump_FILES = Tweak.xm \
	Sources/SJCompat.m \
	Sources/SJRules.m \
	Sources/SJAppList.m \
	Sources/SJPicker.m
SplitJump_CFLAGS = -fobjc-arc -ISources \
	-Wno-deprecated-declarations -Wno-unused-function -Wno-objc-method-access
SplitJump_FRAMEWORKS = UIKit Foundation QuartzCore

# 设置面板是一个 PreferenceBundle，不走 Theos 的 subproject 机制：
# $(TWEAK_NAME)_SUBPROJECTS 要求子工程产出 *.subproject.a 静态库，
# bundle 不产出它，会让主 dylib 链接时报
#   No rule to make target '.../arm64/*.subproject.a'
# 因此 SplitJumpPrefs 由 CI 单独构建，产物拷进本工程的 layout/ 再一起打包。
# 见 .github/workflows/build.yml 的 "Build prefs bundle" 步骤。

include $(THEOS_MAKE_PATH)/tweak.mk

# 安装后不要自动注销 —— 由用户手动注销（需求明确）。
