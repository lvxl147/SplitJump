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

# 子工程必须声明成 $(TWEAK_NAME)_SUBPROJECTS。
# Theos 的 makefiles/master/rules.mk 里是
#   __SUBPROJECTS = $(call __schema_var_all,$(_INSTANCE)_,SUBPROJECTS)
# 也就是读「实例名_子工程」这个变量来递归构建与暂存子目录；
# 写成裸的 SUBPROJECTS、或 include subprojects.mk 都不会生效
# （subprojects.mk 这个文件在现行 Theos 中并不存在，也不会报错，只会静默漏掉子工程）。
SplitJump_SUBPROJECTS = SplitJumpPrefs

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard" || true
