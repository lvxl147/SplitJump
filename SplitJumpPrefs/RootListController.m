//
//  RootListController.m — SplitJump 设置主页
//
//  页面结构完全对齐 JumpSelect：
//    · 启用插件
//    · 拦截规则 —— 规则直接以「应用图标 + 名称」的形式列在这一节，
//                 点右上角 + / 最后一行新建；点某条进入编辑；左滑删除
//    · 放行黑名单 —— 点选多选应用，名单内的 App 发起跳转时直接放行
//    · 行为 / 高级 开关
//    · 清空规则
//    · 使用教程（页脚）
//
//  实现说明：
//   1. 这里是普通的 UITableViewController，不依赖 Preferences.framework 的
//      PSListController —— 开关的读写都走 SJRuleStore（CFPreferences 域）。
//   2. 之前踩过的坑（留档）：不要继承 PSListController 并重复声明 _specifiers，
//      Theos 的 PSListController.h 已声明过该 ivar，会报 duplicate member。
//   3. 子工程默认 -Werror，注意别留下未使用变量 / 废弃 API。
//

#import "RootListController.h"
#import "SJRuleEditorController.h"
#import "SJRuleStore.h"
#import "SJAppPicker.h"

#define SJ_KEY_ENABLED   @"Enabled"
#define SJ_KEY_URLONLY   @"URLOnly"
#define SJ_KEY_EARLY     @"EarlyHook"
#define SJ_KEY_DEBUG     @"DebugLog"

// 开关行的 tag -> key 映射
static NSString * const kSwitchKeys[] = {
	@"__none__",      // tag 0 占位
	SJ_KEY_ENABLED,   // tag 1
	SJ_KEY_URLONLY,   // tag 2
	SJ_KEY_EARLY,     // tag 3
	SJ_KEY_DEBUG,     // tag 4
};

static NSString * const kCellSwitch = @"SJRootSwitch";
static NSString * const kCellButton = @"SJRootButton";
static NSString * const kCellRule   = @"SJRootRule";

@interface SplitJumpRootListController ()
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *rules;
@property (nonatomic, strong) NSArray<NSString *> *blacklist;
@end

@implementation SplitJumpRootListController

- (instancetype)initWithStyle:(UITableViewStyle)style
{
	self = [super initWithStyle:style];
	if (self) {
		self.title = @"SplitJump";
		self.rules = [[SJRuleStore loadRules] mutableCopy];
		self.blacklist = [SJRuleStore loadBlacklist];
	}
	return self;
}

- (void)viewDidLoad
{
	[super viewDidLoad];
	self.tableView.rowHeight = 52;
	self.navigationItem.rightBarButtonItem =
	    [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
	                                              target:self
	                                              action:@selector(addRule)];
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	[self reloadRules];
}

#pragma mark - 动作

- (void)addRule
{
	SJRuleEditorController *vc = [[SJRuleEditorController alloc] initWithRule:nil];
	__weak typeof(self) w = self;
	vc.onSaved = ^{
		[w reloadRules];
	};
	[self.navigationController pushViewController:vc animated:YES];
}

- (void)reloadRules
{
	self.rules = [[SJRuleStore loadRules] mutableCopy];
	self.blacklist = [SJRuleStore loadBlacklist];
	[self.tableView reloadData];
}

- (void)editRule:(NSInteger)index
{
	if (index < 0 || index >= (NSInteger)self.rules.count) return;
	SJRuleEditorController *vc = [[SJRuleEditorController alloc] initWithRule:self.rules[index]];
	__weak typeof(self) w = self;
	vc.onSaved = ^{
		[w reloadRules];
	};
	[self.navigationController pushViewController:vc animated:YES];
}

- (void)editBlacklist
{
	__weak typeof(self) w = self;
	[SJAppPicker presentFrom:self
	                   title:@"选择放行黑名单"
	                     multi:YES
	        preselected:[NSSet setWithArray:self.blacklist]
	                   onFinish:^(NSArray<NSString *> *ids) {
		                   NSMutableArray *out = [ids mutableCopy];
		                   // SpringBoard 始终保留，否则桌面点图标也会弹窗
		                   if (![out containsObject:@"com.apple.springboard"]) {
			                   [out insertObject:@"com.apple.springboard" atIndex:0];
		                   }
		                   [SJRuleStore saveBlacklist:out];
		                   [w reloadRules];
	                   }];
}

