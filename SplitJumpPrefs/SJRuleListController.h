//
//  SJRuleListController.h — 拦截规则列表（添加 / 编辑 / 删除）
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SJRuleListController : UITableViewController
/// 保存或删除后回调（用于主页刷新）
@property (nonatomic, copy, nullable) void (^onSaved)(void);
@end

NS_ASSUME_NONNULL_END
