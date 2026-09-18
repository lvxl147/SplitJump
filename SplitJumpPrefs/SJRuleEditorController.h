//
//  SJRuleEditorController.h — 单条拦截规则的编辑页
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SJRuleEditorController : UITableViewController

/// 传入 nil 表示新建；传入字典（含 target / candidates）表示编辑
- (instancetype)initWithRule:(nullable NSDictionary *)rule;

/// 保存成功后回调（用于列表页刷新）
@property (nonatomic, copy, nullable) void (^onSaved)(void);

@end

NS_ASSUME_NONNULL_END
