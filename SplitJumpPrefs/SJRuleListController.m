//
//  SJRuleListController.m
//
//  界面结构（对齐 JumpSelect 的使用习惯）：
//    · 放行黑名单 —— 点进去多选应用，名单内的 App 发起跳转时直接放行
//    · 拦截规则  —— 每条规则 = 一个「被拦截的目标应用」+ 若干「列表应用」
//                  右上角 + 新建，点某条进入编辑，左滑删除
//

#import "SJRuleListController.h"
#import "SJRuleStore.h"
#import "SJAppPicker.h"
#import "SJRuleEditorController.h"

static NSString *const kCellID = @"SJRuleCell";

@interface SJRuleListController ()
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *rules;
@property (nonatomic, strong) NSArray<NSString *> *blacklist;
@end

@implementation SJRuleListController

- (instancetype)initWithStyle:(UITableViewStyle)style
{
	self = [super initWithStyle:style];
	if (self) {
		self.title = @"拦截规则";
		self.rules = [[SJRuleStore loadRules] mutableCopy];
		self.blacklist = [SJRuleStore loadBlacklist];
	}
	return self;
}

- (void)viewDidLoad
{
	[super viewDidLoad];
	self.navigationItem.rightBarButtonItem =
	    [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
	                                              target:self
	                                              action:@selector(addRule)];
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	[self reloadData];
}

- (void)reloadData
{
	self.rules = [[SJRuleStore loadRules] mutableCopy];
	self.blacklist = [SJRuleStore loadBlacklist];
	[self.tableView reloadData];
}

#pragma mark - 动作

- (void)addRule
{
	SJRuleEditorController *vc = [[SJRuleEditorController alloc] initWithRule:nil];
	__weak typeof(self) w = self;
	vc.onSaved = ^{
		[w reloadData];
	};
	[self.navigationController pushViewController:vc animated:YES];
}

- (void)editBlacklist
{
	__weak typeof(self) w = self;
	[SJAppPicker presentFrom:self
	                   title:@"放行黑名单（这些 App 发起跳转时不弹窗）"
	                     multi:YES
	                preselected:[NSSet setWithArray:self.blacklist]
	                   onFinish:^(NSArray<NSString *> *ids) {
		                   // 默认始终保留 SpringBoard，否则桌面点图标也会弹窗
		                   NSMutableArray *out = [ids mutableCopy];
		                   if (![out containsObject:@"com.apple.springboard"]) {
			                   [out insertObject:@"com.apple.springboard" atIndex:0];
		                   }
		                   [SJRuleStore saveBlacklist:out];
		                   [w reloadData];
	                   }];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section
{
	if (section == 0) return 1;
	return self.rules.count ? (NSInteger)self.rules.count : 1;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section
{
	return section == 0 ? @"放行黑名单" : @"拦截规则";
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section
{
	if (section == 0) {
		return @"名单内的 App 尝试唤起被拦截目标时，直接放行、不弹窗。"
		       @"com.apple.springboard 始终保留，避免桌面点图标也弹窗。";
	}
	return @"每条规则：被拦截的目标应用 + 弹窗里供你选择的列表应用。"
	       @"一般列表应用就填该应用的各个多开分身。";
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip
{
	UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:kCellID];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
		                              reuseIdentifier:kCellID];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	}

	if (ip.section == 0) {
		cell.textLabel.text = [NSString stringWithFormat:@"放行黑名单（%lu 个）",
		                       (unsigned long)self.blacklist.count];
		cell.detailTextLabel.text = [self.blacklist componentsJoinedByString:@", "];
		cell.imageView.image = nil;
		return cell;
	}

	if (!self.rules.count) {
		cell.textLabel.text = @"暂无规则";
		cell.detailTextLabel.text = @"点击右上角 + 添加拦截规则";
		cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
		cell.imageView.image = nil;
		cell.accessoryType = UITableViewCellAccessoryNone;
		return cell;
	}

	NSDictionary *r = self.rules[ip.row];
	NSString *target = r[@"target"];
	NSArray *cands = r[@"candidates"] ?: @[];
	NSString *name = [SJAppPicker displayNameForBundleID:target];

	cell.textLabel.text = name;
	cell.detailTextLabel.text =
	    [NSString stringWithFormat:@"%@ → %lu 个候选", target, (unsigned long)cands.count];
	cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
	cell.imageView.image = [SJAppPicker iconForBundleID:target];
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip
{
	[tv deselectRowAtIndexPath:ip animated:YES];

	if (ip.section == 0) { [self editBlacklist]; return; }
	if (!self.rules.count) { [self addRule]; return; }

	SJRuleEditorController *vc =
	    [[SJRuleEditorController alloc] initWithRule:self.rules[ip.row]];
	__weak typeof(self) w = self;
	vc.onSaved = ^{
		[w reloadData];
	};
	[self.navigationController pushViewController:vc animated:YES];
}

- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)ip
{
	return ip.section == 1 && self.rules.count > 0;
}

- (void)tableView:(UITableView *)tv
    commitEditingStyle:(UITableViewCellEditingStyle)style
     forRowAtIndexPath:(NSIndexPath *)ip
{
	if (style != UITableViewCellEditingStyleDelete) return;
	if (ip.row >= (NSInteger)self.rules.count) return;

	[self.rules removeObjectAtIndex:ip.row];
	[SJRuleStore saveRules:self.rules];
	[self reloadData];
}

@end
