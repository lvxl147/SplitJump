//
//  SJRuleEditorController.m
//
//  单条规则的编辑页（对齐 JumpSelect 的「编辑拦截规则」）：
//    第 1 节  选择拦截应用（单选）—— 被拦截唤起的目标应用本体
//    第 2 节  列表应用显示（多选）—— 弹窗里显示的候选，一般是该应用的各个多开分身
//    第 3 节  本条规则设置 —— 开启直接跳转 / 显示目标拦截应用 / 兼容 Crane 容器
//    第 4 节  保存此规则 / 删除此规则
//
//  踩坑留档：
//   - 不要在类扩展里重新声明头文件里带 nullable 的 onSaved，
//     clang 会报 illegal redeclaration（可空性不一致）。
//   - 本子工程默认 -Werror：别留未使用变量、别用废弃 API。
//

#import "SJRuleEditorController.h"
#import "SJAppPicker.h"
#import "SJRuleStore.h"

// 本条规则开关的 tag -> 字段名
static NSString * const kRuleFlagKeys[] = {
	@"__none__",       // tag 0 占位
	@"directJump",     // tag 1
	@"showTarget",     // tag 2
	@"enableCrane",    // tag 3
};

@interface SJRuleEditorController ()
@property (nonatomic, copy) NSString *target;
@property (nonatomic, strong) NSMutableArray<NSString *> *candidates;
@property (nonatomic, assign) BOOL flagDirectJump;
@property (nonatomic, assign) BOOL flagShowTarget;
@property (nonatomic, assign) BOOL flagEnableCrane;
@property (nonatomic, assign) BOOL isEditingExisting;
@end

@implementation SJRuleEditorController

- (instancetype)initWithRule:(NSDictionary *)rule
{
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self) {
		self.isEditingExisting = (rule != nil);
		self.title = self.isEditingExisting ? @"编辑拦截规则" : @"添加拦截规则";

		self.target = nil;
		if ([rule[@"target"] isKindOfClass:[NSString class]]) {
			self.target = rule[@"target"];
		}

		self.candidates = [NSMutableArray array];
		if ([rule[@"candidates"] isKindOfClass:[NSArray class]]) {
			for (id c in rule[@"candidates"]) {
				NSString *s = c;
				if ([s isKindOfClass:[NSString class]] && s.length > 0) [self.candidates addObject:s];
			}
		}

		// 三个开关是「每条规则各自一份」，新建时给合理默认值
		if (rule) {
			self.flagDirectJump  = [rule[@"directJump"]  boolValue];
			self.flagShowTarget  = rule[@"showTarget"] == nil ? YES : [rule[@"showTarget"] boolValue];
			self.flagEnableCrane = rule[@"enableCrane"] == nil ? YES : [rule[@"enableCrane"] boolValue];
		} else {
			self.flagDirectJump  = NO;
			self.flagShowTarget  = YES;
			self.flagEnableCrane = YES;
		}

		self.navigationItem.rightBarButtonItem =
		    [[UIBarButtonItem alloc] initWithTitle:@"保存"
		                                     style:UIBarButtonItemStyleDone
		                                    target:self
		                                    action:@selector(save)];
		if (self.isEditingExisting) {
			self.navigationItem.leftBarButtonItem =
			    [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
			                                              target:self
			                                              action:@selector(cancelTapped)];
		}
	}
	return self;
}

- (void)viewDidLoad
{
	[super viewDidLoad];
	self.tableView.rowHeight = 52;
}

#pragma mark - 开关

- (void)flagChanged:(UISwitch *)sw
{
	switch (sw.tag) {
		case 1: self.flagDirectJump  = sw.on; break;
		case 2: self.flagShowTarget  = sw.on; break;
		case 3: self.flagEnableCrane = sw.on; break;
		default: break;
	}
}

#pragma mark - 动作

- (void)cancelTapped
{
	[self.navigationController popViewControllerAnimated:YES];
}

