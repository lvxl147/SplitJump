//
//  SJAppPicker.m
//
//  注意：Theos 对这个子工程默认开 -Werror，任何告警都会导致编译失败。
//  所以这里不用 performSelector:（会触发 -Warc-performSelector-leaks），
//  统一用 objc_msgSend 强转；也不要在 id 上直接取 .length（那是硬错误）。
//

#import "SJAppPicker.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <QuartzCore/QuartzCore.h>

@interface SJInstalledApp : NSObject
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) BOOL isUser;
@end
@implementation SJInstalledApp
@end

// 0 参 / 1 参的 objc_msgSend 强转（本文件只用到无参方法）
static inline id SJSend0(id obj, SEL sel)
{
	if (!obj || !sel) return nil;
	return ((id(*)(id, SEL))objc_msgSend)(obj, sel);
}

/// +[UIImage _applicationIconImageForBundleIdentifier:format:scale:]
static UIImage *SJPAppIcon(NSString *bid)
{
	if (!bid.length) return nil;
	Class c = [UIImage class];
	SEL sel = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
	Method m = class_getClassMethod(c, sel);
	if (!m) return nil;
	typedef UIImage *(*fn_t)(id, SEL, NSString *, int, double);
	fn_t f = (fn_t)method_getImplementation(m);
	double scale = [UIScreen mainScreen].scale;
	if (scale <= 0) scale = 3.0;
	return f((id)c, sel, bid, 0, scale);
}

@interface SJAppPicker () <UISearchResultsUpdating>
@property (nonatomic, strong) NSArray<SJInstalledApp *> *allApps;
@property (nonatomic, strong) NSArray<SJInstalledApp *> *visibleApps;
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *selected;
@property (nonatomic, strong) UISearchController *search;
@property (nonatomic, copy) NSString *pickerTitle;
@property (nonatomic, assign) BOOL multi;
@property (nonatomic, copy) void (^onFinish)(NSArray<NSString *> *);
@end

@implementation SJAppPicker

#pragma mark - 应用枚举

+ (NSArray<SJInstalledApp *> *)enumerateApps
{
	NSMutableArray<SJInstalledApp *> *out = [NSMutableArray array];

	Class cls = NSClassFromString(@"LSApplicationWorkspace");
	if (!cls) return out;
	id ws = SJSend0((id)cls, NSSelectorFromString(@"defaultWorkspace"));
	if (!ws) return out;

	NSArray *all = SJSend0(ws, NSSelectorFromString(@"allInstalledApplications"));
	if (![all isKindOfClass:[NSArray class]]) return out;

	for (id proxy in all) {
		SEL bidSel = NSSelectorFromString(@"bundleIdentifier");
		if (![proxy respondsToSelector:bidSel]) continue;

		NSString *bid = SJSend0(proxy, bidSel);
		if (![bid isKindOfClass:[NSString class]]) continue;

		NSString *name = nil;
		for (NSString *k in @[ @"localizedShortName", @"localizedName", @"itemName" ]) {
			SEL s = NSSelectorFromString(k);
			if (![proxy respondsToSelector:s]) continue;
			NSString *v = SJSend0(proxy, s);
			if ([v isKindOfClass:[NSString class]] && v.length > 0) { name = v; break; }
		}
		if (name.length == 0) name = bid;

		BOOL user = YES;
		SEL t = NSSelectorFromString(@"applicationType");
		if ([proxy respondsToSelector:t]) {
			NSString *v = SJSend0(proxy, t);
			if ([v isKindOfClass:[NSString class]]) user = [v isEqualToString:@"User"];
		}

		SJInstalledApp *a = [[SJInstalledApp alloc] init];
		a.bundleID = bid;
		a.name = name;
		a.isUser = user;
		[out addObject:a];
	}

	[out sortUsingComparator:^NSComparisonResult(SJInstalledApp *x, SJInstalledApp *y) {
		return [x.name caseInsensitiveCompare:y.name];
	}];
	return out;
}

#pragma mark - 对外取值助手

+ (NSString *)displayNameForBundleID:(NSString *)bundleID
{
	if (bundleID.length == 0) return @"";
	for (SJInstalledApp *a in [self enumerateApps]) {
		if ([a.bundleID isEqualToString:bundleID]) return a.name;
	}
	return bundleID;
}

+ (UIImage *)iconForBundleID:(NSString *)bundleID
{
	return SJPAppIcon(bundleID);
}

#pragma mark - 入口

