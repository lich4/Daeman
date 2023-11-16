//
//  main.cpp
//  daeman
//
//  Created by APPLE on 2023/10/21.
//  Copyright (c) 2023 ___ORGANIZATIONNAME___. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

extern "C" {
#include "launchctl.h"
}
#include "utils.h"
#include <dlfcn.h>

static int platformize_me() {
    int ret = 0;
    #define FLAG_PLATFORMIZE (1 << 1)
    void* h_jailbreak = dlopen("/usr/lib/libjailbreak.dylib", RTLD_LAZY);
    if (h_jailbreak) {
        const char* dlsym_error = 0;
        dlerror();
        typedef void (*fix_entitle_prt_t)(pid_t pid, uint32_t what);
        fix_entitle_prt_t jb_oneshot_entitle_now = (fix_entitle_prt_t)dlsym(h_jailbreak, "jb_oneshot_entitle_now");
        dlsym_error = dlerror();
        if (jb_oneshot_entitle_now && !dlsym_error) {
            jb_oneshot_entitle_now(getpid(), FLAG_PLATFORMIZE);
        }
        dlerror();
        typedef void (*fix_setuid_prt_t)(pid_t pid);
        fix_setuid_prt_t jb_oneshot_fix_setuid_now = (fix_setuid_prt_t)dlsym(h_jailbreak, "jb_oneshot_fix_setuid_now");
        dlsym_error = dlerror();
        if (jb_oneshot_fix_setuid_now && !dlsym_error) {
            jb_oneshot_fix_setuid_now(getpid());
        }
    }
    ret += setuid(0);
    ret += setgid(0);
    return ret;
}

static int start_cmd(const char* name, bool start) {
    @autoreleasepool {
        xpc_object_t dict, reply;
        int ret;
        dict = xpc_dictionary_create(nil, nil, 0);
        launchctl_setup_xpc_dict(dict);
        xpc_dictionary_set_string(dict, "name", name);
        ret = launchctl_send_xpc_to_launchd(start?XPC_ROUTINE_SERVICE_START:XPC_ROUTINE_SERVICE_STOP, dict, &reply);
        NSLog(@"cloudtweak start_cmd_%d %s->%d", start, name, ret);
        return ret == EALREADY ? 0 : ret;
    }
}

// FLAG_W:1 FLAG_FORCE:2
static int load_cmd(const char* path, bool load, int flag) {
    xpc_object_t dict, reply;
    int ret;
    unsigned int domain = 0;
    bool wflag, force;
    wflag = force = false;
    wflag = (flag & 1) != 0;
    force = (flag & 2) != 0;
    dict = xpc_dictionary_create(nil, nil, 0);
    launchctl_setup_xpc_dict(dict);
    xpc_object_t array = launchctl_parse_load_unload(domain, 1, (char**)&path);
    xpc_dictionary_set_value(dict, "paths", array);
    if (load) {
        xpc_dictionary_set_bool(dict, "enable", wflag);
    } else {
        xpc_dictionary_set_bool(dict, "disable", wflag);
        if (__builtin_available(iOS 15.0, *)) {
            xpc_dictionary_set_bool(dict, "no-einprogress", true);
        }
    }
    xpc_dictionary_set_bool(dict, "legacy-load", true);
    if (force) {
        xpc_dictionary_set_bool(dict, "force", true);
    }
    ret = launchctl_send_xpc_to_launchd(load ? XPC_ROUTINE_LOAD : XPC_ROUTINE_UNLOAD, dict, &reply);
    if (ret == 0) {
        xpc_object_t errors = xpc_dictionary_get_value(reply, "errors");
        if (errors != NULL && xpc_get_type(errors) == XPC_TYPE_DICTIONARY) {
            xpc_dictionary_apply(errors, ^bool(const char *key, xpc_object_t value) {
                return true;
            });
        }
    }
    NSLog(@"cloudtweak load_cmd_%d %s->%d", load, path, ret);
    return ret;
}

static void add_plist_info(int type, NSString* root, NSMutableDictionary* dic) {
    NSFileManager* man = [NSFileManager defaultManager];
    for (NSString* item in [man contentsOfDirectoryAtPath:root error:nil]) {
        if (![item hasSuffix:@".plist"]) {
            //NSLog(@"daeman err invalid file %@", item);
            continue;
        }
        NSString* path = [root stringByAppendingPathComponent:item];
        NSDictionary* plist = [NSDictionary dictionaryWithContentsOfFile:path];
        if (plist == nil || plist[@"Label"] == nil) {
            //NSLog(@"daeman err invalid plist %@", path);
            continue;
        }
        NSString* Label = plist[@"Label"];
        NSMutableDictionary* subdic = [dic[Label] mutableCopy];
        if (subdic == nil) {
            subdic = [@{
                @"Label": Label,
                @"Pid": @(-1),
                @"Status": @(-1),
            } mutableCopy];
        }
        subdic[@"Type"] = @(type);
        subdic[@"Plist"] = path;
        [subdic addEntriesFromDictionary:plist];
        dic[Label] = subdic;
    }
}

