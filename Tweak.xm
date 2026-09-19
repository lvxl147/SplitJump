//
//  Tweak.xm — SplitJump
//
//  功能：拦截「跨 App 跳转」（URL / 支付 / 授权 / 快捷指令），先弹出应用选择面板，
//        用户选定后再把请求交回原调用链继续执行；把它交回原链是刻意设计，
//        这样分屏 / 浮窗类插件（例如 Stheno）仍能对这次打开按自己的规则处理，
//        从而达到「先选应用 → 再以浮窗打开」的效果。
//
//  两个拦截点：
//   ① 下游（Logos %hook，加载期安装，稳定可用）
//        -[SBMainWorkspace systemService:handleOpenApplicationRequest:withCompletion:]
//      这里拿到的是一个封装过的 request 对象，改写它需要 KVC 写 bundle 标识。
//
//   ② 上游（substrate，延迟安装，对应偏好「提早拦截」）
//        -[SBMainWorkspace _activateBundleID:requestID:isTrusted:options:source:
//                        originalSource:withResult:]
//      bundleID 是显式参数，直接换参重投即可，不需要改写对象，最可靠；
//      并且它和分屏类插件的拦截点同层，所以刻意「延迟安装」以保证自己位于
//      调用链最外层 —— 只有最外层才既拦得住、又能在重投时把请求交回它们。
//

#import <substrate.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <unistd.h>
#import <signal.h>

#import "SJCompat.h"
#import "SJRules.h"
#import "SJAppList.h"
#import "SJPicker.h"

/// 取消跳转时使用的哨兵包名（系统中不存在，打开会静默失败）
static NSString *const SJSentinelBundleID = @"com.lvxl524.splitjump.void";

#pragma mark - 状态

static BOOL sSJPending = NO;              // 已有请求挂起，等待用户选择
static BOOL sSJRedirecting = NO;          // 正在执行我们自己的重投
static void (^sSJResume)(NSString *bid) = nil;

static void SJResolve(NSString *bid);
static void SJBeginIntercept(SJRule *rule, NSString *source, NSString *url, void (^resume)(NSString *));

#pragma mark - request / options 取值

static NSString *SJTargetBundleIDFromRequest(id request)
{
	if (!request) return nil;

	NSString *v = SJStr(SJGetProperty(request,
	                                  @[ @"bundleIdentifier", @"bundleID",
	                                     @"_bundleIdentifier", @"_bundleID",
	                                     @"targetBundleIdentifier" ],
	                                  [NSString class]));
	if (v.length) return v;

	id dict = SJGetProperty(request, @[ @"dictionary" ], [NSDictionary class]);
	if ([dict isKindOfClass:[NSDictionary class]]) {
		for (NSString *k in @[ @"bundleIdentifier", @"bundleID", @"Target" ]) {
			v = SJStr(dict[k]);
			if (v.length) return v;
		}
		id opts = dict[@"options"];
		if ([opts isKindOfClass:[NSDictionary class]]) {
			v = SJStr(opts[@"bundleIdentifier"]);
			if (v.length) return v;
		}
	}
	return nil;
}

static NSDictionary *SJOptionsFromRequest(id request)
{
	if (!request) return nil;

	id v = SJGetProperty(request, @[ @"options", @"_options", @"launchOptions" ],
	                     [NSDictionary class]);
	if ([v isKindOfClass:[NSDictionary class]]) return v;

	id dict = SJGetProperty(request, @[ @"dictionary" ], [NSDictionary class]);
	if ([dict isKindOfClass:[NSDictionary class]]) {
		id o = dict[@"options"];
		if ([o isKindOfClass:[NSDictionary class]]) return o;
		return dict;
	}
	return nil;
}

