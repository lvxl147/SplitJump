//
//  SJAppList.m
//

#import "SJAppList.h"
#import "SJCompat.h"
#import <objc/runtime.h>

@implementation SJAppEntry

- (NSString *)description
{
	return [NSString stringWithFormat:@"<SJAppEntry %@/%@ (%@)>", self.bundleID,
	                                  self.containerID ?: @"-", self.title];
}

@end

#pragma mark -

@implementation SJAppList

#pragma mark LSApplicationWorkspace

+ (id)workspace
{
	static id ws = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		Class c = NSClassFromString(@"LSApplicationWorkspace");
		if (!c) return;
		ws = SJInvokeClass(c, @"defaultWorkspace", @[]);
		if (!ws) ws = SJInvokeClass(c, @"workspace", @[]);
	});
	return ws;
}

+ (id)proxyForBundleID:(NSString *)bundleID
{
	if (!bundleID.length) return nil;
	return SJInvoke([self workspace], @"applicationProxyForIdentifier:", @[ bundleID ]);
}

+ (BOOL)isInstalled:(NSString *)bundleID
{
	id proxy = [self proxyForBundleID:bundleID];
	if (!proxy) return NO;

	// 优先用 isInstalled / installed
	id v = SJInvoke(proxy, @"isInstalled", @[]);
	if ([v isKindOfClass:[NSNumber class]]) return [v boolValue];

	// 退而求其次：能取到 bundleIdentifier 就认为存在
	return SJStr(SJInvoke(proxy, @"bundleIdentifier", @[])).length > 0;
}

+ (NSString *)displayNameForBundleID:(NSString *)bundleID
{
	if (!bundleID.length) return @"";
	id proxy = [self proxyForBundleID:bundleID];
	NSString *name = SJStr(SJGetProperty(proxy, @[ @"localizedShortName", @"localizedName",
	                                               @"itemName", @"bundleIdentifier" ],
	                                     [NSString class]));
	return name.length ? name : bundleID;
}

#pragma mark Crane

+ (id)craneManager
{
	static id mgr = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		Class c = NSClassFromString(@"CraneManager");
		if (!c) return;
		mgr = SJInvokeClass(c, @"sharedManager", @[]);
		if (!mgr) mgr = SJInvokeClass(c, @"sharedInstance", @[]);
	});
	return mgr;
}

+ (BOOL)craneAvailable
{
	return [self craneManager] != nil;
}

+ (NSArray<NSString *> *)containersForBundleID:(NSString *)bundleID
{
	if (!bundleID.length) return @[];
	id manager = [self craneManager];
	if (!manager) return @[];

	id v = SJInvoke(manager, @"containerIdentifiersOfApplicationWithIdentifier:", @[ bundleID ]);
	if (![v isKindOfClass:[NSArray class]]) return @[];
	return v;
}

+ (NSString *)containerDisplayName:(NSString *)containerID forBundleID:(NSString *)bundleID
{
	id manager = [self craneManager];
	if (!manager || !containerID.length) return nil;

	// displayNameForContainerWithIdentifier:ofApplicationWithIdentifier:shouldUseShortVersion:
	id v = SJInvoke(manager,
	                @"displayNameForContainerWithIdentifier:ofApplicationWithIdentifier:"
	                @"shouldUseShortVersion:",
	                @[ containerID, bundleID, @YES ]);
	return SJStr(v);
}

+ (BOOL)activateContainer:(NSString *)containerID forBundleID:(NSString *)bundleID
{
	if (!bundleID.length) return NO;
	id manager = [self craneManager];
	if (!manager) return NO;

	SEL sel = NSSelectorFromString(
	    @"setActiveContainerIdentifier:forApplicationWithIdentifier:");
	if (![manager respondsToSelector:sel]) return NO;

	// containerID 为 nil 表示切回默认容器
	id cid = containerID.length ? containerID : [NSNull null];
	SJInvoke(manager, @"setActiveContainerIdentifier:forApplicationWithIdentifier:",
	         @[ cid, bundleID ]);
	return YES;
}

#pragma mark 组装

+ (NSArray<SJAppEntry *> *)entriesForRule:(SJRule *)rule
{
	NSMutableArray<SJAppEntry *> *out = [NSMutableArray array];
	if (!rule) return out;

	SJSettings *s = [SJSettings shared];
	// 「兼容 Crane 容器」是每条规则各自的设置；未设置时回退全局
	BOOL canExpand = (rule.enableCrane && [self craneAvailable]);

	// 「显示目标拦截应用」：关掉时不把目标本体放进列表（但若候选只有它，仍显示，避免空面板）
	BOOL showBase = rule.showTarget || rule.candidates.count <= 1;

	for (NSString *bid in rule.candidates) {
		if (![self isInstalled:bid]) continue;

		NSString *appName = [self displayNameForBundleID:bid];
		UIImage *icon = SJAppIcon(bid);

		// 1) 应用本体（默认容器）
		BOOL isTarget = [bid isEqualToString:rule.target];
		if (isTarget && !showBase) continue;

		SJAppEntry *base = [[SJAppEntry alloc] init];
		base.bundleID = bid;
		base.containerID = nil;
		base.title = appName;
		base.subtitle = nil;
		base.icon = icon;
		base.installed = YES;
		[out addObject:base];

		// 2) Crane 多开容器
		if (!canExpand) continue;

		NSArray<NSString *> *containers = [self containersForBundleID:bid];
		if (!containers.count) continue;

		if (!s.craneAllContainers) {
			// 只补一个"切换容器"提示项，避免列表过长
			SJAppEntry *e = [[SJAppEntry alloc] init];
			e.bundleID = bid;
			e.containerID = containers.firstObject;
			e.title = [self containerDisplayName:containers.firstObject forBundleID:bid] ?: appName;
			e.subtitle = [NSString stringWithFormat:@"共 %lu 个容器",
			                                        (unsigned long)containers.count];
			e.icon = icon;
			e.installed = YES;
			[out addObject:e];
			continue;
		}

		NSInteger idx = 0;
		for (NSString *cid in containers) {
			idx++;
			SJAppEntry *e = [[SJAppEntry alloc] init];
			e.bundleID = bid;
			e.containerID = cid;
			NSString *cname = [self containerDisplayName:cid forBundleID:bid];
			e.title = cname.length ? cname
			                       : [NSString stringWithFormat:@"%@ (%ld)", appName, (long)idx];
			e.subtitle = [NSString stringWithFormat:@"容器 %@",
			                                        cid.length > 8
			                                            ? [cid substringToIndex:8]
			                                            : cid];
			e.icon = icon;
			e.installed = YES;
			[out addObject:e];
		}
	}

	return out;
}

@end
