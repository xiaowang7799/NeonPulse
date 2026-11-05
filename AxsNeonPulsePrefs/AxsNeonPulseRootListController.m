#import "AxsNeonPulseRootListController.h"
#import "AxsNeonPulsePreferences.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>


@interface AxsNeonPulseRootListController ()
@end

@implementation AxsNeonPulseRootListController

- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *items = [[self loadSpecifiersFromPlistName:@"AxsNeonPulseRoot"
                                                           target:self] mutableCopy];
        PSSpecifier *about = [PSSpecifier preferenceSpecifierNamed:@"关于我们" target:self
                              set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [about setProperty:@"搞机群友：三叶草" forKey:@"footerText"];
        [items addObject:about];
        _specifiers = items;
    }
    return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length == 0) return nil;
    return axs_neonpulse_readPreferences()[key] ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length == 0) return;
    NSError *error = nil;
    if (!axs_neonpulse_writePreference(key, value, &error)) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"设置未保存"
            message:error.localizedDescription ?: @"请检查配置文件路径和写入权限。"
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        [self reloadSpecifiers];
    }
}

// PSLinkListCell 的详情控制器会绕过 root 的 read/set 覆盖直接写 NSUserDefaults，
// 与 Tweak 读文件不一致；这里用 get/set 把发光颜色显式路由到文件写入。
- (id)axs_neonpulse_getGlowColor:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"] ?: @"glowColor";
    return axs_neonpulse_readPreferences()[key] ?: [specifier propertyForKey:@"default"];
}

- (void)axs_neonpulse_setGlowColor:(id)value specifier:(PSSpecifier *)specifier {
    [self setPreferenceValue:value specifier:specifier];
}

@end