static BOOL SJSetTargetBundleID(id request, NSString *bid)
{
	if (!request || !bid.length) return NO;

	static NSArray<NSString *> *keys = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		keys = @[ @"_bundleIdentifier", @"_bundleID", @"bundleIdentifier", @"bundleID",
		          @"targetBundleIdentifier" ];
	});

	for (NSString *k in keys) {
		@try {
			[request setValue:bid forKey:k];
			return YES;
		} @catch (NSException *e) {
			// 该 key 不存在，试下一个
		}
	}

	for (NSString *selName in @[ @"setBundleIdentifier:", @"setBundleID:",
	                             @"setTargetBundleIdentifier:" ]) {
		if (SJObjectResponds(request, selName)) {
			SJInvoke(request, selName, @[ bid ]);
			return YES;
		}
	}
	return NO;
}

#pragma mark - 来源与 URL

static NSString *SJSourceFromOptions(NSDictionary *options)
{
	if (![options isKindOfClass:[NSDictionary class]]) return nil;
	NSString *v = SJStr(options[@"UIApplicationLaunchOptionsSourceApplicationKey"]);
	if (!v.length) v = SJStr(options[@"sourceApplication"]);
	return v;
}

static NSString *SJURLFromOptions(NSDictionary *options)
{
	if (![options isKindOfClass:[NSDictionary class]]) return nil;
	return SJStr(options[@"UIApplicationLaunchOptionsURLKey"]);
}

/// 兜底：SpringBoard 前台应用。桌面点图标时 options 里没有 sourceApplication，
/// 只能靠它得到「com.apple.springboard」从而被放行名单命中。
static NSString *SJFrontmostBundleID(void)
{
	NSMutableArray *candidates = [NSMutableArray array];
	id app = [UIApplication sharedApplication];
	if (app) {
		[candidates addObject:app];
		id delegate = SJInvoke(app, @"delegate", @[]);
		if (delegate) [candidates addObject:delegate];
	}

	for (id obj in candidates) {
		id front = SJInvoke(obj, @"_accessibilityFrontMostApplication", @[]);
		if (!front) continue;

		NSString *bid = SJStr(SJGetProperty(front, @[ @"bundleIdentifier" ], [NSString class]));
		if (bid.length) return bid;

		id proc = SJGetProperty(front, @[ @"clientProcess" ], nil);
		bid = SJStr(SJGetProperty(proc, @[ @"bundleIdentifier" ], [NSString class]));
		if (bid.length) return bid;
	}
	return nil;
}

#pragma mark - 决策

static BOOL SJShouldIntercept(NSString *target, NSDictionary *options,
                              NSString **outSource, NSString **outURL, SJRule **outRule)
{
	SJSettings *s = [SJSettings shared];
	if (!s.enabled || !target.length) return NO;

	NSString *src = SJSourceFromOptions(options);
	if (!src.length) src = SJFrontmostBundleID();
	if (outSource) *outSource = src;

	if ([s sourceAllowed:src]) {
		SJLog(@"pass: source %@ is allowed", src ?: @"(unknown)");
		return NO;
	}

	NSString *url = SJURLFromOptions(options);
	if (outURL) *outURL = url;

	if (s.urlOnly && !url.length) return NO;

	SJRule *rule = [s ruleForTarget:target];
	if (!rule) return NO;

	if (outRule) *outRule = rule;
	return YES;
}

#pragma mark - 挂起 / 恢复

static void SJResolve(NSString *bid)
{
	void (^r)(NSString *) = sSJResume;
	sSJResume = nil;
	sSJPending = NO;
	if (!r) return;

	sSJRedirecting = YES;
	@try {
		r(bid);
	} @catch (NSException *e) {
		SJLog(@"resume threw: %@", e);
	}
	sSJRedirecting = NO;
}

