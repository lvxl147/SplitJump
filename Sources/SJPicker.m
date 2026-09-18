//
//  SJPicker.m
//
//  面板实现要点：
//   - 用独立 UIWindow（UIWindowLevelAlert + 1）承载，避免被 SpringBoard 的
//     其它 scene / 窗口层级影响；能拿到 windowScene 就绑，拿不到就退回无 scene 初始化。
//   - 全部 UIKit 公有 API，不用私有类，跨版本稳定。
//

#import "SJPicker.h"
#import <QuartzCore/QuartzCore.h>

static UIWindow *gSJWindow = nil;
static SJPickerViewController *gSJController = nil;

@interface SJPickerViewController ()
@property (nonatomic, strong) NSArray<SJAppEntry *> *entries;
@property (nonatomic, strong) NSString *sourceName;
@property (nonatomic, strong) NSString *urlString;
@property (nonatomic, copy) void (^onCancel)(void);
@property (nonatomic, copy) void (^onSelect)(SJAppEntry *);
@property (nonatomic, strong) UIView *card;
@end

@implementation SJPickerViewController

#pragma mark - 生命周期

+ (BOOL)isPresenting
{
	return gSJWindow != nil;
}

+ (void)dismiss
{
	if (!gSJWindow) return;
	UIWindow *w = gSJWindow;
	SJPickerViewController *vc = gSJController;
	gSJWindow = nil;
	gSJController = nil;
	w.hidden = YES;

	void (^cleanup)(void) = ^{
		vc.onCancel = nil;
		vc.onSelect = nil;
		vc.view.hidden = YES;
	};
	[UIView animateWithDuration:0.18
	                     animations:^{
		                     w.alpha = 0;
	                     }
	                     completion:^(BOOL finished) {
		                     cleanup();
	                     }];
}

+ (UIWindowScene *)activeWindowScene
{
	UIApplication *app = [UIApplication sharedApplication];
	for (UIScene *s in app.connectedScenes) {
		if (![s isKindOfClass:[UIWindowScene class]]) continue;
		if (s.activationState == UISceneActivationStateForegroundActive) return (UIWindowScene *)s;
	}
	for (UIScene *s in app.connectedScenes) {
		if ([s isKindOfClass:[UIWindowScene class]]) return (UIWindowScene *)s;
	}
	return nil;
}

+ (void)presentWithSourceName:(NSString *)sourceName
                    urlString:(NSString *)urlString
                      entries:(NSArray<SJAppEntry *> *)entries
                       cancel:(void (^)(void))onCancel
                       select:(void (^)(SJAppEntry *))onSelect
{
	if (!entries.count) return;
	if (gSJWindow) return; // 已在显示，忽略重复请求

	SJPickerViewController *vc = [[SJPickerViewController alloc] init];
	vc.entries = entries;
	vc.sourceName = sourceName ?: @"";
	vc.urlString = urlString ?: @"";
	vc.onCancel = onCancel;
	vc.onSelect = onSelect;

	UIWindowScene *scene = [self activeWindowScene];
	UIWindow *w = nil;
	if (scene) {
		w = [[UIWindow alloc] initWithWindowScene:scene];
		w.frame = scene.coordinateSpace.bounds;
	} else {
		w = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
	}
	w.rootViewController = vc;
	w.windowLevel = UIWindowLevelAlert + 1;
	w.backgroundColor = [UIColor clearColor];
	w.alpha = 0;

	gSJWindow = w;
	gSJController = vc;

	[w makeKeyAndVisible];
	[UIView animateWithDuration:0.2
	                 animations:^{
		                 w.alpha = 1;
	                 }];
}

#pragma mark - 界面

- (void)loadView
{
	self.view = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
	self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
	self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

	UITapGestureRecognizer *tap =
	    [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(backgroundTapped)];
	[self.view addGestureRecognizer:tap];
}

- (void)viewDidLoad
{
	[super viewDidLoad];
	[self buildCard];
}

