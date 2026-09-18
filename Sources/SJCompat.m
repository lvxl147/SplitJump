//
//  SJCompat.m
//

#import "SJCompat.h"
#import <objc/runtime.h>

#pragma mark - 基础探测

BOOL SJObjectResponds(id obj, NSString *selName)
{
	if (!obj || !selName.length) return NO;
	SEL sel = NSSelectorFromString(selName);
	return sel && [obj respondsToSelector:sel];
}

BOOL SJHasInstanceMethod(Class cls, NSString *selName)
{
	if (!cls || !selName.length) return NO;
	return class_getInstanceMethod(cls, NSSelectorFromString(selName)) != NULL;
}

BOOL SJHasClassMethod(Class cls, NSString *selName)
{
	if (!cls || !selName.length) return NO;
	return class_getClassMethod(cls, NSSelectorFromString(selName)) != NULL;
}

#pragma mark - NSInvocation 调用

static id SJInvokeOn(id target, NSString *selName, NSArray *args, BOOL isClass)
{
	if (!target || !selName.length) return nil;
	SEL sel = NSSelectorFromString(selName);
	if (!sel) return nil;

	// 类方法用 +respondsToSelector:，实例方法用 -respondsToSelector:
	BOOL responds = isClass ? [(id)target respondsToSelector:sel] : [target respondsToSelector:sel];
	if (!responds) return nil;

	NSMethodSignature *sig = [target methodSignatureForSelector:sel];
	if (!sig) return nil;

	NSUInteger want = args ? args.count : 0;
	if (sig.numberOfArguments != want + 2) {
		// 参数个数与 selector 冒号数不匹配 —— 说明探测到了同名但签名不同的方法，放弃
		return nil;
	}

	NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
	[inv setTarget:target];
	[inv setSelector:sel];

	for (NSUInteger i = 0; i < want; i++) {
		id a = args[i];
		NSUInteger idx = i + 2;
		const char *t = [sig getArgumentTypeAtIndex:idx];
		switch (t[0]) {
			case '@': {
				__unsafe_unretained id v = ([a isKindOfClass:[NSNull class]]) ? nil : a;
				[inv setArgument:&v atIndex:idx];
				break;
			}
			case 'c':
			case 'B': {
				BOOL v = [a boolValue];
				[inv setArgument:&v atIndex:idx];
				break;
			}
			case 'i': {
				int v = [a intValue];
				[inv setArgument:&v atIndex:idx];
				break;
			}
			case 'q': {
				long long v = [a longLongValue];
				[inv setArgument:&v atIndex:idx];
				break;
			}
			case 'Q': {
				unsigned long long v = [a unsignedLongLongValue];
				[inv setArgument:&v atIndex:idx];
				break;
			}
			case 'd': {
				double v = [a doubleValue];
				[inv setArgument:&v atIndex:idx];
				break;
			}
			default: {
				__unsafe_unretained id v = a;
				[inv setArgument:&v atIndex:idx];
				break;
			}
		}
	}

	@try {
		[inv invoke];
	} @catch (NSException *e) {
		return nil;
	}

	const char *rt = sig.methodReturnType;
	if (!rt || rt[0] == 'v') return nil;

	switch (rt[0]) {
		case '@': {
			__unsafe_unretained id r = nil;
			[inv getReturnValue:&r];
			return r;
		}
		case 'c':
		case 'B': {
			BOOL r = NO;
			[inv getReturnValue:&r];
			return @(r);
		}
		case 'i': {
			int r = 0;
			[inv getReturnValue:&r];
			return @(r);
		}
		case 'q': {
			long long r = 0;
			[inv getReturnValue:&r];
			return @(r);
		}
		case 'Q': {
			unsigned long long r = 0;
			[inv getReturnValue:&r];
			return @(r);
		}
		case 'd': {
			double r = 0;
			[inv getReturnValue:&r];
			return @(r);
		}
		default:
			return nil;
	}
}

id SJInvoke(id target, NSString *selName, NSArray *args)
{
	return SJInvokeOn(target, selName, args, NO);
}

id SJInvokeClass(Class cls, NSString *selName, NSArray *args)
{
	if (!cls) return nil;
	return SJInvokeOn((id)cls, selName, args, YES);
}

#pragma mark - 取值助手

NSString *SJStr(id v)
{
	if ([v isKindOfClass:[NSString class]]) return v;
	if ([v isKindOfClass:[NSURL class]]) return [(NSURL *)v absoluteString];
	if ([v isKindOfClass:[NSNumber class]]) return [v stringValue];
	return nil;
}

id SJGetProperty(id obj, NSArray<NSString *> *candidateKeys, Class expectClass)
{
	if (!obj) return nil;
	for (NSString *key in candidateKeys) {
		// 1) 无参取值方法
		id v = SJInvoke(obj, key, @[]);
		if (v && (!expectClass || [v isKindOfClass:expectClass])) return v;

		// 2) KVC（含私有 ivar，如 _bundleIdentifier）
		@try {
			v = [obj valueForKey:key];
		} @catch (NSException *e) {
			v = nil;
		}
		if (v && (!expectClass || [v isKindOfClass:expectClass])) return v;
	}
	return nil;
}

UIImage *SJAppIcon(NSString *bundleID)
{
	if (!bundleID.length) return nil;

	Class UIImageCls = [UIImage class];
	SEL sel = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
	NSMethodSignature *sig = [UIImageCls methodSignatureForSelector:sel]; // 类方法签名
	if (!sig || sig.numberOfArguments < 5) return nil;

	NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
	[inv setTarget:UIImageCls];
	[inv setSelector:sel];

	__unsafe_unretained NSString *bid = bundleID;
	int format = 0; // 0 = 主屏尺寸图标
	double scale = (double)[UIScreen mainScreen].scale;
	if (scale <= 0) scale = 3.0;

	[inv setArgument:&bid atIndex:2];
	[inv setArgument:&format atIndex:3];
	[inv setArgument:&scale atIndex:4];

	@try {
		[inv invoke];
	} @catch (NSException *e) {
		return nil;
	}

	__unsafe_unretained UIImage *img = nil;
	[inv getReturnValue:&img];
	return img;
}

#pragma mark - 调试日志

static BOOL sSJDebugEnabled = NO;

/// 由主工程在每次偏好重载时调用，使开关立即生效（无需注销）
void SJSetDebugEnabled(BOOL on)
{
	sSJDebugEnabled = on;
}

static BOOL SJDebugEnabled(void)
{
	return sSJDebugEnabled;
}

void SJLog(NSString *format, ...)
{
	va_list ap;
	va_start(ap, format);
	NSString *msg = [[NSString alloc] initWithFormat:format arguments:ap];
	va_end(ap);

	NSLog(@"[SplitJump] %@", msg);
	if (!SJDebugEnabled()) return;

	static NSString *logPath = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSString *dir = @"/var/mobile/Library/Logs";
		[[NSFileManager defaultManager] createDirectoryAtPath:dir
		                          withIntermediateDirectories:YES
		                                           attributes:nil
		                                                error:NULL];
		logPath = [dir stringByAppendingPathComponent:@"SplitJump.log"];
	});

	NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
	fmt.dateFormat = @"MM-dd HH:mm:ss.SSS";
	NSString *line = [NSString stringWithFormat:@"%@  %@\n", [fmt stringFromDate:[NSDate date]], msg];

	NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
	if (!fh) {
		[line writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
		return;
	}
	@try {
		[fh seekToEndOfFile];
		[fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
		[fh closeFile];
	} @catch (NSException *e) {
	}
}
