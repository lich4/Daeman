
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

#define MEMORYSTATUS_CMD_GET_PRIORITY_LIST            1
#define MEMORYSTATUS_CMD_SET_JETSAM_HIGH_WATER_MARK   5

typedef struct memorystatus_priority_entry {
    pid_t pid;
    int32_t priority;
    uint64_t user_data;
    int32_t limit;
    uint32_t state;
} memorystatus_priority_entry_t;

#ifdef __cplusplus
extern "C" {
#endif
int memorystatus_control(uint32_t command, int32_t pid, uint32_t flags, void* buffer, size_t buffersize);
#ifdef __cplusplus
}
#endif

int32_t get_mem_limit(int pid) {
    int rc = memorystatus_control(MEMORYSTATUS_CMD_GET_PRIORITY_LIST, 0, 0, 0, 0);
    if (rc < 1) {
        return -1;
    }
    struct memorystatus_priority_entry* buf = (struct memorystatus_priority_entry*)malloc(rc);
    rc = memorystatus_control(MEMORYSTATUS_CMD_GET_PRIORITY_LIST, 0, 0, buf, rc);
    int32_t limit = -1;
    for (int i = 0 ; i < rc; i++) {
        if (buf[i].pid == pid) {
            limit = buf[i].limit;
            break;
        }
    }
    free((void*)buf);
    return limit;
}

int set_memory_limit(int pid, int mb) {
    if (get_mem_limit(pid) < mb) { // 单位MB
        return memorystatus_control(MEMORYSTATUS_CMD_SET_JETSAM_HIGH_WATER_MARK, pid, mb, 0, 0);
    }
    return 0;
}


