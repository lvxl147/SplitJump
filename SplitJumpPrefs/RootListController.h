//
//  RootListController.h — SplitJump 设置主页
//
//  类名必须与 layout/Library/PreferenceLoader/Preferences/SplitJumpPrefs.plist
//  里的 detail 字段一致（PreferenceLoader 用 NSClassFromString 实例化）。
//
//  重要（v1.3.0 的闪退教训）：
//  主页必须是 PSListController —— PreferenceLoader / 「设置」对 isController
//  入口是按 Preferences.framework 的惯例实例化并推送的，v1.2.0 把它改成
//  普通 UITableViewController 之后，「设置」一点就崩。动态内容（规则列表、
//  规则编辑、应用选择器）用普通 UITableViewController push 即可，没问题。
//

#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>

NS_ASSUME_NONNULL_BEGIN

@interface SplitJumpRootListController : PSListController
@end

NS_ASSUME_NONNULL_END
