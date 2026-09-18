//
//  SJRuleEditorController.m
//
//  单条规则的编辑页：
//    第 1 节  拦截应用（单选）—— 被拦截唤起的目标应用本体
//    第 2 节  列表应用（多选）—— 弹窗里显示的候选，一般是该应用的各个多开分身
//    第 3 节  保存
//

#import "SJRuleEditorController.h"
#import "SJAppPicker.h"
#import "SJRuleStore.h"

@interface SJRuleEditorController ()
@property (nonatomic, copy) NSString *target;
@property (nonatomic, strong) NSMutableArray<NSString *> *candidates;
@property (nonatomic, copy) void (^onSaved)(void);
@end

@implementation SJRuleEditorController

- (instancetype)initWithRule:(NSDictionary *)rule
{
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self) {
		self.title = rule ? @"编辑拦截规则" : @"添加拦截规则";
		self.target = [rule[@"target"] isKindOfClass:[NSString class]]
		    ? rule[@"target"] : nil;
		NSArray *c = [rule[@"candidates"] isKindOfClass:[NSArray class]]
		    ? rule[@"candidates"] : @[];
		self.candidates = [c mutableCopy] ?: [NSMutableArray array];

		self.navigationItem.rightBarButtonItem =
		    [[UIBarButtonItem alloc] initWithTitle:@"保存"
		                                     style:UIBarButtonItemStyleDone
		                                    target:self
		                                    action:@selector(save)];
	}
	return self;
}

- (void)viewDidLoad
{
	[super viewDidLoad];
	self.tableView.rowHeight = 52;
}

#pragma mark - 保存

- (void)save
{
	if (!self.target.length) {
		[self alert:@"还没有选择拦截应用" msg:@"请先在第 1 节选择被拦截的目标应用本体。"];
		return;
	}
	if (!self.candidates.count) {
		[self alert:@"还没有选择列表应用" msg:@"请至少选择 1 个候选应用，弹窗里才会显示。"];
		return;
	}

	NSMutableArray<NSDictionary *> *rules =
	    [[SJRuleStore loadRules] mutableCopy];
	NSDictionary *newRule = @{
		@"target": self.target,
		@"candidates": [self.candidates copy],
	};

	BOOL replaced = NO;
	for (NSUInteger i = 0; i < rules.count; i++) {
		NSString *t = rules[i][@"target"];
		if ([t isKindOfClass:[NSString class]] &&
		    [t caseInsensitiveCompare:self.target] == NSOrderedSame) {
			// 同一个目标只保留一条规则
			rules[i] = newRule;
			replaced = YES;
			break;
		}
	}
	if (!replaced) [rules addObject:newRule];

	[SJRuleStore saveRules:rules];
	void (^cb)(void) = self.onSaved;
	[self.navigationController popViewControllerAnimated:YES];
	if (cb) cb();
}

