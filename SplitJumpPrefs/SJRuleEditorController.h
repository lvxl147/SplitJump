//
//  SJRuleEditorController.h — 单条拦截规则的编辑页
//
//  页面结构对齐 JumpSelect 的「编辑拦截规则」：
//    1. 选择拦截应用（单选）
//    2. 列表应用显示（多选）
//    3. 本条规则设置：开启直接跳转 / 显示目标拦截应用 / 兼容 Crane 容器
//    4. 保存此规则 / 删除此规则
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SJRuleEditorController : UITableViewController

/// 传入 nil 表示新建；传入字典（含 target / candidates / 三个开关）表示编辑
- (instancetype)initWithRule:(nullable NSDictionary *)rule;

/// 保存成功后回调（用于列表页刷新）
@property (nonatomic, copy, nullable) void (^onSaved)(void);

@end

NS_ASSUME_NONNULL_END