- (void)clearRules
{
	UIAlertController *alert =
	    [UIAlertController alertControllerWithTitle:@"清空规则"
	                                        message:@"确定全部清空？"
	                                 preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"取消"
	                                          style:UIAlertActionStyleCancel
	                                        handler:nil]];
	__weak typeof(self) w = self;
	[alert addAction:[UIAlertAction actionWithTitle:@"确定"
	                                          style:UIAlertActionStyleDestructive
	                                        handler:^(UIAlertAction *a) {
		                                        [SJRuleStore clearRules];
		                                        [w reloadRules];
	                                        }]];
	[self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 开关

- (void)switchChanged:(UISwitch *)sw
{
	NSString *key = (sw.tag > 0 && sw.tag < 5) ? kSwitchKeys[sw.tag] : nil;
	if (key.length == 0) return;
	[SJRuleStore setBool:sw.on forKey:key];
}

- (UITableViewCell *)switchCell:(UITableView *)tv
                  reuseIdentifier:(NSString *)rid
                            title:(NSString *)title
                              key:(NSString *)key
                           defVal:(BOOL)def
                              tag:(NSInteger)tag
{
	UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:rid];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
		                              reuseIdentifier:rid];
		UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectZero];
		[sw addTarget:self action:@selector(switchChanged:)
		     forControlEvents:UIControlEventValueChanged];
		cell.accessoryView = sw;
	}
	UISwitch *sw = (UISwitch *)cell.accessoryView;
	sw.tag = tag;
	sw.on = [SJRuleStore boolForKey:key defaultValue:def];
	cell.textLabel.text = title;
	cell.imageView.image = nil;
	cell.detailTextLabel.text = nil;
	return cell;
}

