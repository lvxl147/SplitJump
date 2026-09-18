// SplitJumpPrefs / RuleEditorController.m
// 多行拦截规则编辑器（UIKit 原生，不依赖任何 Preferences 私有 cell，规避链接风险）

#import "RuleEditorController.h"

#define SJ_DOMAIN @"com.lvxl524.splitjump"
#define SJ_RULES_KEY @"Rules"
#define SJ_RELOAD_NOTIFY "com.lvxl524.splitjump/ReloadPrefs"

static NSString *const kSJPlaceholder =
    @"每行一条规则，格式：\n"
    @"被拦截的目标包名 = 候选1, 候选2, ...\n"
    @"\n"
    @"示例：\n"
    @"com.tencent.xin = com.tencent.xin, com.tencent.xin.clone1\n"
    @"com.taobao.taobao = com.taobao.taobao\n"
    @"\n"
    @"以 # 开头的行会被忽略。";

@interface RuleEditorController () <UITextViewDelegate>
@property (nonatomic, strong) UITextView *textView;
@end

@implementation RuleEditorController

- (void)viewDidLoad
{
	[super viewDidLoad];
	self.title = @"编辑拦截规则";
	self.view.backgroundColor = [UIColor systemBackgroundColor];

	self.navigationItem.rightBarButtonItem =
	    [[UIBarButtonItem alloc] initWithTitle:@"保存"
	                                     style:UIBarButtonItemStyleDone
	                                    target:self
	                                    action:@selector(saveTapped)];

	self.textView = [[UITextView alloc] initWithFrame:CGRectZero];
	self.textView.translatesAutoresizingMaskIntoConstraints = NO;
	self.textView.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
	self.textView.autocorrectionType = UITextAutocorrectionTypeNo;
	self.textView.autocapitalizationType = UITextAutocapitalizationTypeNone;
	self.textView.spellCheckingType = UITextSpellCheckingTypeNo;
	self.textView.alwaysBounceVertical = YES;
	self.textView.delegate = self;
	self.textView.text = [self storedRules] ?: kSJPlaceholder;
	[self.view addSubview:self.textView];

	UILayoutGuide *g = self.view.safeAreaLayoutGuide;
	[NSLayoutConstraint activateConstraints:@[
		[self.textView.topAnchor constraintEqualToAnchor:g.topAnchor constant:8],
		[self.textView.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:12],
		[self.textView.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-12],
		[self.textView.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-8],
	]];
}

- (NSString *)storedRules
{
	NSDictionary *domain = [[NSUserDefaults standardUserDefaults]
	    persistentDomainForName:SJ_DOMAIN];
	id v = domain[SJ_RULES_KEY];
	return [v isKindOfClass:[NSString class]] ? v : nil;
}

- (void)saveTapped
{
	NSString *text = self.textView.text ?: @"";
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	[d setObject:text forKey:SJ_RULES_KEY];
	[d synchronize];

	// 让 SpringBoard 里的插件立即重载
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
	                                     CFSTR(SJ_RELOAD_NOTIFY), NULL, NULL, YES);

	[self.navigationController popViewControllerAnimated:YES];
}

- (void)textViewDidBeginEditing:(UITextView *)tv
{
	// 首次聚焦时清掉占位示例
	NSDictionary *domain = [[NSUserDefaults standardUserDefaults]
	    persistentDomainForName:SJ_DOMAIN];
	if (!domain[SJ_RULES_KEY] && [tv.text isEqualToString:kSJPlaceholder]) {
		tv.text = @"";
	}
}

@end