+ (void)presentFrom:(UIViewController *)host
              title:(NSString *)title
              multi:(BOOL)multi
        preselected:(NSSet<NSString *> *)pre
           onFinish:(void (^)(NSArray<NSString *> *))onFinish
{
	if (!host.navigationController) return;

	SJAppPicker *vc = [[SJAppPicker alloc] initWithStyle:UITableViewStylePlain];
	vc.pickerTitle = title ?: (multi ? @"选择应用（可多选）" : @"选择应用");
	vc.multi = multi;
	vc.selected = [[NSMutableOrderedSet alloc] initWithArray:pre.allObjects];
	vc.onFinish = onFinish;
	[host.navigationController pushViewController:vc animated:YES];
}

#pragma mark - 生命周期

- (void)viewDidLoad
{
	[super viewDidLoad];
	self.title = self.pickerTitle;
	self.tableView.rowHeight = 56;

	if (self.multi) {
		self.navigationItem.rightBarButtonItem =
		    [[UIBarButtonItem alloc] initWithTitle:@"完成"
		                                     style:UIBarButtonItemStyleDone
		                                    target:self
		                                    action:@selector(finishTapped)];
	}

	// 搜索框：按名称 / 包名过滤
	UISearchController *sc =
	    [[UISearchController alloc] initWithSearchResultsController:nil];
	sc.searchResultsUpdater = self;
	sc.obscuresBackgroundDuringPresentation = NO;
	sc.searchBar.placeholder = @"搜索应用名称或包名";
	self.search = sc;
	self.tableView.tableHeaderView = sc.searchBar;
	self.definesPresentationContext = YES;

	// 已装应用可能不少，枚举放后台线程，回主线程刷新
	self.visibleApps = @[];
	[self.tableView reloadData];
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSArray<SJInstalledApp *> *apps = [SJAppPicker enumerateApps];
		dispatch_async(dispatch_get_main_queue(), ^{
			self.allApps = apps;
			self.visibleApps = apps;
			[self.tableView reloadData];
		});
	});
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	self.search.active = NO;
}

#pragma mark - 搜索

- (void)updateSearchResultsForSearchController:(UISearchController *)sc
{
	NSString *kw = [sc.searchBar.text stringByTrimmingCharactersInSet:
	                         [NSCharacterSet whitespaceCharacterSet]];

	if (kw.length == 0) {
		self.visibleApps = self.allApps;
	} else {
		NSPredicate *p = [NSPredicate predicateWithFormat:
		                  @"name CONTAINS[cd] %@ OR bundleID CONTAINS[cd] %@", kw, kw];
		self.visibleApps = [self.allApps filteredArrayUsingPredicate:p];
	}
	[self.tableView reloadData];
}

#pragma mark - 交互

- (void)finishTapped
{
	// NSOrderedSet 不是 NSArray，这里显式转成数组再回调
	NSArray<NSString *> *out = [self.selected array];
	void (^cb)(NSArray<NSString *> *) = self.onFinish;
	[self.navigationController popViewControllerAnimated:YES];
	if (cb) cb(out);
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section
{
	return (NSInteger)self.visibleApps.count;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section
{
	return self.allApps.count
	    ? [NSString stringWithFormat:@"共 %lu 个应用，顶部搜索框支持按名称或包名过滤。",
	      (unsigned long)self.allApps.count]
	    : @"正在读取已安装应用…";
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip
{
	static NSString *id_ = @"SJAppCell";
	UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:id_];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
		                              reuseIdentifier:id_];
		cell.imageView.layer.cornerRadius = 8;
		cell.imageView.layer.cornerCurve = kCACornerCurveContinuous;
		cell.imageView.clipsToBounds = YES;
	}

	SJInstalledApp *a = self.visibleApps[ip.row];
	cell.textLabel.text = a.name;
	cell.detailTextLabel.text = a.bundleID;
	cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
	cell.imageView.image = SJPAppIcon(a.bundleID); // 取不到就留空

	if (self.multi) {
		BOOL on = [self.selected containsObject:a.bundleID];
		cell.accessoryType = on ? UITableViewCellAccessoryCheckmark
		                        : UITableViewCellAccessoryNone;
		cell.tintColor = [UIColor systemBlueColor];
	} else {
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	}
	return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip
{
	[tv deselectRowAtIndexPath:ip animated:YES];
	SJInstalledApp *a = self.visibleApps[ip.row];
	if (!a) return;

	UITableViewCell *cell = [tv cellForRowAtIndexPath:ip];

	if (!self.multi) {
		void (^cb)(NSArray<NSString *> *) = self.onFinish;
		[self.navigationController popViewControllerAnimated:YES];
		if (cb) cb(@[ a.bundleID ]);
		return;
	}

	if ([self.selected containsObject:a.bundleID]) {
		[self.selected removeObject:a.bundleID];
		cell.accessoryType = UITableViewCellAccessoryNone;
	} else {
		[self.selected addObject:a.bundleID];
		cell.accessoryType = UITableViewCellAccessoryCheckmark;
	}
}

@end