static void SJBeginIntercept(SJRule *rule, NSString *source, NSString *url, void (^resume)(NSString *))
{
	NSArray<SJAppEntry *> *entries = nil;
	@try {
		entries = [SJAppList entriesForRule:rule];
	} @catch (NSException *e) {
		SJLog(@"entriesForRule threw: %@", e);
		entries = @[];
	}

	if (!entries.count) {
		SJLog(@"no installed candidate for %@ -> pass through", rule.target);
		if (resume) {
			sSJRedirecting = YES;
			resume(nil);
			sSJRedirecting = NO;
		}
		return;
	}

	sSJPending = YES;
	sSJResume = [resume copy];

	// 「开启直接跳转」是每条规则各自的设置（对齐 JumpSelect）
	if (rule.directJump) {
		SJAppEntry *first = entries.firstObject;
		SJLog(@"directJump -> %@ / %@", first.bundleID, first.containerID ?: @"(default)");
		[SJAppList activateContainer:first.containerID forBundleID:first.bundleID];
		SJResolve(first.bundleID);
		return;
	}

	NSString *srcName = [SJAppList displayNameForBundleID:source];
	dispatch_async(dispatch_get_main_queue(), ^{
		[SJPickerViewController presentWithSourceName:srcName
		                                    urlString:url
		                                      entries:entries
		                                       cancel:^{
			                                       SJLog(@"user cancelled -> sentinel");
			                                       SJResolve(SJSentinelBundleID);
		                                       }
		                                       select:^(SJAppEntry *entry) {
			                                       SJLog(@"user picked %@ / %@",
			                                             entry.bundleID,
			                                             entry.containerID ?: @"(default)");
			                                       [SJAppList activateContainer:entry.containerID
			                                                     forBundleID:entry.bundleID];
			                                       SJResolve(entry.bundleID);
		                                       }];
	});
}

#pragma mark - ① 下游拦截点（加载期安装）

%hook SBMainWorkspace

- (void)systemService:(id)service
    handleOpenApplicationRequest:(id)request
               withCompletion:(id)completion
{
	if (sSJRedirecting || sSJPending || ![SJSettings shared].enabled) {
		%orig;
		return;
	}

	NSString *target = nil;
	NSDictionary *options = nil;
	NSString *src = nil, *url = nil;
	SJRule *rule = nil;
	BOOL should = NO;

	// 决策阶段全部兜底：任何异常都直接放行，绝不能把 SpringBoard 带崩
	@try {
		target = SJTargetBundleIDFromRequest(request);
		options = SJOptionsFromRequest(request);
		should = SJShouldIntercept(target, options, &src, &url, &rule);
	} @catch (NSException *e) {
		SJLog(@"DOWNSTREAM decide threw: %@", e);
		should = NO;
	}

	if (!should) {
		%orig;
		return;
	}

	SJLog(@"DOWNSTREAM hit: target=%@ source=%@ url=%@", target, src, url);

	SJBeginIntercept(rule, src, url, ^(NSString *bid) {
		NSString *newBID = bid.length ? bid : target;
		if (![newBID isEqualToString:target]) {
			if (!SJSetTargetBundleID(request, newBID)) {
				SJLog(@"cannot rewrite request bundle id -> drop");
				return;
			}
		}
		SJLog(@"DOWNSTREAM resume -> %@", newBID);
		%orig(service, request, completion);
	});
}

%end

#pragma mark - ② 上游拦截点（延迟安装，换取「位于最外层」）

static NSString *const kSJActivateSelector =
    @"_activateBundleID:requestID:isTrusted:options:source:originalSource:withResult:";

typedef void (*SJActivateFn)(id, SEL, id, id, BOOL, id, id, id, id);
static SJActivateFn gSJOrigActivate = NULL;

static void SJActivateReplacement(id self, SEL _cmd, id bundleID, id requestID, BOOL isTrusted,
                                  id options, id source, id originalSource, id result)
{
	SJActivateFn orig = gSJOrigActivate;
	if (!orig) return;

	SJSettings *s = [SJSettings shared];
	if (!s.enabled || !s.earlyHook || sSJRedirecting || sSJPending) {
		orig(self, _cmd, bundleID, requestID, isTrusted, options, source, originalSource, result);
		return;
	}

	NSString *target = SJStr(bundleID);
	NSDictionary *opts = [options isKindOfClass:[NSDictionary class]] ? options : nil;
	NSString *src = nil, *url = nil;
	SJRule *rule = nil;
	BOOL should = NO;

	// 决策阶段全部兜底：任何异常都直接放行，绝不能把 SpringBoard 带崩
	@try {
		should = SJShouldIntercept(target, opts, &src, &url, &rule);
	} @catch (NSException *e) {
		SJLog(@"UPSTREAM decide threw: %@", e);
		should = NO;
	}

	if (!should) {
		orig(self, _cmd, bundleID, requestID, isTrusted, options, source, originalSource, result);
		return;
	}

	SJLog(@"UPSTREAM hit: target=%@ source=%@ url=%@", target, src, url);

	SJBeginIntercept(rule, src, url, ^(NSString *bid) {
		NSString *newBID = bid.length ? bid : target;
		SJLog(@"UPSTREAM resume -> %@", newBID);
		// 换参重投：这一跳会进入链上其它插件（例如分屏/浮窗插件）的实现
		orig(self, _cmd, newBID, requestID, isTrusted, options, source, originalSource, result);
	});
}