- (void)alert:(NSString *)title msg:(NSString *)msg
{
	UIAlertController *a = [UIAlertController alertControllerWithTitle:title
	                                                           message:msg
	                                                    preferredStyle:UIAlertControllerStyleAlert];
	[a addAction:[UIAlertAction actionWithTitle:@"知道了"
	                                          style:UIAlertActionStyleDefault
	                                        handler:nil]];
	[self presentViewController:a animated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 3; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section
{
	if (section == 0) return 1;
	if (section == 1) return (NSInteger)self.candidates.count + 1;
	return 1;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section
{
	if (section == 0) return @"拦截应用";
	if (section == 1) return @"列表应用";
	return @"";
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section
{
	if (section == 0) {
		return @"设置你需要被拦截唤起的目标应用本体，"
		       @"请选择从 App Store 安装的官方正版应用。"
		       @"注意：已做过注入 / 多开的那个 App 不要设为拦截目标。";
	}
	if (section == 1) {
		return @"拦截后，弹窗里会显示这里选的应用（一般是多开分身）。"
		       @"左滑可移除。";
	}
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip
{
	static NSString *id_ = @"SJRuleEditCell";
	UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:id_];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
		                              reuseIdentifier:id_];
	}

	if (ip.section == 0) {
		if (self.target.length) {
			cell.textLabel.text = [SJAppPicker displayNameForBundleID:self.target];
			cell.detailTextLabel.text = self.target;
			cell.imageView.image = [SJAppPicker iconForBundleID:self.target];
		} else {
			cell.textLabel.text = @"点击选择拦截应用";
			cell.detailTextLabel.text = nil;
			cell.imageView.image = nil;
			cell.textLabel.textColor = [UIColor systemBlueColor];
		}
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		return cell;
	}

	if (ip.section == 1) {
		if (ip.row == (NSInteger)self.candidates.count) {
			cell.textLabel.text = @"＋ 点击选择 / 修改列表应用";
			cell.detailTextLabel.text = nil;
			cell.imageView.image = nil;
			cell.textLabel.textColor = [UIColor systemBlueColor];
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
			return cell;
		}
		NSString *bid = self.candidates[ip.row];
		cell.textLabel.text = [SJAppPicker displayNameForBundleID:bid];
		cell.detailTextLabel.text = bid;
		cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
		cell.imageView.image = [SJAppPicker iconForBundleID:bid];
		cell.accessoryType = UITableViewCellAccessoryNone;
		return cell;
	}

	// 保存
	cell.textLabel.text = @"保存此规则";
	cell.textLabel.textColor = [UIColor systemBlueColor];
	cell.textLabel.textAlignment = NSTextAlignmentCenter;
	cell.imageView.image = nil;
	cell.accessoryType = UITableViewCellAccessoryNone;
	return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip
{
	[tv deselectRowAtIndexPath:ip animated:YES];

	if (ip.section == 0) {
		__weak typeof(self) w = self;
		[SJAppPicker presentFrom:self
		                   title:@"选择拦截应用（应用本体）"
		                     multi:NO
		                preselected:self.target ? [NSSet setWithObject:self.target] : nil
		                   onFinish:^(NSArray<NSString *> *ids) {
			                   if (!ids.count) return;
			                   w.target = ids.firstObject;
			                   // 换目标时清掉旧候选，避免残留不相关分身
			                   [w.candidates removeAllObjects];
			                   [w.tableView reloadData];
		                   }];
		return;
	}

	if (ip.section == 1) {
		if (ip.row == (NSInteger)self.candidates.count) {
			__weak typeof(self) w = self;
			[SJAppPicker presentFrom:self
			                   title:@"选择列表应用（可多选）"
			                     multi:YES
			                preselected:[NSSet setWithArray:self.candidates]
			                   onFinish:^(NSArray<NSString *> *ids) {
				                   NSMutableArray *out = [NSMutableArray array];
				                   for (NSString *b in ids) {
					                   // 目标本体不用重复出现在候选里，弹窗会自动补一条
					                   if ([b isEqualToString:w.target]) continue;
					                   if (![out containsObject:b]) [out addObject:b];
				                   }
				                   w.candidates = out;
				                   [w.tableView reloadData];
			                   }];
		}
		return;
	}

	[self save];
}

#pragma mark - 左滑删除候选

- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)ip
{
	return ip.section == 1 && ip.row < (NSInteger)self.candidates.count;
}

- (void)tableView:(UITableView *)tv
    commitEditingStyle:(UITableViewCellEditingStyle)style
     forRowAtIndexPath:(NSIndexPath *)ip
{
	if (style != UITableViewCellEditingStyleDelete) return;
	if (ip.row >= (NSInteger)self.candidates.count) return;

	[self.candidates removeObjectAtIndex:ip.row];
	[self.tableView reloadData];
}

- (NSString *)tableView:(UITableView *)tv
    titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)ip
{
	return @"移除";
}

@end
