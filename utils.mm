
#include "utils.h"

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

void alert(NSString* title, NSString* msg, int tmout, BOOL canCancel, void(^cb)(BOOL ok)) {
    @autoreleasepool {
        if ([NSThread isMainThread]) {
            CFOptionFlags cfRes;
            if (canCancel) {
                CFUserNotificationDisplayAlert(tmout, kCFUserNotificationPlainAlertLevel, nil, nil, nil, (__bridge CFStringRef)msg, (__bridge CFStringRef)title, CFSTR("OK"), CFSTR("CANCEL"), nil, &cfRes);
                if (cb != nil) {
                    cb(cfRes == kCFUserNotificationDefaultResponse);
                }
            } else {
                CFUserNotificationDisplayAlert(tmout, kCFUserNotificationPlainAlertLevel, nil, nil, nil, (__bridge CFStringRef)msg, (__bridge CFStringRef)title, CFSTR("OK"), nil, nil, nil);
            }
        } else {
            dispatch_sync(dispatch_get_main_queue(), ^{
                CFOptionFlags cfRes;
                if (canCancel) {
                    CFUserNotificationDisplayAlert(tmout, kCFUserNotificationPlainAlertLevel, nil, nil, nil, (__bridge CFStringRef)msg, (__bridge CFStringRef)title, CFSTR("OK"), CFSTR("CANCEL"), nil, &cfRes);
                    if (cb != nil) {
                        cb(cfRes == kCFUserNotificationDefaultResponse);
                    }
                } else {
                    CFUserNotificationDisplayAlert(tmout, kCFUserNotificationPlainAlertLevel, nil, nil, nil, (__bridge CFStringRef)msg, (__bridge CFStringRef)title, CFSTR("OK"), nil, nil, nil);
                }
            });
        }
    }
}

void prompt(NSString* title, NSString* msg, NSString* hint, void(^cb)(NSString* text)) {
    NSDictionary* panelDict = @{
        (__bridge NSString*)kCFUserNotificationAlertHeaderKey: title,
        (__bridge NSString*)kCFUserNotificationAlertMessageKey: msg,
        (__bridge NSString*)kCFUserNotificationTextFieldTitlesKey: hint,
        (__bridge NSString*)kCFUserNotificationAlternateButtonTitleKey: @"CANCEL",
    };
    CFUserNotificationRef dialog = CFUserNotificationCreate(kCFAllocatorDefault, 0, kCFUserNotificationPlainAlertLevel, nil, (__bridge CFDictionaryRef)panelDict);
    CFOptionFlags responseFlags;
    SInt32 error = CFUserNotificationReceiveResponse(dialog, 0, &responseFlags);
    if (error == 0){
        if ((responseFlags & 0x3) == kCFUserNotificationDefaultResponse) {
            CFStringRef value = CFUserNotificationGetResponseValue(dialog, kCFUserNotificationTextFieldValuesKey, 0);
            cb((__bridge_transfer NSString*)value);
        }
    }
    CFRelease(dialog);
}
