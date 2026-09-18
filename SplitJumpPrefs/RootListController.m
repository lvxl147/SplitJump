// SplitJumpPrefs / RootListController.m
// SplitJump 设置面板根控制器。
//
// 注意（踩坑记录，勿改）：
//  1. PSListController 由「设置」App 在运行时提供，链接期不存在 →
//     Makefile 里用 -Wl,-undefined,dynamic_lookup 让 dyld 运行时解析。
//  2. 不要在本子类里重复声明 _specifiers：Theos 的
//     vendor/include/Preferences/PSListController.h 自己已经声明了
//     `NSMutableArray *_specifiers;`，子类再声明会报 duplicate member。
//     这里直接复用父类的 ivar。
//  3. 需要用到的父类私有方法用「分类」声明（分类只加方法、不加 ivar，
//     所以不会触发上面的冲突）。

#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import "RuleEditorController.h"

#define SJ_DOMAIN @"com.lvxl524.splitjump"
#define SJ_RELOAD_NOTIFY "com.lvxl524.splitjump/ReloadPrefs"

@interface PSListController (SplitJumpPrivate)
- (id)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
- (void)reloadSpecifiers;
@end

@interface SplitJumpRootListController : PSListController
@end

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
		                                        NSUserDefaults *d =
		                                            [NSUserDefaults standardUserDefaults];
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