#pragma mark - Table 数据

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 6; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section
{
	switch (section) {
		case 0: return 1;                                  // 启用插件
		case 1: return (NSInteger)self.rules.count + 1;    // 拦截规则 + 添加
		case 2: return 1;                                  // 放行黑名单
		case 3: return 1;                                  // 行为
		case 4: return 2;                                  // 高级
		case 5: return 1;                                  // 清空规则
		default: return 0;
	}
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section
{
	switch (section) {
		case 0: return @"总开关";
		case 1: return @"拦截规则";
		case 2: return @"放行黑名单";
		case 3: return @"行为";
		case 4: return @"高级";
		default: return nil;
	}
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section
{
	if (section == 1) {
		return @"使用教程：\n"
		       @"1. 拦截应用：设置你需要被拦截唤起的 App 本体（如：微信），"
		       @"需要选择从 AppStore 安装的官方正版应用；另外要注意：已做过注入 / 多开的 App 不要设为拦截目标。\n"
		       @"2. 列表应用显示：一般设置多开应用，设置后触发拦截弹窗，"
		       @"弹窗内显示你选择的 App（如：微信分身1、分身2）。\n"
		       @"3. 放行黑名单：当黑名单列表内的 App 尝试唤起被拦截目标时，直接放行，不弹窗。\n"
		       @"修改后立即生效，无需注销。";
	}
	if (section == 2) {
		return @"当以下应用发起跳转时，直接放行且不触发弹窗。";
	}
	if (section == 3) {
		return @"开启后仅拦截带 URL 的跳转（支付、授权、分享等），普通打开不拦截。";
	}
	if (section == 4) {
		return @"提早拦截：装有分屏 / 浮窗类插件（如 Stheno）且面板不出现时再开启，开启后请自行验证各类跳转。\n"
		       @"写入调试日志：输出到 /var/mobile/Library/Logs/SplitJump.log";
	}
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip
{
	if (ip.section == 0) {
		return [self switchCell:tv reuseIdentifier:kCellSwitch
		                  title:@"启用插件" key:SJ_KEY_ENABLED defVal:YES tag:1];
	}

	if (ip.section == 1) {
		UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:kCellRule];
		if (!cell) {
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
			                              reuseIdentifier:kCellRule];
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		}

		if (ip.row == (NSInteger)self.rules.count) {
			cell.textLabel.text = @"＋ 添加拦截规则";
			cell.textLabel.textColor = [UIColor systemBlueColor];
			cell.detailTextLabel.text = nil;
			cell.imageView.image = nil;
			return cell;
		}

		NSDictionary *r = self.rules[ip.row];
		NSString *target = r[@"target"];
		NSString *name = [SJAppPicker displayNameForBundleID:target];
		NSArray *cands = [r[@"candidates"] isKindOfClass:[NSArray class]]
		    ? r[@"candidates"] : @[];
		NSString *sub = [NSString stringWithFormat:@"%@ → %lu 个候选", target,
		                 (unsigned long)cands.count];

		// 开了「直接跳转」的规则在名字后面标注，一眼能看出来
		BOOL dj = [r[@"directJump"] boolValue];
		cell.textLabel.text = dj ? [name stringByAppendingString:@"（直接跳转）"] : name;
		cell.detailTextLabel.text = sub;
		cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
		cell.imageView.image = [SJAppPicker iconForBundleID:target];
		cell.imageView.layer.cornerRadius = 8;
		cell.imageView.layer.cornerCurve = kCACornerCurveContinuous;
		cell.imageView.clipsToBounds = YES;
		return cell;
	}

	if (ip.section == 2) {
		UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:kCellButton];
		if (!cell) {
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
			                              reuseIdentifier:kCellButton];
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		}
		cell.textLabel.text = [NSString stringWithFormat:@"选择放行黑名单（%lu 个）",
		                       (unsigned long)self.blacklist.count];
		cell.textLabel.textColor = [UIColor systemBlueColor];
		cell.detailTextLabel.text = [self.blacklist componentsJoinedByString:@", "];
		cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
		cell.imageView.image = nil;
		return cell;
	}

	if (ip.section == 3) {
		return [self switchCell:tv reuseIdentifier:kCellSwitch
		                  title:@"仅拦截带 URL 的跳转" key:SJ_KEY_URLONLY defVal:NO tag:2];
	}

	if (ip.section == 4) {
		if (ip.row == 0) {
			return [self switchCell:tv reuseIdentifier:kCellSwitch
			                  title:@"提早拦截" key:SJ_KEY_EARLY defVal:NO tag:3];
		}
		return [self switchCell:tv reuseIdentifier:kCellSwitch
		                  title:@"写入调试日志" key:SJ_KEY_DEBUG defVal:NO tag:4];
	}

	// 清空规则
	UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:kCellButton];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
		                              reuseIdentifier:kCellButton];
	}
	cell.textLabel.text = @"清空规则";
	cell.textLabel.textColor = [UIColor systemRedColor];
	cell.textLabel.textAlignment = NSTextAlignmentCenter;
	cell.imageView.image = nil;
	cell.accessoryType = UITableViewCellAccessoryNone;
	return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip
{
	[tv deselectRowAtIndexPath:ip animated:YES];

	switch (ip.section) {
		case 1:
			if (ip.row == (NSInteger)self.rules.count) [self addRule];
			else [self editRule:ip.row];
			return;
		case 2: [self editBlacklist]; return;
		case 5: [self clearRules]; return;
		default: return;
	}
}

#pragma mark - 左滑删除规则

- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)ip
{
	return ip.section == 1 && ip.row < (NSInteger)self.rules.count;
}

- (void)tableView:(UITableView *)tv
    commitEditingStyle:(UITableViewCellEditingStyle)style
     forRowAtIndexPath:(NSIndexPath *)ip
{
	if (style != UITableViewCellEditingStyleDelete) return;
	if (ip.row >= (NSInteger)self.rules.count) return;

	[self.rules removeObjectAtIndex:ip.row];
	[SJRuleStore saveRules:self.rules];
	[self.tableView reloadData];
}

@end
