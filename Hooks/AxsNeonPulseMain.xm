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

static UIColor *axs_neonpulse_colorFromHex(id value) {
    if (![value isKindOfClass:[NSString class]]) return nil;
    NSString *string = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([string hasPrefix:@"#"]) string = [string substringFromIndex:1];
    if (string.length != 6) return nil;
    unsigned int rgb = 0;
    if (![[NSScanner scannerWithString:string] scanHexInt:&rgb]) return nil;
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

// 正在显示的图标视图弱注册表，用于配置变更时统一刷新，不持有强引用。
static NSHashTable *axs_neonpulse_iconViews(void) {
    static NSHashTable *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = [NSHashTable weakObjectsHashTable];
    });
    return table;
}

static char axs_neonpulse_glowKey;
static char axs_neonpulse_motionKey;
static char axs_neonpulse_breathCacheKey;
static char axs_neonpulse_parallaxCacheKey;
static NSString *const AxsNeonPulseBreathingKey = @"axs_neonpulse_breathing";

static SBIconImageView *axs_neonpulse_imageViewOf(SBIconView *view) {
    if (![view respondsToSelector:@selector(iconImageView)]) return nil;
    return [view iconImageView];
}

static CAShapeLayer *axs_neonpulse_glowLayer(SBIconView *view) {
    return objc_getAssociatedObject(view, &axs_neonpulse_glowKey);
}

static CGFloat axs_neonpulse_iconCornerRadius(SBIconImageView *imageView) {
    if ([imageView respondsToSelector:@selector(continuousCornerRadius)]) {
        CGFloat radius = [imageView continuousCornerRadius];
        if (radius > 0.0) return radius;
    }
    // iOS 图标圆角约为图标宽度 22.37%，作为真机缺失时的回退。
    return imageView.bounds.size.width * 0.2237;
}

