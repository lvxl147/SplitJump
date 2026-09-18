//
//  SJPicker.h — 应用选择面板
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "SJAppList.h"

NS_ASSUME_NONNULL_BEGIN

@interface SJPickerViewController : UIViewController

/// 面板是否正在显示
+ (BOOL)isPresenting;

/// 弹出面板。必须在主线程调用。
+ (void)presentWithSourceName:(nullable NSString *)sourceName
                   urlString:(nullable NSString *)urlString
                   entries:(NSArray<SJAppEntry *> *)entries
                     cancel:(nullable void (^)(void))onCancel
                     select:(nullable void (^)(SJAppEntry *entry))onSelect;

/// 关闭面板（不触发任何回调）
+ (void)dismiss;

@end

NS_ASSUME_NONNULL_END
