#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <math.h>
#import "AxsNeonPulseConfig.h"
#import "AxsNeonPulsePreferences.h"
#import "AxsNeonPulsePrivate.h"

// ---------------------------------------------------------------------------
// 只读配置快照读取。Tweak 不写默认值，缺键用业务默认值回退。
// ---------------------------------------------------------------------------
static BOOL axs_neonpulse_boolValue(AxsNeonPulseConfig *config, NSString *key, BOOL fallback) {
    id value = [config axs_neonpulse_valueForKey:key defaultValue:@(fallback)];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : fallback;
}

static double axs_neonpulse_doubleValue(AxsNeonPulseConfig *config, NSString *key, double fallback) {
    id value = [config axs_neonpulse_valueForKey:key defaultValue:@(fallback)];
    return [value isKindOfClass:[NSNumber class]] ? [value doubleValue] : fallback;
}

// 解析 "#RRGGBB" / "RRGGBB" / "RGB" 三种写法。
static UIColor *axs_neonpulse_colorFromHex(id value) {
    if (![value isKindOfClass:[NSString class]]) return nil;
    NSString *string = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([string hasPrefix:@"#"]) string = [string substringFromIndex:1];
    if (string.length == 3) {
        string = [NSString stringWithFormat:@"%c%c%c%c%c%c",
                  [string characterAtIndex:0], [string characterAtIndex:0],
                  [string characterAtIndex:1], [string characterAtIndex:1],
                  [string characterAtIndex:2], [string characterAtIndex:2]];
    }
    if (string.length != 6) return nil;
    unsigned int rgb = 0;
    if (![[NSScanner scannerWithString:string] scanHexInt:&rgb]) return nil;
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

// 正在显示的图标图片视图弱注册表，配置变更时统一刷新，不持有强引用。
static NSHashTable *axs_neonpulse_iconViews(void) {
    static NSHashTable *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = [NSHashTable weakObjectsHashTable];
    });
    return table;
}

static char axs_neonpulse_glowKey;
static char axs_neonpulse_glowCacheKey;
static char axs_neonpulse_motionKey;
static char axs_neonpulse_breathCacheKey;
static char axs_neonpulse_parallaxCacheKey;
static NSString *const AxsNeonPulseBreathingKey = @"axs_neonpulse_breathing";

static CGFloat axs_neonpulse_iconCornerRadius(SBIconImageView *imageView) {
    if ([imageView respondsToSelector:@selector(continuousCornerRadius)]) {
        CGFloat radius = [imageView continuousCornerRadius];
        if (radius > 0.0) return radius;
    }
    // iOS 图标圆角约为图标宽度 22.37%，作为真机缺失时的回退。
    return imageView.bounds.size.width * 0.2237;
}