static id xpc_2_ns(xpc_object_t obj) {
    xpc_type_t t = xpc_get_type(obj);
    if (t == XPC_TYPE_STRING) {
        return @(xpc_string_get_string_ptr(obj));
    } else if (t == XPC_TYPE_INT64) {
        return @(xpc_int64_get_value(obj));
    } else if (t == XPC_TYPE_DOUBLE) {
        return @(xpc_double_get_value(obj));
    } else if (t == XPC_TYPE_BOOL) {
        if (obj == XPC_BOOL_TRUE) {
            return @YES;
        } else if (obj == XPC_BOOL_FALSE) {
            return @NO;
        }
    } else if (t == XPC_TYPE_ARRAY) {
        size_t c = xpc_array_get_count(obj);
        NSMutableArray* arr = [NSMutableArray array];
        for (int i = 0; i < c; i++) {
            id val = xpc_2_ns(xpc_array_get_value(obj, i));
            if (val != nil) {
                [arr addObject:val];
            }
        }
        return arr;
    } else if (t == XPC_TYPE_DICTIONARY) {
        NSMutableDictionary* dic = [NSMutableDictionary dictionary];
        xpc_dictionary_apply(obj, ^ bool (const char* key, xpc_object_t value) {
            id val = xpc_2_ns(value);
            if (val != nil) {
                dic[@(key)] = val;
            }
            return true;
        });
        return dic;
    }
    return @"";
}

static NSDictionary* list_1_cmd(const char* label) {
    xpc_object_t reply;
    xpc_object_t dict = xpc_dictionary_create(NULL, NULL, 0);
    launchctl_setup_xpc_dict(dict);
    xpc_dictionary_set_string(dict, "name", label);
    int ret = launchctl_send_xpc_to_launchd(XPC_ROUTINE_LIST, dict, &reply);
    if (ret != 0) {
        return nil;
    }
    xpc_object_t service = xpc_dictionary_get_dictionary(reply, "service");
    if (service == nil) {
        return nil;
    }
    return xpc_2_ns(service);
}

static NSArray* list_cmd() {
    @autoreleasepool {
        xpc_object_t reply;
        xpc_object_t dict = xpc_dictionary_create(nil, nil, 0);
        launchctl_setup_xpc_dict(dict);
        int ret = launchctl_send_xpc_to_launchd(XPC_ROUTINE_LIST, dict, &reply);
        if (ret != 0) {
            return nil;
        }
        xpc_object_t services = xpc_dictionary_get_value(reply, "services");
        if (services == nil) {
            return nil;
        }
        NSMutableDictionary* dic = [NSMutableDictionary dictionary];
        xpc_dictionary_apply(services, ^ bool (const char* key, xpc_object_t value) {
            int64_t pid = xpc_dictionary_get_int64(value, "pid");
            int64_t status = xpc_dictionary_get_int64(value, "status");
            dic[@(key)] = @{
                @"Label": @(key),
                @"Pid": @(pid),
                @"Status": @(status),
                @"Type": @(-1),
            };
            //if (WIFSTOPPED(status))
            //    printf("???\t%s\n", key);
            //else if (WIFEXITED(status))
            //    printf("%d\t%s\n", WEXITSTATUS(status), key);
            //else if (WIFSIGNALED(status))
            //    printf("-%d\t%s\n", WTERMSIG(status), key);
            return true;
        });
        for (NSString* key in dic.allKeys) {
           id val = list_1_cmd(key.UTF8String);
           if (val != nil) {
               NSMutableDictionary* subdic = [dic[key] mutableCopy];
               [subdic addEntriesFromDictionary:val];
               dic[key] = subdic;
           }
        }
        add_plist_info(0, @"/Library/LaunchDaemons", dic);
        add_plist_info(10, @"/System/Library/LaunchDaemons", dic);
        add_plist_info(11, @"/System/Library/NanoLaunchDaemons", dic);
        for (NSString* key in dic.allKeys) {
            NSMutableDictionary* subdic = [dic[key] mutableCopy];
            if ([subdic[@"Type"] intValue] == -1) {
                if ([key containsString:@"com.apple"]) {
                    subdic[@"Type"] = @12;
                }
            }
            [subdic removeObjectForKey:@"PID"];
            dic[key] = subdic;
        }
        [dic removeObjectForKey:@"chaoge.daeman"];
        NSArray* sortedKeys = [dic.allKeys sortedArrayUsingSelector: @selector(caseInsensitiveCompare:)];
        return [dic objectsForKeys:sortedKeys notFoundMarker:NSNull.null];
    }
}

