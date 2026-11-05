#pragma once

#import <UIKit/UIKit.h>

// SpringBoard 私有类：图标图片视图。仅声明本插件用到的接口，需在目标 iOS 版本真机核对。
@interface SBIconImageView : UIView
// iOS 15+ 连续圆角半径；不存在时用图标宽度比例回退。
- (CGFloat)continuousCornerRadius;
@end
