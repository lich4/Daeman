
#include "utils.h"
#include <spawn.h>

NSString* ns_2_json(id nsobj) {
    if (nsobj == nil) {
        return nil;
    }
    NSData* data = [NSJSONSerialization dataWithJSONObject:nsobj options:0 error:nil];
    if (data == nil) {
        return nil;
    }
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

id json_2_ns(NSString* s) {
    if (s == nil) {
        return nil;
    }
    NSData* data = [s dataUsingEncoding:NSUTF8StringEncoding];
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
}

int alert(NSString* title, NSString* msg, int tmout, void(^on_ok)()) {
    @autoreleasepool {
        if ([NSThread isMainThread]) {
            int ret = CFUserNotificationDisplayAlert(tmout, kCFUserNotificationPlainAlertLevel, nil, nil, nil, (__bridge CFStringRef)msg, (__bridge CFStringRef)title, CFSTR("OK"), nil, nil, nil);
            if (0 == ret && on_ok) {
                on_ok();
            }
        } else {
            dispatch_sync(dispatch_get_main_queue(), ^{
                int ret = CFUserNotificationDisplayAlert(tmout, kCFUserNotificationPlainAlertLevel, nil, nil, nil, (__bridge CFStringRef)msg, (__bridge CFStringRef)title, CFSTR("OK"), nil, nil, nil);
                if (0 == ret && on_ok) {
                    on_ok();
                }
            });
        }
    }
}