- (void)save
{
	if (self.target.length == 0) {
		[self alert:@"还没有选择拦截应用" msg:@"请先在第 1 节选择被拦截的目标应用本体。"];
		return;
	}
	if (self.candidates.count == 0) {
		[self alert:@"还没有选择列表应用" msg:@"请至少选择 1 个候选应用，弹窗里才会显示。"];
		return;
	}

	NSMutableArray<NSDictionary *> *rules = [[SJRuleStore loadRules] mutableCopy];
	NSDictionary *newRule = @{
		@"target": self.target,
		@"candidates": [self.candidates copy],
		@"directJump":  @(self.flagDirectJump),
		@"showTarget":  @(self.flagShowTarget),
		@"enableCrane": @(self.flagEnableCrane),
	};

	BOOL replaced = NO;
	for (NSUInteger i = 0; i < rules.count; i++) {
		NSString *t = rules[i][@"target"];
		if ([t isKindOfClass:[NSString class]] &&
		    [t caseInsensitiveCompare:self.target] == NSOrderedSame) {
			// 同一个目标只保留一条规则（与 JumpSelect 行为一致）
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

- (void)deleteRule
{
	UIAlertController *alert =
	    [UIAlertController alertControllerWithTitle:@"删除此规则"
	                                        message:@"确定删除这条拦截规则？"
	                                 preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"取消"
	                                          style:UIAlertActionStyleCancel
	                                        handler:nil]];
	__weak typeof(self) w = self;
	[alert addAction:[UIAlertAction actionWithTitle:@"删除"
	                                          style:UIAlertActionStyleDestructive
	                                        handler:^(UIAlertAction *a) {
		                                        NSMutableArray<NSDictionary *> *rules =
		                                            [[SJRuleStore loadRules] mutableCopy];
		                                        for (NSUInteger i = 0; i < rules.count; i++) {
			                                        NSString *t = rules[i][@"target"];
			                                        if ([t isKindOfClass:[NSString class]] &&
			                                            [t caseInsensitiveCompare:w.target] == NSOrderedSame) {
				                                        [rules removeObjectAtIndex:i];
				                                        break;
			                                        }
		                                        }
		                                        [SJRuleStore saveRules:rules];
		                                        void (^cb)(void) = w.onSaved;
		                                        [w.navigationController popViewControllerAnimated:YES];
		                                        if (cb) cb();
	                                        }]];
	[self presentViewController:alert animated:YES completion:nil];
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

#pragma mark - Table 数据

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 4; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section
{
	switch (section) {
		case 0: return 1;                                     // 拦截应用
		case 1: return (NSInteger)self.candidates.count + 1;  // 列表应用 + 添加
		case 2: return 3;                                     // 三个开关
		case 3: return self.isEditingExisting ? 2 : 1;        // 保存 / 删除
		default: return 0;
	}
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section
{
	switch (section) {
		case 0: return @"拦截应用";
		case 1: return @"列表应用显示";
		case 2: return @"本条规则设置";
		default: return nil;
	}
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section
{
	if (section == 0) {
		return @"设置需要被拦截唤起的目标应用本体，"
		       @"请选择从 AppStore 安装的官方正版应用；已做过注入 / 多开的 App 不要设为拦截目标。";
	}
	if (section == 1) {
		return @"拦截后，将在弹窗中显示供你选择的跳转列表。左滑可移除。";
	}
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip
{
	// 第 2 节的三个开关行各自独立复用 id，避免复用串状态（见下方说明）
	NSString *rid = (ip.section == 2)
	    ? [NSString stringWithFormat:@"SJFlag-%ld", (long)ip.row]
	    : [NSString stringWithFormat:@"SJRuleEdit%ld", (long)ip.section];
	UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:rid];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
		                              reuseIdentifier:rid];
	}
	cell.textLabel.textAlignment = NSTextAlignmentLeft;
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.imageView.image = nil;
	cell.detailTextLabel.text = nil;
	cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];

	if (ip.section == 0) {
		if (self.target.length > 0) {
			cell.textLabel.text = [SJAppPicker displayNameForBundleID:self.target];
			cell.detailTextLabel.text = self.target;
			cell.imageView.image = [SJAppPicker iconForBundleID:self.target];
		} else {
			cell.textLabel.text = @"点击选择拦截应用";
			cell.textLabel.textColor = [UIColor systemBlueColor];
		}
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		return cell;
	}

	if (ip.section == 1) {
		if (ip.row == (NSInteger)self.candidates.count) {
			cell.textLabel.text = @"点击选择列表应用";
			cell.textLabel.textColor = [UIColor systemBlueColor];
		} else {
			NSString *bid = self.candidates[ip.row];
			cell.textLabel.text = [SJAppPicker displayNameForBundleID:bid];
			cell.detailTextLabel.text = bid;
			cell.imageView.image = [SJAppPicker iconForBundleID:bid];
		}
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		return cell;
	}

	if (ip.section == 2) {
		NSString *title = nil;
		BOOL value = NO;
		if (ip.row == 0) { title = @"开启直接跳转";     value = self.flagDirectJump; }
		if (ip.row == 1) { title = @"显示目标拦截应用"; value = self.flagShowTarget; }
		if (ip.row == 2) { title = @"兼容 Crane 容器";  value = self.flagEnableCrane; }

		// 关键修复（v1.4.0「开关关不了」的根因）：
		// 三个开关行共用一个复用 id 时，复用会让别行的开关绑到本行，
		// 并且每次 dequeue 都回写 sw.on，把用户刚点下的状态覆盖掉。
		// 现在每行用【独立复用 id】，且 sw.on 只在创建 cell 时设置一次。
		UISwitch *sw = (UISwitch *)cell.accessoryView;
		if (!sw) {
			sw = [[UISwitch alloc] initWithFrame:CGRectZero];
			sw.tag = ip.row + 1;
			sw.on = value;
			[sw addTarget:self action:@selector(flagChanged:)
			     forControlEvents:UIControlEventValueChanged];
			cell.accessoryView = sw;
		}
		cell.textLabel.text = title;
		cell.imageView.image = nil;
		cell.detailTextLabel.text = nil;
		return cell;
	}

	// 第 4 节：保存 / 删除
	if (ip.row == 0) {
		cell.textLabel.text = @"保存此规则";
		cell.textLabel.textColor = [UIColor systemBlueColor];
		cell.textLabel.textAlignment = NSTextAlignmentCenter;
	} else {
		cell.textLabel.text = @"删除此规则";
		cell.textLabel.textColor = [UIColor systemRedColor];
		cell.textLabel.textAlignment = NSTextAlignmentCenter;
	}
	return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip
{
	[tv deselectRowAtIndexPath:ip animated:YES];

	if (ip.section == 0) {
		__weak typeof(self) w = self;
		[SJAppPicker presentFrom:self
		                   title:@"选择拦截应用"
		                     multi:NO
		        preselected:self.target.length > 0 ? [NSSet setWithObject:self.target] : nil
		                   onFinish:^(NSArray<NSString *> *ids) {
			                   if (ids.count == 0) return;
			                   w.target = ids.firstObject;
			                   // 换目标时清掉旧候选，避免残留不相关分身
			                   [w.candidates removeAllObjects];
			                   [w.tableView reloadData];
		                   }];
		return;
	}

	if (ip.section == 1) {
		if (ip.row != (NSInteger)self.candidates.count) return;
		__weak typeof(self) w = self;
		[SJAppPicker presentFrom:self
		                   title:@"选择列表应用"
		                     multi:YES
		        preselected:[NSSet setWithArray:self.candidates]
		                   onFinish:^(NSArray<NSString *> *ids) {
			                   NSMutableArray *out = [NSMutableArray array];
			                   for (NSString *b in ids) {
				                   // 目标本体不用重复出现在候选里
				                   if ([b isEqualToString:w.target]) continue;
				                   if (![out containsObject:b]) [out addObject:b];
			                   }
			                   w.candidates = out;
			                   [w.tableView reloadData];
		                   }];
		return;
	}

	if (ip.section == 3) {
		if (ip.row == 0) [self save];
		else [self deleteRule];
	}
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

@end
