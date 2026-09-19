//
//  SJAppPicker.m
//
//  踩坑留档（v1.2.0 在「设置」里闪退的修复）：
//   1. 之前用 ((id(*)(id,SEL))objc_msgSend)(obj, sel) 调私有方法 —— ARC 下编译器
//      不认识这是 objc_msgSend，不会插入 retainAutoreleasedReturnValue，
//      返回自动释放对象时存在悬垂 / 失衡风险。这里统一换成 NSInvocation（与主插件一致）。
//   2. 之前在 cellForRow 里直接调 LSApplicationWorkspace（每行都枚举一次全部应用），
//      现在改成后台枚举一次并缓存，cell 只查缓存。
//   3. 图标私有方法全部包 @try，取不到就返回 nil。
//   4. 本子工程默认 -Werror，别留未使用变量 / 废弃 API。
//

#import "SJAppPicker.h"
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

@interface SJInstalledApp : NSObject
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) BOOL isUser;
@end
@implementation SJInstalledApp
@end

#pragma mark - NSInvocation 安全调用（ARC 友好，不做 objc_msgSend 强转）

static id SJPInvoke(id target, NSString *selName, NSArray *args)
{
	if (!target || selName.length == 0) return nil;
	SEL sel = NSSelectorFromString(selName);
	if (!sel || ![target respondsToSelector:sel]) return nil;

	NSMethodSignature *sig = [target methodSignatureForSelector:sel];
	if (!sig) return nil;

	NSUInteger want = args ? args.count : 0;
	if (sig.numberOfArguments != want + 2) return nil;

	NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
	[inv setTarget:target];
	[inv setSelector:sel];

	for (NSUInteger i = 0; i < want; i++) {
		id a = args[i];
		NSUInteger idx = i + 2;
		const char *t = [sig getArgumentTypeAtIndex:idx];
		if (t[0] == '@') {
			__unsafe_unretained id v = a;
			[inv setArgument:&v atIndex:idx];
		} else if (t[0] == 'c' || t[0] == 'B') {
			BOOL v = [a boolValue];
			[inv setArgument:&v atIndex:idx];
		} else if (t[0] == 'i') {
			int v = [a intValue];
			[inv setArgument:&v atIndex:idx];
		} else if (t[0] == 'q') {
			long long v = [a longLongValue];
			[inv setArgument:&v atIndex:idx];
		} else if (t[0] == 'd') {
			double v = [a doubleValue];
			[inv setArgument:&v atIndex:idx];
		} else {
			__unsafe_unretained id v = a;
			[inv setArgument:&v atIndex:idx];
		}
	}

	@try {
		[inv invoke];
	} @catch (NSException *e) {
		return nil;
	}

	if (sig.methodReturnType[0] != '@') return nil;
	__unsafe_unretained id r = nil;
	[inv getReturnValue:&r];
	return r;
}

/// +[UIImage _applicationIconImageForBundleIdentifier:format:scale:]
static UIImage *SJPAppIcon(NSString *bid)
{
	if (bid.length == 0) return nil;
	Class c = [UIImage class];
	SEL sel = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
	Method m = class_getClassMethod(c, sel);
	if (!m) return nil;

	NSMethodSignature *sig = [c methodSignatureForSelector:sel];
	if (!sig || sig.numberOfArguments < 5) return nil;

	NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
	[inv setTarget:c];
	[inv setSelector:sel];

	__unsafe_unretained NSString *b = bid;
	int format = 0;
	double scale = [UIScreen mainScreen].scale;
	if (scale <= 0) scale = 3.0;

	[inv setArgument:&b atIndex:2];
	[inv setArgument:&format atIndex:3];
	[inv setArgument:&scale atIndex:4];

	@try {
		[inv invoke];
	} @catch (NSException *e) {
		return nil;
	}

	__unsafe_unretained UIImage *img = nil;
	[inv getReturnValue:&img];
	return img;
}

#pragma mark - 缓存

