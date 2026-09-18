//
//  SJRules.m
//

#import "SJRules.h"

NSString *const SJSettingsDomain = @"com.lvxl524.splitjump";
NSString *const SJReloadNotify = @"com.lvxl524.splitjump/ReloadPrefs";

// 默认放行：SpringBoard 自己发起的打开（桌面点图标）不该被拦
static NSString *const kDefaultSourceBlacklist = @"com.apple.springboard";

@implementation SJRule
- (NSString *)description
{
	return [NSString stringWithFormat:@"<SJRule %@ -> %@>", self.target,
	                                  [self.candidates componentsJoinedByString:@","]];
}
@end

@interface SJSettings ()
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) NSInteger mode;
@property (nonatomic, assign) BOOL urlOnly;
@property (nonatomic, assign) BOOL showSourceApp;
@property (nonatomic, assign) BOOL enableCrane;
@property (nonatomic, assign) BOOL craneAllContainers;
@property (nonatomic, assign) BOOL earlyHook;
@property (nonatomic, copy) NSArray<NSString *> *sourceBlacklist;
@property (nonatomic, copy) NSArray<SJRule *> *rules;
@end

@implementation SJSettings

+ (instancetype)shared
{
	static SJSettings *inst = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		inst = [[SJSettings alloc] init];
		[inst reload];
	});
	return inst;
}

- (NSDictionary *)domain
{
	NSDictionary *d = [[NSUserDefaults standardUserDefaults]
	    persistentDomainForName:SJSettingsDomain];
	return [d isKindOfClass:[NSDictionary class]] ? d : @{};
}

static BOOL SJBoolFrom(NSDictionary *d, NSString *key, BOOL def)
{
	id v = d[key];
	if ([v isKindOfClass:[NSNumber class]]) return [v boolValue];
	if ([v isKindOfClass:[NSString class]]) return [v boolValue];
	return def;
}

static NSInteger SJIntFrom(NSDictionary *d, NSString *key, NSInteger def)
{
	id v = d[key];
	if ([v isKindOfClass:[NSNumber class]]) return [v integerValue];
	if ([v isKindOfClass:[NSString class]]) return [v integerValue];
	return def;
}

static NSString *SJStrFrom(NSDictionary *d, NSString *key, NSString *def)
{
	id v = d[key];
	if ([v isKindOfClass:[NSString class]]) return v;
	return def ?: @"";
}

- (void)reload
{
	NSDictionary *d = [self domain];

	// 注意：偏好域可能整片不存在，所以每项都带代码级默认值
	self.enabled = SJBoolFrom(d, @"Enabled", YES);
	self.mode = SJIntFrom(d, @"Mode", 0);
	self.urlOnly = SJBoolFrom(d, @"URLOnly", NO);
	self.showSourceApp = SJBoolFrom(d, @"ShowSourceApp", YES);
	self.enableCrane = SJBoolFrom(d, @"EnableCrane", YES);
	self.craneAllContainers = SJBoolFrom(d, @"CraneAllContainers", YES);
	self.earlyHook = SJBoolFrom(d, @"EarlyHook", NO);

	self.sourceBlacklist = [self parseBlacklistValue:d[@"SourceBlacklist"]];

	// 优先用结构化规则（设置面板点选应用生成）；
	// 没有时退回 v1.0.x 的文本规则，老用户配置不丢。
	NSArray<SJRule *> *structured = [self rulesFromArray:d[@"RulesArray"]];
	self.rules = structured ?: [self parseRules:SJStrFrom(d, @"Rules", @"")];
}

#pragma mark - 解析

/// 放行黑名单：v1.1.0 起是字符串数组，v1.0.x 是逗号分隔字符串
- (NSArray<NSString *> *)parseBlacklistValue:(id)v
{
	if ([v isKindOfClass:[NSArray class]]) {
		NSMutableArray<NSString *> *out = [NSMutableArray array];
		for (id item in v) {
			if ([item isKindOfClass:[NSString class]] && item.length) [out addObject:item];
		}
		return out;
	}
	if ([v isKindOfClass:[NSString class]]) return [self parseList:v];
	return [self parseList:kDefaultSourceBlacklist];
}