// ---------------------------------------------------------------------------
// 霓虹发光边框：在 SBIconView 上插入一个描边 + 辉光的 CAShapeLayer。
// ---------------------------------------------------------------------------
static void axs_neonpulse_refreshGlow(SBIconView *view) {
    AxsNeonPulseConfig *config = [AxsNeonPulseConfig axs_neonpulse_shared];
    BOOL enabled = [config axs_neonpulse_isEnabled]
        && axs_neonpulse_boolValue(config, @"glowEnabled", YES);
    SBIconImageView *imageView = axs_neonpulse_imageViewOf(view);
    CAShapeLayer *layer = axs_neonpulse_glowLayer(view);
    if (!enabled || !imageView) {
        if (layer) {
            [layer removeFromSuperlayer];
            objc_setAssociatedObject(view, &axs_neonpulse_glowKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }
    UIColor *color = axs_neonpulse_colorFromHex([config axs_neonpulse_valueForKey:@"glowColor" defaultValue:@"#00E5FF"]);
    if (!color) color = [UIColor cyanColor];
    CGFloat intensity = axs_neonpulse_doubleValue(config, @"glowIntensity", 1.0);
    CGFloat width = axs_neonpulse_doubleValue(config, @"glowWidth", 1.5);
    // 无论图标视图嵌套多深，都换算到 SBIconView 坐标系，保证描边路径对齐。
    CGRect frame = [view convertRect:imageView.bounds fromView:imageView];
    CGFloat radius = axs_neonpulse_iconCornerRadius(imageView);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:frame cornerRadius:radius];
    if (!layer) {
        layer = [CAShapeLayer layer];
        layer.fillColor = [UIColor clearColor].CGColor;
        [view.layer insertSublayer:layer atIndex:0];
        objc_setAssociatedObject(view, &axs_neonpulse_glowKey, layer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    layer.path = path.CGPath;
    layer.strokeColor = color.CGColor;
    layer.lineWidth = width;
    layer.shadowColor = color.CGColor;
    layer.shadowRadius = fmax(0.0, intensity * 6.0);
    layer.shadowOpacity = 1.0;
    layer.shadowOffset = CGSizeZero;
    layer.shadowPath = path.CGPath;
}

// ---------------------------------------------------------------------------
// 呼吸动画：图标缩放的柔和脉冲。带参数缓存，布局刷新时不打断动画相位。
// ---------------------------------------------------------------------------
static void axs_neonpulse_refreshBreathing(SBIconView *view) {
    AxsNeonPulseConfig *config = [AxsNeonPulseConfig axs_neonpulse_shared];
    BOOL enabled = [config axs_neonpulse_isEnabled]
        && axs_neonpulse_boolValue(config, @"breathingEnabled", YES);
    SBIconImageView *imageView = axs_neonpulse_imageViewOf(view);
    if (!imageView) return;
    if (!enabled) {
        [imageView.layer removeAnimationForKey:AxsNeonPulseBreathingKey];
        objc_setAssociatedObject(imageView, &axs_neonpulse_breathCacheKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    double speed = axs_neonpulse_doubleValue(config, @"breathingSpeed", 1.0);
    if (speed <= 0.0) speed = 1.0;
    // 面板用百分比（0–15），默认 4%，换算为缩放振幅。
    double amplitude = axs_neonpulse_doubleValue(config, @"breathingAmplitude", 4.0) / 100.0;
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
// 3D 视差：UIKit 原生倾斜视差，图标随设备角度平移，形成浮起效果。
// ---------------------------------------------------------------------------
static void axs_neonpulse_refreshParallax(SBIconView *view) {
    AxsNeonPulseConfig *config = [AxsNeonPulseConfig axs_neonpulse_shared];
    BOOL enabled = [config axs_neonpulse_isEnabled]
        && axs_neonpulse_boolValue(config, @"parallaxEnabled", YES);
    SBIconImageView *imageView = axs_neonpulse_imageViewOf(view);
    if (!imageView) return;
    UIMotionEffectGroup *existing = objc_getAssociatedObject(imageView, &axs_neonpulse_motionKey);
    if (!enabled) {
        if (existing) {
            [imageView removeMotionEffect:existing];
            objc_setAssociatedObject(imageView, &axs_neonpulse_motionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        objc_setAssociatedObject(imageView, &axs_neonpulse_parallaxCacheKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    double intensity = axs_neonpulse_doubleValue(config, @"parallaxIntensity", 24.0);
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
static void axs_neonpulse_removeAllEffects(SBIconView *view) {
    CAShapeLayer *layer = axs_neonpulse_glowLayer(view);
    if (layer) {
        [layer removeFromSuperlayer];
        objc_setAssociatedObject(view, &axs_neonpulse_glowKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    SBIconImageView *imageView = axs_neonpulse_imageViewOf(view);
    if (imageView) {
        [imageView.layer removeAnimationForKey:AxsNeonPulseBreathingKey];
        objc_setAssociatedObject(imageView, &axs_neonpulse_breathCacheKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UIMotionEffectGroup *group = objc_getAssociatedObject(imageView, &axs_neonpulse_motionKey);
        if (group) {
            [imageView removeMotionEffect:group];
            objc_setAssociatedObject(imageView, &axs_neonpulse_motionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        objc_setAssociatedObject(imageView, &axs_neonpulse_parallaxCacheKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void axs_neonpulse_refreshIcon(SBIconView *view) {
    AxsNeonPulseConfig *config = [AxsNeonPulseConfig axs_neonpulse_shared];
    if (![config axs_neonpulse_isEnabled]) {
        // 主开关关闭时清掉全部效果，保持系统原行为。
        axs_neonpulse_removeAllEffects(view);
        return;
    }
    axs_neonpulse_refreshGlow(view);
    axs_neonpulse_refreshBreathing(view);
    axs_neonpulse_refreshParallax(view);
}

// ---------------------------------------------------------------------------
// Logos hook：只 hook SBIconView 这一处，覆盖主屏、Dock 与文件夹图标。
// ---------------------------------------------------------------------------
%hook SBIconView

- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        [axs_neonpulse_iconViews() addObject:self];
    } else {
        [axs_neonpulse_iconViews() removeObject:self];
    }
    axs_neonpulse_refreshIcon(self);
}

- (void)layoutSubviews {
    %orig;
    // 全量协调；呼吸/视差带参数缓存，重复布局不会打断动画。
    axs_neonpulse_refreshIcon(self);
}

- (void)dealloc {
    [axs_neonpulse_iconViews() removeObject:self];
    %orig;
}

%end

static id axs_neonpulse_observerToken;

%ctor {
    @autoreleasepool {
        // 读取一次快照，触发配置层初始化；不写默认值。
        [AxsNeonPulseConfig axs_neonpulse_shared];
        // 面板写配置后经 Darwin 通知到达本进程，主线程刷新所有图标视图。
        axs_neonpulse_observerToken = [[NSNotificationCenter defaultCenter]
            addObserverForName:AxsNeonPulsePreferencesChanged object:nil
            queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notification) {
                for (SBIconView *view in [axs_neonpulse_iconViews() allObjects]) {
                    axs_neonpulse_refreshIcon(view);
                }
            }];
    }
}