// ---------------------------------------------------------------------------
// 霓虹发光边框：静态效果。带路径缓存，布局未变化时不重设 path/shadow，
// 避免每次 layout 都重渲染阴影（阴影是静态的，渲染一次即被缓存）。
// ---------------------------------------------------------------------------
static void axs_neonpulse_refreshGlow(SBIconImageView *imageView) {
    AxsNeonPulseConfig *config = [AxsNeonPulseConfig axs_neonpulse_shared];
    BOOL enabled = [config axs_neonpulse_isEnabled]
        && axs_neonpulse_boolValue(config, @"glowEnabled", YES);
    UIView *container = imageView.superview;
    CAShapeLayer *layer = objc_getAssociatedObject(imageView, &axs_neonpulse_glowKey);
    if (!enabled || !container) {
        if (layer) {
            [layer removeFromSuperlayer];
            objc_setAssociatedObject(imageView, &axs_neonpulse_glowKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        objc_setAssociatedObject(imageView, &axs_neonpulse_glowCacheKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    NSString *hex = [config axs_neonpulse_valueForKey:@"glowColor" defaultValue:@"#00E5FF"];
    UIColor *color = axs_neonpulse_colorFromHex(hex);
    if (!color) color = [UIColor cyanColor];
    CGFloat intensity = axs_neonpulse_doubleValue(config, @"glowIntensity", 2.0);
    CGFloat width = axs_neonpulse_doubleValue(config, @"glowWidth", 2.5);
    CGRect frame = imageView.frame;
    CGFloat radius = axs_neonpulse_iconCornerRadius(imageView);

    NSString *signature = [NSString stringWithFormat:@"%.1f,%.1f,%.1f,%.1f|%.1f|%.2f|%.2f|%@",
                           frame.origin.x, frame.origin.y, frame.size.width, frame.size.height,
                           radius, width, intensity, hex];
    NSString *cached = objc_getAssociatedObject(imageView, &axs_neonpulse_glowCacheKey);
    if (layer && cached && [cached isEqualToString:signature]) {
        return; // 无变化，跳过重渲染
    }

    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:frame cornerRadius:radius];
    if (layer && layer.superlayer != container.layer) {
        // 父视图变化时搬到新的父图层。
        [layer removeFromSuperlayer];
        layer = nil;
        objc_setAssociatedObject(imageView, &axs_neonpulse_glowKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!layer) {
        layer = [CAShapeLayer layer];
        layer.fillColor = [UIColor clearColor].CGColor;
        [container.layer insertSublayer:layer atIndex:0];
        objc_setAssociatedObject(imageView, &axs_neonpulse_glowKey, layer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    layer.path = path.CGPath;
    layer.strokeColor = color.CGColor;
    layer.lineWidth = width;
    layer.shadowColor = color.CGColor;
    layer.shadowRadius = fmax(0.0, intensity * 6.0);
    layer.shadowOpacity = 1.0;
    layer.shadowOffset = CGSizeZero;
    layer.shadowPath = path.CGPath;
    objc_setAssociatedObject(imageView, &axs_neonpulse_glowCacheKey, signature, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// ---------------------------------------------------------------------------
// 呼吸动画：持续动画，仅在图标可见（有 window）时运行，离屏即移除。
// ---------------------------------------------------------------------------
static void axs_neonpulse_refreshBreathing(SBIconImageView *imageView) {
    AxsNeonPulseConfig *config = [AxsNeonPulseConfig axs_neonpulse_shared];
    BOOL enabled = [config axs_neonpulse_isEnabled]
        && axs_neonpulse_boolValue(config, @"breathingEnabled", YES)
        && imageView.window != nil;
    if (!enabled) {
        [imageView.layer removeAnimationForKey:AxsNeonPulseBreathingKey];
        objc_setAssociatedObject(imageView, &axs_neonpulse_breathCacheKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    double speed = axs_neonpulse_doubleValue(config, @"breathingSpeed", 1.0);
    if (speed <= 0.0) speed = 1.0;
    double amplitude = axs_neonpulse_doubleValue(config, @"breathingAmplitude", 8.0) / 100.0;
    if (amplitude < 0.0) amplitude = 0.0;

    NSString *signature = [NSString stringWithFormat:@"%.4f|%.4f", speed, amplitude];
    NSString *cached = objc_getAssociatedObject(imageView, &axs_neonpulse_breathCacheKey);
    if ([imageView.layer animationForKey:AxsNeonPulseBreathingKey] && cached
        && [cached isEqualToString:signature]) {
        return;
    }

    CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
    animation.values = @[@1.0, @(1.0 + amplitude), @1.0, @(1.0 - amplitude), @1.0];
    animation.keyTimes = @[@0.0, @0.25, @0.5, @0.75, @1.0];
    CAMediaTimingFunction *ease = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    animation.timingFunctions = @[ease, ease, ease, ease];
    animation.duration = 2.0 / speed;
    animation.repeatCount = INFINITY;
    animation.removedOnCompletion = NO;
    [imageView.layer addAnimation:animation forKey:AxsNeonPulseBreathingKey];
    objc_setAssociatedObject(imageView, &axs_neonpulse_breathCacheKey, signature, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// ---------------------------------------------------------------------------
// 3D 视差：仅在图标可见时挂载运动效果。
// ---------------------------------------------------------------------------
static void axs_neonpulse_refreshParallax(SBIconImageView *imageView) {
    AxsNeonPulseConfig *config = [AxsNeonPulseConfig axs_neonpulse_shared];
    BOOL enabled = [config axs_neonpulse_isEnabled]
        && axs_neonpulse_boolValue(config, @"parallaxEnabled", YES)
        && imageView.window != nil;
    UIMotionEffectGroup *existing = objc_getAssociatedObject(imageView, &axs_neonpulse_motionKey);
    if (!enabled) {
        if (existing) {
            [imageView removeMotionEffect:existing];
            objc_setAssociatedObject(imageView, &axs_neonpulse_motionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        objc_setAssociatedObject(imageView, &axs_neonpulse_parallaxCacheKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    double intensity = axs_neonpulse_doubleValue(config, @"parallaxIntensity", 40.0);
    if (intensity < 0.0) intensity = 0.0;
    NSNumber *cachedIntensity = objc_getAssociatedObject(imageView, &axs_neonpulse_parallaxCacheKey);
    if (existing && cachedIntensity && [cachedIntensity doubleValue] == intensity) {
        return;
    }
    if (existing) [imageView removeMotionEffect:existing];
    UIInterpolatingMotionEffect *horizontal = [[UIInterpolatingMotionEffect alloc]
        initWithKeyPath:@"center.x" type:UIInterpolatingMotionEffectTypeTiltAlongHorizontalAxis];
    horizontal.minimumRelativeValue = @(-intensity);
    horizontal.maximumRelativeValue = @(intensity);
    UIInterpolatingMotionEffect *vertical = [[UIInterpolatingMotionEffect alloc]
        initWithKeyPath:@"center.y" type:UIInterpolatingMotionEffectTypeTiltAlongVerticalAxis];
    vertical.minimumRelativeValue = @(-intensity);
    vertical.maximumRelativeValue = @(intensity);
    UIMotionEffectGroup *group = [UIMotionEffectGroup new];
    group.motionEffects = @[horizontal, vertical];
    [imageView addMotionEffect:group];
    objc_setAssociatedObject(imageView, &axs_neonpulse_motionKey, group, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(imageView, &axs_neonpulse_parallaxCacheKey, @(intensity), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// ---------------------------------------------------------------------------
// 全量协调与清理。
// ---------------------------------------------------------------------------
static void axs_neonpulse_removeAllEffects(SBIconImageView *imageView) {
    CAShapeLayer *layer = objc_getAssociatedObject(imageView, &axs_neonpulse_glowKey);
    if (layer) {
        [layer removeFromSuperlayer];
        objc_setAssociatedObject(imageView, &axs_neonpulse_glowKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    objc_setAssociatedObject(imageView, &axs_neonpulse_glowCacheKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [imageView.layer removeAnimationForKey:AxsNeonPulseBreathingKey];
    objc_setAssociatedObject(imageView, &axs_neonpulse_breathCacheKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIMotionEffectGroup *group = objc_getAssociatedObject(imageView, &axs_neonpulse_motionKey);
    if (group) {
        [imageView removeMotionEffect:group];
        objc_setAssociatedObject(imageView, &axs_neonpulse_motionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    objc_setAssociatedObject(imageView, &axs_neonpulse_parallaxCacheKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void axs_neonpulse_refreshIcon(SBIconImageView *imageView) {
    AxsNeonPulseConfig *config = [AxsNeonPulseConfig axs_neonpulse_shared];
    if (![config axs_neonpulse_isEnabled]) {
        axs_neonpulse_removeAllEffects(imageView);
        return;
    }
    axs_neonpulse_refreshGlow(imageView);
    axs_neonpulse_refreshBreathing(imageView);
    axs_neonpulse_refreshParallax(imageView);
}

// ---------------------------------------------------------------------------
// Logos hook：直接 hook 图标图片视图，覆盖主屏、Dock 与文件夹图标。
// 离屏（window 为 nil）时停掉呼吸/视差这类持续动画，节省电量、降低发热。
// ---------------------------------------------------------------------------
%hook SBIconImageView

- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        [axs_neonpulse_iconViews() addObject:self];
        axs_neonpulse_refreshIcon(self);
    } else {
        [axs_neonpulse_iconViews() removeObject:self];
        axs_neonpulse_removeAllEffects(self);
    }
}

- (void)layoutSubviews {
    %orig;
    // 只在 frame 实际变化时刷新发光描边，避免滚动时高频重复计算。
    // 缓存签名已覆盖 frame，这里额外加一个快速路径：bounds 未变直接返回。
    static char axs_neonpulse_boundsKey;
    CGRect current = self.bounds;
    NSValue *cached = objc_getAssociatedObject(self, &axs_neonpulse_boundsKey);
    if (cached && CGRectEqualToRect([cached CGRectValue], current)) {
        return;
    }
    objc_setAssociatedObject(self, &axs_neonpulse_boundsKey, [NSValue valueWithCGRect:current], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if ([[AxsNeonPulseConfig axs_neonpulse_shared] axs_neonpulse_isEnabled]) {
        axs_neonpulse_refreshGlow(self);
    }
}

- (void)dealloc {
    [axs_neonpulse_iconViews() removeObject:self];
    axs_neonpulse_removeAllEffects(self);
    %orig;
}

%end

static id axs_neonpulse_observerToken;

%ctor {
    @autoreleasepool {
        // 读取一次快照，触发配置层初始化；不写默认值。
        [AxsNeonPulseConfig axs_neonpulse_shared];
        // 面板写配置后经 Darwin 通知到达本进程，主线程刷新所有可见图标视图。
        axs_neonpulse_observerToken = [[NSNotificationCenter defaultCenter]
            addObserverForName:AxsNeonPulsePreferencesChanged object:nil
            queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notification) {
                for (SBIconImageView *imageView in [axs_neonpulse_iconViews() allObjects]) {
                    axs_neonpulse_refreshIcon(imageView);
                }
            }];
    }
}
