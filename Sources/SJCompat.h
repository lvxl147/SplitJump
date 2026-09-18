//
//  SJCompat.h — 运行时安全桥接层
//
//  设计原则：
//   - 全部私有 API 一律通过 NSInvocation 调用，不做 objc_msgSend 强转
//     （ARC 下安全，且能按真实类型编码自动适配 @/B/i/q/d 参数）。
//   - 任何调用前先 respondsToSelector: 校验，缺失即安全返回 nil / NO，
//     不抛异常、不崩溃，方便跨 iOS 版本与小版本差异。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// 必须：Tweak.xm 是 Objective-C++（clang++），而 .m 文件按 C 链接编译。
// 不加 extern "C" 时头里的 C 函数声明会被 C++ 名字修饰，链接期报
// "symbol(s) not found ... declaration possibly missing 'extern \"C\"'"。
#ifdef __cplusplus
extern "C" {
#endif

NS_ASSUME_NONNULL_BEGIN

/// 调用 target 上的 selName（参数按顺序放 args，支持 0~3 个参数）
id SJInvoke(id _Nullable target, NSString *selName, NSArray * _Nullable args);

/// 调用类方法
id SJInvokeClass(Class _Nullable cls, NSString *selName, NSArray * _Nullable args);

BOOL SJObjectResponds(id _Nullable obj, NSString *selName);
BOOL SJHasClassMethod(Class _Nullable cls, NSString *selName);
BOOL SJHasInstanceMethod(Class _Nullable cls, NSString *selName);

/// 安全取字符串
NSString *SJStr(id _Nullable v);

/// 读取 ivar / KVC 属性（容错，返回 nil 表示不存在）
id SJGetProperty(id _Nullable obj, NSArray<NSString *> *candidateKeys, Class _Nullable expectClass);

/// App 图标（私有 +[UIImage _applicationIconImageForBundleIdentifier:format:scale:]），取不到返回 nil
UIImage * _Nullable SJAppIcon(NSString *bundleID);

/// 调试日志：受偏好项 DebugLog 控制；同时写入 NSLog 与
/// /var/mobile/Library/Logs/SplitJump.log（写失败静默忽略）
void SJLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

/// 由主工程在偏好重载时调用
void SJSetDebugEnabled(BOOL on);

NS_ASSUME_NONNULL_END

#ifdef __cplusplus
}
#endif