/// 设置面板点选生成的结构化规则：[ { target, candidates: [...] }, … ]
- (nullable NSArray<SJRule *> *)rulesFromArray:(id)v
{
	if (![v isKindOfClass:[NSArray class]]) return nil;

	NSMutableArray<SJRule *> *out = [NSMutableArray array];
	for (id item in v) {
		if (![item isKindOfClass:[NSDictionary class]]) continue;

		NSString *target = item[@"target"];
		if (![target isKindOfClass:[NSString class]] || !target.length) continue;

		NSArray *raw = item[@"candidates"];
		if (![raw isKindOfClass:[NSArray class]]) raw = @[ target ];

		NSMutableArray<NSString *> *cands = [NSMutableArray array];
		for (id c in raw) {
			if ([c isKindOfClass:[NSString class]] && c.length) [cands addObject:c];
		}
		if (!cands.count) [cands addObject:target];
		else if (![cands containsObject:target]) [cands insertObject:target atIndex:0];

		SJRule *r = [[SJRule alloc] init];
		r.target = target;
		r.candidates = cands;
		r.sourceLine = [NSString stringWithFormat:@"%@ → %@", target,
		                        [cands componentsJoinedByString:@","]];
		[out addObject:r];
	}
	return out.count ? out : nil;
}

- (NSArray<NSString *> *)parseList:(NSString *)raw
{
	NSMutableArray *out = [NSMutableArray array];
	for (NSString *piece in [raw componentsSeparatedByString:@","]) {
		NSString *s = [piece stringByTrimmingCharactersInSet:
		                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (s.length && ![out containsObject:s]) [out addObject:s];
	}
	return out;
}

- (NSArray<SJRule *> *)parseRules:(NSString *)raw
{
	NSMutableArray<SJRule *> *out = [NSMutableArray array];
	if (!raw.length) return out;

	for (NSString *lineRaw in [raw componentsSeparatedByCharactersInSet:
	                                     [NSCharacterSet newlineCharacterSet]]) {
		NSString *line = [lineRaw stringByTrimmingCharactersInSet:
		                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (!line.length || [line hasPrefix:@"#"]) continue;

		// 分隔符兼容 = 与 ->
		NSRange sep = [line rangeOfString:@"->"];
		if (sep.location == NSNotFound) sep = [line rangeOfString:@"="];
		if (sep.location == NSNotFound) continue;

		NSString *lhs = [line substringToIndex:sep.location];
		NSString *rhs = [line substringFromIndex:sep.location + sep.length];

		NSString *target = [lhs stringByTrimmingCharactersInSet:
		                            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (!target.length) continue;

		NSMutableArray *cands = [[self parseList:rhs] mutableCopy];
		if (!cands.count) cands = [@[ target ] mutableCopy];
		else if (![cands containsObject:target]) [cands insertObject:target atIndex:0];

		SJRule *r = [[SJRule alloc] init];
		r.target = target;
		r.candidates = cands;
		r.sourceLine = line;
		[out addObject:r];
	}
	return out;
}

#pragma mark - 查询

- (SJRule *)ruleForTarget:(NSString *)bundleID
{
	if (!bundleID.length) return nil;
	for (SJRule *r in self.rules) {
		if ([r.target isEqualToString:bundleID]) return r;
	}
	// 兼容大小写差异
	for (SJRule *r in self.rules) {
		if ([r.target caseInsensitiveCompare:bundleID] == NSOrderedSame) return r;
	}
	return nil;
}

- (BOOL)sourceAllowed:(NSString *)sourceBundleID
{
	if (!sourceBundleID.length) return NO;
	for (NSString *s in self.sourceBlacklist) {
		if ([s caseInsensitiveCompare:sourceBundleID] == NSOrderedSame) return YES;
	}
	return NO;
}

@end
