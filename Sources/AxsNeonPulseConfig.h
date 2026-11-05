#pragma once

#import <Foundation/Foundation.h>

@interface AxsNeonPulseConfig : NSObject
+ (instancetype)axs_neonpulse_shared;
- (BOOL)axs_neonpulse_isEnabled;
- (id)axs_neonpulse_valueForKey:(NSString *)key defaultValue:(id)defaultValue;
- (void)axs_neonpulse_reload;
@end
