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

#pragma mark - 日志

static NSString *SJSettingsLogPath(void)
{
	NSString *dir = @"/var/mobile/Library/Logs";
	[[NSFileManager defaultManager] createDirectoryAtPath:dir
	                          withIntermediateDirectories:YES
	                                           attributes:nil
	                                                error:NULL];
	return [dir stringByAppendingPathComponent:@"SplitJump-Settings.log"];
}

+ (void)appendSettingsLog:(NSString *)line
{
	@try {
		NSString *path = SJSettingsLogPath();
		NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
		fmt.dateFormat = @"MM-dd HH:mm:ss.SSS";
		NSString *out = [NSString stringWithFormat:@"%@  %@\n",
		                 [fmt stringFromDate:[NSDate date]], line ?: @""];

		NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
		if (!fh) {
			[out writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
			return;
		}
		[fh seekToEndOfFile];
		[fh writeData:[out dataUsingEncoding:NSUTF8StringEncoding]];
		[fh closeFile];
	} @catch (NSException *e) {
		// 诊断日志失败就放弃，绝不能反过来把「设置」弄崩
	}
}

+ (NSString *)exportLogs
{
	@try {
		NSString *docs = @"/var/mobile/Documents";
		NSString *destDir = [docs stringByAppendingPathComponent:@"SplitJump-Logs"];
		NSFileManager *fm = [NSFileManager defaultManager];
		[fm createDirectoryAtPath:destDir withIntermediateDirectories:YES attributes:nil error:NULL];

		NSArray *sources = @[
			@"/var/mobile/Library/Logs/SplitJump.log",          // SpringBoard 侧（插件本体）
			SJSettingsLogPath(),                               // 设置侧（面板）
		];
		NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
		fmt.dateFormat = @"yyyyMMdd-HHmmss";
		NSString *stamp = [fmt stringFromDate:[NSDate date]];

		NSMutableArray *copied = [NSMutableArray array];
		for (NSString *src in sources) {
			if (![fm fileExistsAtPath:src]) continue;
			NSString *base = [src lastPathComponent];
			NSString *dst = [destDir stringByAppendingPathComponent:
			                 [NSString stringWithFormat:@"%@-%@.log", base, stamp]];
			[fm removeItemAtPath:dst error:NULL];
			if ([fm copyItemAtPath:src toPath:dst error:NULL]) [copied addObject:dst];
		}
		return copied.count
		    ? [NSString stringWithFormat:@"已导出 %lu 个文件到：\n%@",
		       (unsigned long)copied.count, destDir]
		    : @"没有可导出的日志（请先开启「写入调试日志」并复现一次问题）。";
	} @catch (NSException *e) {
		return [NSString stringWithFormat:@"导出失败：%@", e];
	}
}

@end
