// SplitJumpPrefs / RootListController.m
// SplitJump 设置面板根控制器。
//
// 注意（踩坑记录，勿改）：
//  1. PSListController 由「设置」App 运行时提供，链接期不存在 →
//     Makefile 里用 -Wl,-undefined,dynamic_lookup 让 dyld 运行时解析。
//  2. _specifiers ivar 必须声明在「子类」上；写在 PSListController 的前置声明里
//     会产生父类 ivar 符号，链接期报 _OBJC_IVAR_$_PSListController._specifiers 未定义。

#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "RuleEditorController.h"

#define SJ_DOMAIN @"com.lvxl524.splitjump"
#define SJ_RELOAD_NOTIFY "com.lvxl524.splitjump/ReloadPrefs"

@interface SplitJumpRootListController : PSListController {
	NSArray *_specifiers; // 必须声明在子类上（见文件头注释 2）
}
@end

@implementation SplitJumpRootListController

- (id)specifiers
{
	if (!_specifiers) {
		_specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
	}
	return _specifiers;
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	[self reloadSpecifiers];
}

- (void)viewDidDisappear:(BOOL)animated
{
	[super viewDidDisappear:animated];
	// 通知 SpringBoard 进程内的插件立即重新读取设置，无需注销
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
	                                     CFSTR(SJ_RELOAD_NOTIFY), NULL, NULL, YES);
}

#pragma mark - 规则编辑

- (void)editRules
{
	RuleEditorController *vc = [[RuleEditorController alloc] init];
	[self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - 恢复默认

- (void)resetSettings
{
	UIAlertController *alert =
	    [UIAlertController alertControllerWithTitle:@"恢复默认设置"
	                                        message:@"将清空所有拦截规则与开关设置，确定继续？"
	                                 preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"取消"
	                                          style:UIAlertActionStyleCancel
	                                        handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:@"确定"
	                                          style:UIAlertActionStyleDestructive
	                                        handler:^(UIAlertAction *a) {
		                                        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
		                                        [d removePersistentDomainForName:SJ_DOMAIN];
		                                        [d synchronize];
		                                        CFNotificationCenterPostNotification(
		                                            CFNotificationCenterGetDarwinNotifyCenter(),
		                                            CFSTR(SJ_RELOAD_NOTIFY), NULL, NULL, YES);
		                                        [weakSelf reloadSpecifiers];
	                                        }]];
	[self presentViewController:alert animated:YES completion:nil];
}

@end
