//
//  SJRuleStore.h — 规则的结构化存取（设置面板侧）
//
//  存储格式（域 com.lvxl524.splitjump）：
//    RulesArray     : [ { "target": "com.tencent.xin",
//                         "candidates": ["com.tencent.xin", "com.tencent.xin.clone1"] }, … ]
//    SourceBlacklist: ["com.apple.springboard", …]
//
//  主插件（SpringBoard 进程）里 Sources/SJRules.m 读的是同一份文件，
//  写完发 Darwin 通知即可即时生效，无需注销。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#define SJ_DOMAIN @"com.lvxl524.splitjump"
#define SJ_RELOAD_NOTIFY "com.lvxl524.splitjump/ReloadPrefs"

@interface SJRuleStore : NSObject

+ (NSArray<NSDictionary *> *)loadRules;
+ (void)saveRules:(NSArray<NSDictionary *> *)rules;

+ (NSArray<NSString *> *)loadBlacklist;
+ (void)saveBlacklist:(NSArray<NSString *> *)list;

/// 写完偏好后调用：通知 SpringBoard 里的插件立即重载
+ (void)notify;

@end

NS_ASSUME_NONNULL_END