static BOOL SJInstallEarlyHook(void)
{
	Class cls = objc_getClass("SBMainWorkspace");
	if (!cls) {
		SJLog(@"early hook: SBMainWorkspace not found");
		return NO;
	}

	SEL sel = NSSelectorFromString(kSJActivateSelector);
	Method m = sel ? class_getInstanceMethod(cls, sel) : NULL;
	if (!m) {
		SJLog(@"early hook: %@ not present on this iOS -> skipped", kSJActivateSelector);
		return NO;
	}

	// 只安装一次：重复 MSHookMessageEx 会让「自己 → 自己」形成递归
	if (gSJOrigActivate != NULL) return YES;

	MSHookMessageEx(cls, sel, (IMP)SJActivateReplacement, (IMP *)&gSJOrigActivate);

	Method after = class_getInstanceMethod(cls, sel);
	IMP now = after ? method_getImplementation(after) : NULL;
	SJLog(@"early hook installed: outermost=%@ encoding=%s",
	      (now == (IMP)SJActivateReplacement) ? @"YES" : @"NO",
	      (after && method_getTypeEncoding(after)) ? method_getTypeEncoding(after) : "(null)");
	return YES;
}

#pragma mark - 偏好重载

static void SJReloadPrefs(void)
{
	[[SJSettings shared] reload];

	NSDictionary *d = [[NSUserDefaults standardUserDefaults]
	    persistentDomainForName:SJSettingsDomain];
	id dbg = d[@"DebugLog"];
	BOOL debugOn = [dbg isKindOfClass:[NSNumber class]] ? [dbg boolValue] : NO;
	SJSetDebugEnabled(debugOn);

	SJSettings *s = [SJSettings shared];
	SJLog(@"prefs reloaded: enabled=%d earlyHook=%d mode=%ld urlOnly=%d rules=%lu",
	      (int)s.enabled, (int)s.earlyHook, (long)s.mode, (int)s.urlOnly,
	      (unsigned long)s.rules.count);
}

static void SJPrefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name,
                           const void *object, CFDictionaryRef userInfo)
{
	SJReloadPrefs();
}

// 设置面板里的「注销 SpringBoard」按钮：面板进程没有权限杀别的进程，
// 所以只发通知，由这里（SpringBoard 自己）结束自己，再由系统拉起来。
static void SJRespringRequested(CFNotificationCenterRef center, void *observer,
                                CFStringRef name, const void *object,
                                CFDictionaryRef userInfo)
{
	SJLog(@"respring requested from Settings");
	kill(getpid(), SIGKILL);
}

#pragma mark - 入口

%ctor {
	SJReloadPrefs();

	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
	                                (CFNotificationCallback)SJPrefsChanged,
	                                CFSTR("com.lvxl524.splitjump/ReloadPrefs"), NULL,
	                                CFNotificationSuspensionBehaviorDeliverImmediately);

	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
	                                (CFNotificationCallback)SJRespringRequested,
	                                CFSTR("com.lvxl524.splitjump/Respring"), NULL,
	                                CFNotificationSuspensionBehaviorDeliverImmediately);

	// 延迟安装上游钩子：等其它插件（含分屏/浮窗类）都装完再装，
	// 这样自己的实现位于调用链最外层 —— 既拦得住，重投时又能交回给它们。
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)),
	               dispatch_get_main_queue(), ^{
		               SJInstallEarlyHook();
	               });
}