#import <AppSupport/CPDistributedMessagingCenter.h>
#import <rocketbootstrap/rocketbootstrap.h>
@interface MYMessagingCenter : NSObject {
    CPDistributedMessagingCenter * _messagingCenter;
}
@end

@implementation MYMessagingCenter {
    int batts[3];
    double batlvl[3];
}
+ (void)load {
    [self sharedInstance];
}
+ (instancetype)sharedInstance {
    static dispatch_once_t once = 0;
    __strong static id sharedInstance = nil;
    dispatch_once(&once, ^{
        sharedInstance = [self new];
    });
    return sharedInstance;
}
- (instancetype)init {
    @autoreleasepool {
        if ((self = [super init])) {
            _messagingCenter = [CPDistributedMessagingCenter centerNamed:@"msgport.daeman"];
            rocketbootstrap_distributedmessagingcenter_apply(_messagingCenter);
            [_messagingCenter runServerOnCurrentThread];
            [_messagingCenter registerForMessageName:@"listAll" target:self selector:@selector(handleMessageNamed:withUserInfo:)];
            [_messagingCenter registerForMessageName:@"startOne" target:self selector:@selector(handleMessageNamed:withUserInfo:)];
            [_messagingCenter registerForMessageName:@"export" target:self selector:@selector(handleMessageNamed:withUserInfo:)];
            [_messagingCenter registerForMessageName:@"getBat" target:self selector:@selector(handleMessageNamed:withUserInfo:)];
        }
        UIDevice* dev = UIDevice.currentDevice;
        dev.batteryMonitoringEnabled = YES;
        batts[0] = 0;
        batlvl[0] = 0;
        batts[1] = 0;
        batlvl[1] = 0;
        batts[2] = (int)time(0);
        batlvl[2] = dev.batteryLevel;
        void (^block)(NSNotification* note) = ^(NSNotification* note){
            int ts = (int)time(0);
            double lvl = dev.batteryLevel;
            batts[0] = batts[1];
            batlvl[0] = batlvl[1];
            batts[1] = batts[2];
            batlvl[1] = batlvl[2];
            batts[2] = ts;
            batlvl[2] = lvl;
            NSLog(@"daeman battery %d,%d,%lf", (int)dev.batteryState, ts, lvl);
        };
        [[NSNotificationCenter defaultCenter] addObserverForName:UIDeviceBatteryLevelDidChangeNotification object:nil queue:nil usingBlock:block];
        return self;
    }
}
- (NSDictionary*)handleMessageNamed:(NSString*)name withUserInfo:(NSDictionary*)userInfo {
    @autoreleasepool {
        if ([name isEqualToString:@"listAll"]) {
            return @{
                @"data": list_cmd(),
            };
        } else if ([name isEqualToString:@"startOne"]) {
            NSString* Label = userInfo[@"Label"];
            NSNumber* isStart = userInfo[@"isStart"];
            NSString* Plist =  userInfo[@"Plist"];
            NSNumber* flag = userInfo[@"flag"];
            if (isStart.boolValue) {
                if (Plist != nil) {
                    load_cmd(Plist.UTF8String, YES, flag.intValue);
                }
                start_cmd(Label.UTF8String, YES);
            } else {
                if (Plist != nil) {
                    load_cmd(Plist.UTF8String, NO, flag.intValue);
                }
                start_cmd(Label.UTF8String, NO);
            }
            return @{
                @"status": @0,
            };
        } else if ([name isEqualToString:@"export"]) {
            NSString* path = userInfo[@"path"];
            NSDictionary* policy = userInfo[@"data"];
            BOOL status = [policy writeToFile:path atomically:YES];
            return @{
                @"status": @(status?0:-1),
            };
        } else if ([name isEqualToString:@"getBat"]) {
            if (batts[0] == 0) {
                return @{
                    @"status": @-1,
                };
            } else {
                float v = (batlvl[0] - batlvl[2]) * 100 * 3600 / (batts[2] - batts[0]);
                return @{
                    @"status": @0,
                    @"value": @(v),
                };
            }
        }
        return nil;
    }
}
@end

int main (int argc, char** argv) {
    @autoreleasepool {
        NSLog(@"daeman start");
        platformize_me();
        set_memory_limit(getpid(), 20);
        [[NSRunLoop mainRunLoop] run];
        NSLog(@"daeman abnormally exit");
    }
}

