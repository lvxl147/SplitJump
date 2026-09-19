//
//  SJRuleListController.m — 拦截规则列表
//
//  这是 push 进来的普通 UITableViewController（主页保持 PSListController，
//  见 RootListController.h 的说明），所以这里可以自由做动态行。
//
//  每条规则显示目标应用的图标 / 名称 / 候选数；右上角 + 新建；
//  点某条进入编辑；左滑删除。
//

#import "SJRuleListController.h"
#import "SJRuleStore.h"
#import "SJAppPicker.h"
#import "SJRuleEditorController.h"

static NSString * const kCellID = @"SJRuleCell";

@interface SJRuleListController ()
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *rules;
@end

@implementation SJRuleListController

- (instancetype)initWithStyle:(UITableViewStyle)style
{
	self = [super initWithStyle:style];
	if (self) {
		self.title = @"拦截规则";
		self.rules = [[SJRuleStore loadRules] mutableCopy];
	}
	return self;
}

- (void)viewDidLoad
{
	[super viewDidLoad];
	self.tableView.rowHeight = 56;
	self.navigationItem.rightBarButtonItem =
	    [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
	                                              target:self
	                                              action:@selector(addRule)];
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	[self reloadRules];
	[SJAppPicker warmUp:nil];
}

- (void)reloadRules
{
	self.rules = [[SJRuleStore loadRules] mutableCopy];
	[self.tableView reloadData];
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

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section
{
	return self.rules.count ? (NSInteger)self.rules.count : 1;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section
{
	return self.rules.count
	    ? @"点某条规则可编辑，左滑可删除。修改后立即生效，无需注销。"
	    : @"还没有拦截规则。点击右上角 + 新建一条。";
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip
{
	UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:kCellID];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
		                              reuseIdentifier:kCellID];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	}

	if (self.rules.count == 0) {
		cell.textLabel.text = @"暂无规则";
		cell.detailTextLabel.text = nil;
		cell.imageView.image = nil;
		cell.accessoryType = UITableViewCellAccessoryNone;
		return cell;
	}

	NSDictionary *r = self.rules[ip.row];
	NSString *target = r[@"target"];
	NSString *bid = [target isKindOfClass:[NSString class]] ? target : @"";
	NSArray *cands = [r[@"candidates"] isKindOfClass:[NSArray class]] ? r[@"candidates"] : @[];
	NSString *name = [SJAppPicker displayNameForBundleID:bid];

	BOOL dj = [r[@"directJump"] boolValue];
	cell.textLabel.text = dj ? [name stringByAppendingString:@"（直接跳转）"] : name;
	cell.detailTextLabel.text =
	    [NSString stringWithFormat:@"%@ → %lu 个候选", bid, (unsigned long)cands.count];
	cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
	cell.imageView.image = [SJAppPicker iconForBundleID:bid];
	cell.imageView.layer.cornerRadius = 8;
	cell.imageView.layer.cornerCurve = kCACornerCurveContinuous;
	cell.imageView.clipsToBounds = YES;
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip
{
	[tv deselectRowAtIndexPath:ip animated:YES];
	if (self.rules.count == 0) { [self addRule]; return; }
	if (ip.row >= (NSInteger)self.rules.count) return;

	SJRuleEditorController *vc = [[SJRuleEditorController alloc] initWithRule:self.rules[ip.row]];
	__weak typeof(self) w = self;
	vc.onSaved = ^{
		[w reloadRules];
	};
	[self.navigationController pushViewController:vc animated:YES];
}

- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)ip
{
	return self.rules.count > 0 && ip.row < (NSInteger)self.rules.count;
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
	void (^cb)(void) = self.onSaved;
	if (cb) cb();
}

@end