static NSArray<SJInstalledApp *> *sjAllApps = nil;
static NSMutableDictionary<NSString *, NSString *> *sjNameCache = nil;
static dispatch_queue_t sjQueue(void)
{
	static dispatch_queue_t q;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		q = dispatch_queue_create("lvxl524.splitjump.appcache", DISPATCH_QUEUE_SERIAL);
	});
	return q;
}

+ (void)buildCacheLocked
{
	NSMutableArray<SJInstalledApp *> *out = [NSMutableArray array];
	NSMutableDictionary<NSString *, NSString *> *names = [NSMutableDictionary dictionary];

	@try {
		Class cls = NSClassFromString(@"LSApplicationWorkspace");
		id ws = cls ? SJPInvoke((id)cls, @"defaultWorkspace", @[]) : nil;
		NSArray *all = ws ? SJPInvoke(ws, @"allInstalledApplications", @[]) : nil;

		if ([all isKindOfClass:[NSArray class]]) {
			for (id proxy in all) {
				NSString *bid = SJPInvoke(proxy, @"bundleIdentifier", @[]);
				if (![bid isKindOfClass:[NSString class]] || bid.length == 0) continue;

				NSString *name = nil;
				for (NSString *k in @[ @"localizedShortName", @"localizedName", @"itemName" ]) {
					NSString *v = SJPInvoke(proxy, k, @[]);
					if ([v isKindOfClass:[NSString class]] && v.length > 0) { name = v; break; }
				}
				if (name.length == 0) name = bid;

				NSString *type = SJPInvoke(proxy, @"applicationType", @[]);
				BOOL user = [type isKindOfClass:[NSString class]]
				    ? [type isEqualToString:@"User"] : YES;

				SJInstalledApp *a = [[SJInstalledApp alloc] init];
				a.bundleID = bid;
				a.name = name;
				a.isUser = user;
				[out addObject:a];

				names[bid] = name;
			}
		}
	} @catch (NSException *e) {
		// 枚举失败就保持空缓存：面板仍可用，只是显示包名
	}

	[out sortUsingComparator:^NSComparisonResult(SJInstalledApp *x, SJInstalledApp *y) {
		return [x.name caseInsensitiveCompare:y.name];
	}];

	sjAllApps = out;
	sjNameCache = names;
}

#pragma mark - 对外

+ (void)warmUp:(void (^)(void))done
{
	dispatch_async(sjQueue(), ^{
		if (!sjAllApps) [self buildCacheLocked];
		if (done) dispatch_async(dispatch_get_main_queue(), done);
	});
}

+ (NSString *)displayNameForBundleID:(NSString *)bundleID
{
	if (bundleID.length == 0) return @"";
	NSString *n = sjNameCache[bundleID];
	return n.length > 0 ? n : bundleID;
}

+ (UIImage *)iconForBundleID:(NSString *)bundleID
{
	if (bundleID.length == 0) return nil;
	@try {
		return SJPAppIcon(bundleID);
	} @catch (NSException *e) {
		return nil;
	}
}

+ (NSArray<SJInstalledApp *> *)userApps
{
	NSMutableArray<SJInstalledApp *> *out = [NSMutableArray array];
	for (SJInstalledApp *a in sjAllApps) {
		if (a.isUser) [out addObject:a];
	}
	return out;
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

	UISearchController *sc =
	    [[UISearchController alloc] initWithSearchResultsController:nil];
	sc.searchResultsUpdater = self;
	sc.obscuresBackgroundDuringPresentation = NO;
	sc.searchBar.placeholder = @"搜索应用名称或包名";
	self.search = sc;
	self.tableView.tableHeaderView = sc.searchBar;
	self.definesPresentationContext = YES;

	self.visibleApps = @[];
	[self.tableView reloadData];

	// 后台取列表，好了回主线程刷新（不阻塞、不闪退）
	__weak typeof(self) w = self;
	[SJAppPicker warmUp:^{
		w.allApps = [SJAppPicker userApps];
		w.visibleApps = w.allApps;
		[w.tableView reloadData];
	}];
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
	if (!a) return cell;

	cell.textLabel.text = a.name;
	cell.detailTextLabel.text = a.bundleID;
	cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
	cell.imageView.image = [SJAppPicker iconForBundleID:a.bundleID];

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
