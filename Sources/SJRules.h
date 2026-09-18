//
//  SJRules.h — 偏好读取与拦截规则模型
//

#import <Foundation/Foundation.h>

// 见 SJCompat.h 的说明：Tweak.xm 是 Objective-C++，全局 C 变量需 C 链接
#ifdef __cplusplus
extern "C" {
#endif

NS_ASSUME_NONNULL_BEGIN

extern NSString *const SJSettingsDomain;   // com.lvxl524.splitjump
extern NSString *const SJReloadNotify;     // com.lvxl524.splitjump/ReloadPrefs

/// 一条拦截规则：当有人试图打开 target 时，弹出 candidates 供选择
@interface SJRule : NSObject
@property (nonatomic, copy) NSString *target;
@property (nonatomic, copy) NSArray<NSString *> *candidates;
@property (nonatomic, copy) NSString *sourceLine;
@end

@interface SJSettings : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) BOOL enabled;
@property (nonatomic, readonly) NSInteger mode;   // 0 = 弹窗选择, 1 = 直接打开首个候选
@property (nonatomic, readonly) BOOL urlOnly;     // 仅拦截带 URL 的跳转
@property (nonatomic, readonly) BOOL showSourceApp;
@property (nonatomic, readonly) BOOL enableCrane;
@property (nonatomic, readonly) BOOL craneAllContainers;
@property (nonatomic, readonly) BOOL earlyHook;   // 实验性：前移拦截点

@property (nonatomic, readonly, copy) NSArray<NSString *> *sourceBlacklist;
@property (nonatomic, readonly, copy) NSArray<SJRule *> *rules;

/// 重新从磁盘读取偏好（收到 Darwin 通知后调用）
- (void)reload;

/// 命中则返回规则
- (nullable SJRule *)ruleForTarget:(nullable NSString *)bundleID;

/// 发起方是否在放行名单内（命中则完全不拦截）
- (BOOL)sourceAllowed:(nullable NSString *)sourceBundleID;

@end

NS_ASSUME_NONNULL_END

#ifdef __cplusplus
}
#endif
