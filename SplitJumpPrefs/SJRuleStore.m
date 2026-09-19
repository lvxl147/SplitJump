//
//  SJRuleStore.m
//

#import "SJRuleStore.h"

@implementation SJRuleStore

+ (NSMutableDictionary *)mutableDomain
{
	NSDictionary *d = [[NSUserDefaults standardUserDefaults]
	    persistentDomainForName:SJ_DOMAIN];
	NSMutableDictionary *m = [d mutableCopy] ?: [NSMutableDictionary dictionary];
	return m;
}

+ (void)commitDomain:(NSMutableDictionary *)domain
{
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	[d setPersistentDomain:domain forName:SJ_DOMAIN];
	[d synchronize];
	[self notify];
}

+ (NSArray<NSDictionary *> *)loadRules
{
	NSDictionary *d = [[NSUserDefaults standardUserDefaults]
	    persistentDomainForName:SJ_DOMAIN];
	id v = d[@"RulesArray"];
	if (![v isKindOfClass:[NSArray class]]) return @[];

	NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
	for (id item in v) {
		if (![item isKindOfClass:[NSDictionary class]]) continue;
		NSString *target = item[@"target"];
		NSArray *cands = item[@"candidates"];
		if (![target isKindOfClass:[NSString class]] || !target.length) continue;
		if (![cands isKindOfClass:[NSArray class]]) cands = @[ target ];

		NSMutableArray *clean = [NSMutableArray array];
		for (id c in cands) {
			NSString *s = c;
			if ([s isKindOfClass:[NSString class]] && s.length > 0) [clean addObject:s];
		}
		if (!clean.count) [clean addObject:target];

		[out addObject:@{ @"target": target, @"candidates": clean }];
	}
	return out;
}

+ (void)saveRules:(NSArray<NSDictionary *> *)rules
{
	NSMutableDictionary *d = [self mutableDomain];
	if (rules.count) d[@"RulesArray"] = rules;
	else [d removeObjectForKey:@"RulesArray"];

	// 兼容 v1.0.x 的文本规则：结构化规则出现后不再使用
	[d removeObjectForKey:@"Rules"];

	[self commitDomain:d];
}

+ (NSArray<NSString *> *)loadBlacklist
{
	NSDictionary *d = [[NSUserDefaults standardUserDefaults]
	    persistentDomainForName:SJ_DOMAIN];
	id v = d[@"SourceBlacklist"];

	// 兼容 v1.0.x：可能是逗号分隔的字符串
	if ([v isKindOfClass:[NSString class]]) {
		return [[v componentsSeparatedByString:@","]
		    filteredArrayUsingPredicate:
		        [NSPredicate predicateWithBlock:^BOOL(id c, NSDictionary *b) {
			        NSString *s = (NSString *)c;
			        return [s isKindOfClass:[NSString class]] && s.length > 0;
		        }]];
	}
	if (![v isKindOfClass:[NSArray class]]) return @[ @"com.apple.springboard" ];

	NSMutableArray<NSString *> *out = [NSMutableArray array];
	for (id item in v) {
		NSString *s = item;
		if ([s isKindOfClass:[NSString class]] && s.length > 0) [out addObject:s];
	}
	return out;
}

+ (void)saveBlacklist:(NSArray<NSString *> *)list
{
	NSMutableDictionary *d = [self mutableDomain];
	if (list.count) d[@"SourceBlacklist"] = list;
	else d[@"SourceBlacklist"] = @[];
	[self commitDomain:d];
}

+ (void)notify
{
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
	                                     CFSTR(SJ_RELOAD_NOTIFY), NULL, NULL, YES);
}

#pragma mark - 通用开关

+ (BOOL)boolForKey:(NSString *)key defaultValue:(BOOL)def
{
	NSDictionary *d = [[NSUserDefaults standardUserDefaults]
	    persistentDomainForName:SJ_DOMAIN];
	id v = d[key];
	if ([v isKindOfClass:[NSNumber class]]) return [v boolValue];
	if ([v isKindOfClass:[NSString class]]) return [v boolValue];
	return def;
}

+ (void)setBool:(BOOL)value forKey:(NSString *)key
{
	NSMutableDictionary *d = [self mutableDomain];
	d[key] = @(value);
	[self commitDomain:d];
}

+ (void)clearRules
{
	NSMutableDictionary *d = [self mutableDomain];
	[d removeObjectForKey:@"RulesArray"];
	[d removeObjectForKey:@"Rules"]; // 兼容 v1.0.x 的文本规则
	[self commitDomain:d];
}

+ (void)requestRespring
{
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
	                                     CFSTR("com.lvxl524.splitjump/Respring"),
	                                     NULL, NULL, YES);
}

@end
