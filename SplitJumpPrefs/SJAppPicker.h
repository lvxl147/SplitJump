//
//  SJAppPicker.h — 可搜索的应用选择器（带图标，支持单选 / 多选）
//
//  运行在「设置」App 进程里（PreferenceLoader bundle），
//  通过 LSApplicationWorkspace 枚举已安装应用 —— 与 JumpSelect 的做法一致。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SJAppPicker : UITableViewController

/// 弹出选择器
/// @param host   用于 push 的控制器（取其 navigationController）
/// @param title  页面标题
/// @param multi  YES = 多选（右上角「完成」收尾）；NO = 单选（点一下立刻返回）
/// @param pre    已选中的 bundleID 集合（多选时打勾）
/// @param onFinish 多选：点「完成」回调；单选：点中某项即回调（数组只含 1 个）
+ (void)presentFrom:(nullable UIViewController *)host
              title:(nullable NSString *)title
              multi:(BOOL)multi
         preselected:(nullable NSSet<NSString *> *)pre
            onFinish:(nullable void (^)(NSArray<NSString *> *bundleIDs))onFinish;

/// 显示名（取不到时回退为包名）
+ (NSString *)displayNameForBundleID:(nullable NSString *)bundleID;

/// 应用图标（私有 API，取不到返回 nil）
+ (nullable UIImage *)iconForBundleID:(nullable NSString *)bundleID;

@end

NS_ASSUME_NONNULL_END
