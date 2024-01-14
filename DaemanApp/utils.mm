//
//  utils.m
//  TrollStoreRemoteHelper
//
//  Created by APPLE on 2023/12/27.
//  Copyright © 2023 chaoge. All rights reserved.
//

#include "utils.h"

#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1
extern "C" {
int posix_spawnattr_set_persona_np(const posix_spawnattr_t* __restrict, uid_t, uint32_t);
int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t* __restrict, uid_t);
int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t* __restrict, uid_t);
}

int fd_is_valid(int fd) {
    return fcntl(fd, F_GETFD) != -1 || errno != EBADF;
}

NSString* getNSStringFromFile(int fd) {
    NSMutableString* ms = [NSMutableString new];
    ssize_t num_read;
    char c;
    if (!fd_is_valid(fd)) {
        return @"";
    }
    while ((num_read = read(fd, &c, sizeof(c)))) {
        [ms appendString:[NSString stringWithFormat:@"%c", c]];
        //if(c == '\n') {
        //    break;
        //}
    }
    return ms.copy;
}

extern char** environ;
int spawn(NSArray* args, NSString** stdOut, NSString** stdErr, pid_t* pidPtr, int flag) {
    NSString* file = args.firstObject;
    NSUInteger argCount = [args count];
    char **argsC = (char **)malloc((argCount + 1) * sizeof(char*));
    for (NSUInteger i = 0; i < argCount; i++) {
        argsC[i] = strdup([[args objectAtIndex:i] UTF8String]);
    }
    argsC[argCount] = NULL;
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    if ((flag & SPAWN_FLAG_ROOT) != 0) {
        posix_spawnattr_set_persona_np(&attr, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
        posix_spawnattr_set_persona_uid_np(&attr, 0);
        posix_spawnattr_set_persona_gid_np(&attr, 0);
    }
    posix_spawn_file_actions_t action;
    posix_spawn_file_actions_init(&action);
    int outErr[2];
    if(stdErr) {
        pipe(outErr);
        posix_spawn_file_actions_adddup2(&action, outErr[1], STDERR_FILENO);
        posix_spawn_file_actions_addclose(&action, outErr[0]);
    }
    int out[2];
    if(stdOut) {
        pipe(out);
        posix_spawn_file_actions_adddup2(&action, out[1], STDOUT_FILENO);
        posix_spawn_file_actions_addclose(&action, out[0]);
    }
    pid_t task_pid;
    pid_t* task_pid_ptr = &task_pid;
    if (pidPtr != 0) {
        task_pid_ptr = pidPtr;
    }
    int status = -200;
    int spawnError = posix_spawnp(task_pid_ptr, [file UTF8String], &action, &attr, (char* const*)argsC, environ);
    NSLog(@"posix_spawn %@ %d -> %d", args.firstObject, getpid(), task_pid);
    posix_spawnattr_destroy(&attr);
    for (NSUInteger i = 0; i < argCount; i++) {
        free(argsC[i]);
    }
    free(argsC);
    if(spawnError != 0) {
        NSLog(@"posix_spawn error %d\n", spawnError);
        return spawnError;
    }
    if ((flag & SPAWN_FLAG_NOWAIT) != 0) {
        return 0;
    }
    __block volatile BOOL _isRunning = YES;
    NSMutableString* outString = [NSMutableString new];
    NSMutableString* errString = [NSMutableString new];
    dispatch_semaphore_t sema = 0;
    dispatch_queue_t logQueue;
    if(stdOut || stdErr) {
        logQueue = dispatch_queue_create("com.opa334.TrollStore.LogCollector", NULL);
        sema = dispatch_semaphore_create(0);
        int outPipe = out[0];
        int outErrPipe = outErr[0];
        __block BOOL outEnabled = stdOut != nil;
        __block BOOL errEnabled = stdErr != nil;
        dispatch_async(logQueue, ^{
            while(_isRunning) {
                @autoreleasepool {
                    if(outEnabled) {
                        [outString appendString:getNSStringFromFile(outPipe)];
                    }
                    if(errEnabled) {
                        [errString appendString:getNSStringFromFile(outErrPipe)];
                    }
                }
            }
            dispatch_semaphore_signal(sema);
        });
    }
    do {
        if (waitpid(task_pid, &status, 0) != -1) {
            NSLog(@"Child status %d", WEXITSTATUS(status));
        } else {
            perror("waitpid");
            _isRunning = NO;
            return -222;
        }
    } while (!WIFEXITED(status) && !WIFSIGNALED(status));
    _isRunning = NO;
    if (stdOut || stdErr) {
        if(stdOut) {
            close(out[1]);
        }
        if(stdErr) {
            close(outErr[1]);
        }
        dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
        if(stdOut) {
            *stdOut = outString.copy;
        }
        if(stdErr) {
            *stdErr = errString.copy;
        }
    }
    return WEXITSTATUS(status);
}


extern "C" int _NSGetExecutablePath(char* buf, uint32_t* bufsize);
NSString* getAppEXEPath() {
    char exe[256];
    uint32_t bufsize = sizeof(exe);
    _NSGetExecutablePath(exe, &bufsize);
    return @(exe);
}


extern "C" {
#include "launchctl.h"
}
int start_cmd(const char* name, bool start) {
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
int load_cmd(const char* path, bool load, int flag) {
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

NSArray* list_cmd() {
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
        add_plist_info(1, @"/var/jb/Library/LaunchDaemons", dic);
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

