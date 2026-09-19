//
//  RootListController.m — SplitJump 设置主页（PSListController，静态 specifier）
//
//  结构对齐 JumpSelect：总开关 / 拦截规则 / 放行黑名单 / 行为 / 高级 / 清空与注销。
//  动态内容（规则列表、规则编辑、应用选择器）push 普通 UITableViewController。
//
//  踩坑留档：
//   1. v1.2.0 把主页改成普通 UITableViewController，「设置」一点就崩 ——
//      PreferenceLoader 的 isController 入口按 Preferences.framework 的惯例走，
//      主页必须是 PSListController（本文件）。
//   2. _specifiers 由 Theos 的 PSListController.h 声明，子类不要重复声明
//      （否则 duplicate member 链接错误）。
//   3. PSListController / PSSpecifier 链接期不存在，Makefile 用
//      -Wl,-undefined,dynamic_lookup 交给运行时解析。
//   4. 本子工程默认 -Werror：别留未使用变量、别用废弃 API。
//

#import "RootListController.h"
#import "SJRuleListController.h"
#import "SJRuleStore.h"
#import "SJAppPicker.h"

@implementation SplitJumpRootListController

- (id)specifiers
{
	// _specifiers 来自 PSListController（见文件头注释 2），不要重复声明
	if (!_specifiers) {
		_specifiers = (NSMutableArray *)[self loadSpecifiersFromPlistName:@"Root" target:self];
	}
	return _specifiers;
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	[self reloadSpecifiers];
	// 预热应用名 / 图标缓存（后台），规则列表与选择器打开时直接可用
	[SJAppPicker warmUp:nil];
}

#pragma mark - 动作

- (void)editRules
{
	SJRuleListController *vc = [[SJRuleListController alloc] initWithStyle:UITableViewStyleGrouped];
	__weak typeof(self) w = self;
	vc.onSaved = ^{
		[w reloadSpecifiers];
	};
	[self.navigationController pushViewController:vc animated:YES];
}

- (void)editBlacklist
{
	__weak typeof(self) w = self;
	[SJAppPicker presentFrom:self
	                   title:@"选择放行黑名单"
	                     multi:YES
	        preselected:[NSSet setWithArray:[SJRuleStore loadBlacklist]]
	                   onFinish:^(NSArray<NSString *> *ids) {
		                   NSMutableArray *out = [ids mutableCopy];
		                   // SpringBoard 始终保留，否则桌面点图标也会弹窗
		                   if (![out containsObject:@"com.apple.springboard"]) {
			                   [out insertObject:@"com.apple.springboard" atIndex:0];
		                   }
		                   [SJRuleStore saveBlacklist:out];
		                   [w reloadSpecifiers];
	                   }];
}

- (void)clearAllRules
{
	UIAlertController *alert =
	    [UIAlertController alertControllerWithTitle:@"清空规则"
	                                        message:@"确定全部清空？（放行黑名单保留）"
	                                 preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"取消"
	                                          style:UIAlertActionStyleCancel
	                                        handler:nil]];
	__weak typeof(self) w = self;
	[alert addAction:[UIAlertAction actionWithTitle:@"确定"
	                                          style:UIAlertActionStyleDestructive
	                                        handler:^(UIAlertAction *a) {
		                                        [SJRuleStore clearRules];
		                                        [w reloadSpecifiers];
	                                        }]];
	[self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 注销

// 面板跑在「设置」进程里，没有权限杀 SpringBoard；
// 这里只发 Darwin 通知，由 SpringBoard 进程里的插件自己结束自己，
// 再由 launchd / 越狱框架把它拉起来。
- (void)respringNow
{
	UIAlertController *alert =
	    [UIAlertController alertControllerWithTitle:@"注销 SpringBoard"
	                                        message:@"确定立即注销？注销后插件会重新载入设置。"
	                                 preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"取消"
	                                          style:UIAlertActionStyleCancel
	                                        handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:@"注销"
	                                          style:UIAlertActionStyleDestructive
	                                        handler:^(UIAlertAction *a) {
		                                        [SJRuleStore requestRespring];
	                                        }]];
	[self presentViewController:alert animated:YES completion:nil];
}

@end