- (void)buildCard
{
	SJSettings *settings = [SJSettings shared];

	UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
	card.translatesAutoresizingMaskIntoConstraints = NO;
	card.backgroundColor = [UIColor systemBackgroundColor];
	card.layer.cornerRadius = 16;
	card.layer.cornerCurve = kCACornerCurveContinuous;
	card.clipsToBounds = YES;
	[self.view addSubview:card];
	self.card = card;

	// 标题
	UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
	title.translatesAutoresizingMaskIntoConstraints = NO;
	title.text = @"选择打开应用";
	title.font = [UIFont boldSystemFontOfSize:17];
	title.textAlignment = NSTextAlignmentCenter;

	// 副标题：发起方 / URL
	UILabel *sub = [[UILabel alloc] initWithFrame:CGRectZero];
	sub.translatesAutoresizingMaskIntoConstraints = NO;
	sub.font = [UIFont systemFontOfSize:12];
	sub.textColor = [UIColor secondaryLabelColor];
	sub.numberOfLines = 2;
	sub.textAlignment = NSTextAlignmentCenter;

	NSMutableArray<NSString *> *bits = [NSMutableArray array];
	if (settings.showSourceApp && self.sourceName.length) {
		[bits addObject:[NSString stringWithFormat:@"来自 %@", self.sourceName]];
	}
	if (self.urlString.length) {
		NSString *u = self.urlString;
		if (u.length > 64) u = [[u substringToIndex:61] stringByAppendingString:@"..."];
		[bits addObject:u];
	}
	sub.text = [bits componentsJoinedByString:@" · "];
	sub.hidden = (bits.count == 0);

	// 列表
	UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
	scroll.translatesAutoresizingMaskIntoConstraints = NO;
	scroll.alwaysBounceVertical = YES;
	scroll.showsVerticalScrollIndicator = YES;

	UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	stack.axis = UILayoutConstraintAxisVertical;
	stack.alignment = UIStackViewAlignmentFill;
	stack.spacing = 0;
	[scroll addSubview:stack];

	NSUInteger idx = 0;
	for (SJAppEntry *e in self.entries) {
		if (idx > 0) [stack addArrangedSubview:[self separator]];
		[stack addArrangedSubview:[self rowForEntry:e index:idx]];
		idx++;
	}

	// 取消按钮
	UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
	cancel.translatesAutoresizingMaskIntoConstraints = NO;
	[cancel setTitle:@"取消跳转" forState:UIControlStateNormal];
	cancel.titleLabel.font = [UIFont systemFontOfSize:16];
	[cancel setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
	[cancel addTarget:self
	            action:@selector(cancelTapped)
	  forControlEvents:UIControlEventTouchUpInside];

	[card addSubview:title];
	[card addSubview:sub];
	[card addSubview:scroll];
	[card addSubview:cancel];

	CGFloat maxH = [UIScreen mainScreen].bounds.size.height * 0.66;
	// 内容短时滚动区正好贴合内容；内容长时被上限截断并可滚动
	NSLayoutConstraint *scrollFit = [scroll.heightAnchor constraintEqualToAnchor:stack.heightAnchor];
	scrollFit.priority = 999;
	NSLayoutConstraint *scrollCap =
	    [scroll.heightAnchor constraintLessThanOrEqualToConstant:MAX(maxH - 150.0, 120.0)];

	[NSLayoutConstraint activateConstraints:@[
		[card.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[card.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
		[card.widthAnchor constraintEqualToConstant:312],
		[card.heightAnchor constraintLessThanOrEqualToConstant:maxH],

		[title.topAnchor constraintEqualToAnchor:card.topAnchor constant:16],
		[title.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
		[title.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],

		[sub.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4],
		[sub.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
		[sub.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],

		[scroll.topAnchor constraintEqualToAnchor:sub.bottomAnchor constant:12],
		[scroll.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
		[scroll.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
		scrollCap,
		scrollFit,

		[stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
		[stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
		[stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
		[stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
		[stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],

		[cancel.topAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:4],
		[cancel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
		[cancel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
		[cancel.heightAnchor constraintEqualToConstant:48],
		[cancel.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-4],
	]];
}

- (UIView *)separator
{
	UIView *line = [[UIView alloc] initWithFrame:CGRectZero];
	line.translatesAutoresizingMaskIntoConstraints = NO;
	line.backgroundColor = [UIColor separatorColor];
	[line.heightAnchor constraintEqualToConstant:0.5].active = YES;
	return line;
}

- (UIControl *)rowForEntry:(SJAppEntry *)entry index:(NSUInteger)index
{
	UIControl *row = [[UIControl alloc] initWithFrame:CGRectZero];
	row.translatesAutoresizingMaskIntoConstraints = NO;
	row.tag = (NSInteger)index;
	[row addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
	[row.heightAnchor constraintEqualToConstant:60].active = YES;

	// 图标
	UIView *iconBox = [self iconViewForEntry:entry];
	iconBox.translatesAutoresizingMaskIntoConstraints = NO;
	[row addSubview:iconBox];

	UILabel *name = [[UILabel alloc] initWithFrame:CGRectZero];
	name.translatesAutoresizingMaskIntoConstraints = NO;
	name.text = entry.title;
	name.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
	name.numberOfLines = 1;

	UILabel *detail = [[UILabel alloc] initWithFrame:CGRectZero];
	detail.translatesAutoresizingMaskIntoConstraints = NO;
	detail.text = entry.subtitle.length ? entry.subtitle : entry.bundleID;
	detail.font = [UIFont systemFontOfSize:11];
	detail.textColor = [UIColor secondaryLabelColor];
	detail.numberOfLines = 1;

	[row addSubview:name];
	[row addSubview:detail];

	[NSLayoutConstraint activateConstraints:@[
		[iconBox.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16],
		[iconBox.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
		[iconBox.widthAnchor constraintEqualToConstant:34],
		[iconBox.heightAnchor constraintEqualToConstant:34],

		[name.leadingAnchor constraintEqualToAnchor:iconBox.trailingAnchor constant:12],
		[name.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-16],
		[name.topAnchor constraintEqualToAnchor:row.topAnchor constant:11],

		[detail.leadingAnchor constraintEqualToAnchor:name.leadingAnchor],
		[detail.trailingAnchor constraintEqualToAnchor:name.trailingAnchor],
		[detail.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:2],
	]];

	return row;
}

- (UIView *)iconViewForEntry:(SJAppEntry *)entry
{
	UIImage *icon = entry.icon;
	if (icon) {
		UIImageView *iv = [[UIImageView alloc] initWithImage:icon];
		iv.contentMode = UIViewContentModeScaleAspectFit;
		iv.layer.cornerRadius = 8;
		iv.layer.cornerCurve = kCACornerCurveContinuous;
		iv.clipsToBounds = YES;
		return iv;
	}

	// 占位：首字母色块
	UIView *box = [[UIView alloc] initWithFrame:CGRectZero];
	box.backgroundColor = [UIColor secondarySystemFillColor];
	box.layer.cornerRadius = 8;
	box.layer.cornerCurve = kCACornerCurveContinuous;

	UILabel *ch = [[UILabel alloc] initWithFrame:CGRectZero];
	ch.translatesAutoresizingMaskIntoConstraints = NO;
	ch.text = entry.title.length ? [entry.title substringToIndex:1] : @"?";
	ch.font = [UIFont boldSystemFontOfSize:17];
	ch.textColor = [UIColor secondaryLabelColor];
	ch.textAlignment = NSTextAlignmentCenter;
	[box addSubview:ch];
	[NSLayoutConstraint activateConstraints:@[
		[ch.centerXAnchor constraintEqualToAnchor:box.centerXAnchor],
		[ch.centerYAnchor constraintEqualToAnchor:box.centerYAnchor],
	]];
	return box;
}

#pragma mark - 交互

- (void)rowTapped:(UIControl *)sender
{
	NSInteger i = sender.tag;
	if (i < 0 || (NSUInteger)i >= self.entries.count) return;
	SJAppEntry *entry = self.entries[(NSUInteger)i];

	UIImpactFeedbackGenerator *haptic =
	    [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
	[haptic impactOccurred];

	void (^cb)(SJAppEntry *) = self.onSelect;
	[SJPickerViewController dismiss];
	if (cb) cb(entry);
}

- (void)cancelTapped
{
	void (^cb)(void) = self.onCancel;
	[SJPickerViewController dismiss];
	if (cb) cb();
}

- (void)backgroundTapped
{
	[self cancelTapped];
}

@end
