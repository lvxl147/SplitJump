//
//  SJAppList.h — 候选应用枚举（含 Crane 多开容器）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "SJRules.h"

NS_ASSUME_NONNULL_BEGIN

@interface SJAppEntry : NSObject
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy, nullable) NSString *containerID; // Crane 容器标识，nil = 默认容器
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *subtitle;
@property (nonatomic, strong, nullable) UIImage *icon;
@property (nonatomic, assign) BOOL installed;
@end

@interface SJAppList : NSObject

/// 按规则构建候选列表；未安装的候选会被过滤掉
+ (NSArray<SJAppEntry *> *)entriesForRule:(SJRule *)rule;

/// 是否安装（用 LSApplicationProxy 判定）
+ (BOOL)isInstalled:(nullable NSString *)bundleID;

/// Crane 是否可用
+ (BOOL)craneAvailable;

/// 把某个 Crane 容器设为该应用的当前容器（失败返回 NO）
+ (BOOL)activateContainer:(nullable NSString *)containerID forBundleID:(nullable NSString *)bundleID;

/// 显示名（用于面板与「发起方」展示）
+ (NSString *)displayNameForBundleID:(nullable NSString *)bundleID;

@end

NS_ASSUME_NONNULL_END
