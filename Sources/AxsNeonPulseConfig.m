#import "AxsNeonPulseConfig.h"
#import "AxsNeonPulsePreferences.h"

@interface AxsNeonPulseConfig ()
@property (atomic, copy) NSDictionary *snapshot;
@property (nonatomic, strong) dispatch_queue_t reloadQueue;
@end

static void axs_neonpulse_preferencesDidChange(CFNotificationCenterRef center, void *observer,
                                          CFStringRef name, const void *object, CFDictionaryRef info) {
    AxsNeonPulseConfig *config = (__bridge AxsNeonPulseConfig *)observer;
    dispatch_async(config.reloadQueue, ^{
        [config axs_neonpulse_reload];
    });
}

@implementation AxsNeonPulseConfig

+ (instancetype)axs_neonpulse_shared {
    static AxsNeonPulseConfig *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _reloadQueue = dispatch_queue_create("com.axs.neonpulse.preferences", DISPATCH_QUEUE_SERIAL);
        [self axs_neonpulse_reload];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
            (__bridge const void *)self, axs_neonpulse_preferencesDidChange,
            (__bridge CFStringRef)AxsNeonPulsePreferencesChanged, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        // Close the window between the first read and observer registration.
        dispatch_async(_reloadQueue, ^{ [self axs_neonpulse_reload]; });
    }
    return self;
}

- (void)axs_neonpulse_reload {
    self.snapshot = axs_neonpulse_readPreferences();
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:AxsNeonPulsePreferencesChanged object:self];
    });
}

- (id)axs_neonpulse_valueForKey:(NSString *)key defaultValue:(id)defaultValue {
    return self.snapshot[key] ?: defaultValue;
}

- (BOOL)axs_neonpulse_isEnabled {
    id value = [self axs_neonpulse_valueForKey:@"enabled" defaultValue:@(YES)];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : YES;
}

- (void)dealloc {
    CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                            (__bridge const void *)self);
}

@end
