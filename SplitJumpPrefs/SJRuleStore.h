//
//  SJRuleStore.h — 偏好存取（设置面板侧，供全部页面共用）
//
//  存储域：com.lvxl524.splitjump
//
//  RulesArray : [ { "target": "com.tencent.xin",
//                   "candidates": ["com.tencent.xin", "com.tencent.xin.clone1"],
//                   "directJump": false, "showTarget": true, "enableCrane": true }, … ]
//  SourceBlacklist : ["com.apple.springboard", …]
//  Enabled / URLOnly / EarlyHook / DebugLog : BOOL
//
//  主插件（SpringBoard 进程）里 Sources/SJRules.m 读的是同一份文件，
//  写完发 Darwin 通知即可即时生效，无需注销。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#define SJ_DOMAIN @"com.lvxl524.splitjump"
#define SJ_RELOAD_NOTIFY "com.lvxl524.splitjump/ReloadPrefs"

@interface SJRuleStore : NSObject

#pragma mark 规则

+ (NSArray<NSDictionary *> *)loadRules;
+ (void)saveRules:(NSArray<NSDictionary *> *)rules;
+ (void)clearRules;

#pragma mark 放行黑名单

+ (NSArray<NSString *> *)loadBlacklist;
+ (void)saveBlacklist:(NSArray<NSString *> *)list;

#pragma mark 通用开关

+ (BOOL)boolForKey:(NSString *)key defaultValue:(BOOL)def;
+ (void)setBool:(BOOL)value forKey:(NSString *)key;

/// 请求注销：只发 Darwin 通知，由 SpringBoard 进程里的插件自己结束自己
/// （「设置」进程没有权限杀别的进程）
+ (void)requestRespring;

#pragma mark 日志

/// 追加一行设置侧日志（诊断「设置」闪退用）。写失败静默忽略。
+ (void)appendSettingsLog:(NSString *)line;

/// 把插件日志 + 设置侧日志复制到 /var/mobile/Documents/SplitJump-Logs/，
/// 返回该目录（用 Filza 直接能拿到，方便发给开发者）。
+ (NSString *)exportLogs;

/// 写完偏好后调用：通知 SpringBoard 里的插件立即重载
+ (void)notify;

@end

NS_ASSUME_NONNULL_END
