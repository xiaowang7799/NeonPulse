#pragma once

#import <UIKit/UIKit.h>

// SpringBoard 私有类，仅声明本插件用到的接口，需在目标 iOS 版本真机核对。
// 这些类注入 SpringBoard 进程后在运行时存在，编译器只需知道其接口签名。

@interface SBIconImageView : UIView
// iOS 15+ 提供的连续圆角半径；不存在时用图标宽度比例回退。
- (CGFloat)continuousCornerRadius;
@end

@interface SBIconView : UIView
// 图标图片视图，用于套发光、呼吸与视差。
- (SBIconImageView *)iconImageView;
@end
