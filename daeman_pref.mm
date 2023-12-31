//
//  daeman_pref.m
//  daeman
//
//  Created by APPLE on 2023/10/21.
//

#import <Foundation/Foundation.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

#import <AppSupport/CPDistributedMessagingCenter.h>
#import <rocketbootstrap/rocketbootstrap.h>
#include "utils.h"

static NSUserDefaults* _usrdefs = nil;
static void initPref() {
    if (_usrdefs == nil) {
        _usrdefs = [NSUserDefaults standardUserDefaults];
    }
}
static id getPref(NSString* key, id val) {
    initPref();
    NSDictionary* prefs = [_usrdefs objectForKey:@"chaoge.daeman"];
    if (prefs == nil) {
        prefs = @{};
        [_usrdefs setObject:@{} forKey:@"chaoge.daeman"];
    }
    if (prefs[key] == nil) {
        return val;
    }
    return prefs[key];
}
static void setPref(NSString* key, id val) {
    initPref();
    NSDictionary* prefs = [_usrdefs objectForKey:@"chaoge.daeman"];
    if (prefs == nil) {
        prefs = @{};
        [_usrdefs setObject:@{} forKey:@"chaoge.daeman"];
    }
    NSMutableDictionary* mprefs = [prefs mutableCopy];
    mprefs[key] = val;
    [_usrdefs setObject:mprefs forKey:@"chaoge.daeman"];
}

static NSString* localize(NSString* key) {
    static NSBundle* bundle = nil;
    if (!bundle) {
        bundle = [NSBundle bundleWithPath:@"/Library/PreferenceBundles/DaemanPrefs.bundle"];
    }
    if (key == nil) {
        return nil;
    }
    if (![key hasPrefix:@"$"]) {
        return key;
    }
    NSString* localizedString = [bundle localizedStringForKey:key value:key table:nil];
    if (localizedString == nil) {
        return key;
    }
    return localizedString;
}

static CPDistributedMessagingCenter* get_ipc() {
    static CPDistributedMessagingCenter* _center = nil;
    if (_center == nil) {
        _center = [CPDistributedMessagingCenter centerNamed:@"msgport.daeman"];
        rocketbootstrap_distributedmessagingcenter_apply(_center);
    }
    return _center;
}

static NSString* get_desc(NSString* label, BOOL detail) {
    static NSDictionary* daemon_dic = [NSDictionary dictionaryWithContentsOfFile:@"/Library/PreferenceBundles/DaemanPrefs.bundle/KnownDaemon.plist"];
    int indx = 0;
    NSString* lang = [[NSLocale currentLocale] languageCode];
    if ([lang isEqualToString:@"zh"]) {
        indx = 1;
    }
    if (daemon_dic[label] != nil) {
        NSDictionary* dic = daemon_dic[label];
        if (detail && dic[@"detail"] != nil) {
            return dic[@"detail"][indx];
        }
        return dic[@"simple"][indx];
    }
    return localize(@"$UNKNOWN");
}

static NSArray* getAllDaemons() {
    CPDistributedMessagingCenter* center = get_ipc();
    if (center == nil) {
        return nil;
    }
    NSDictionary* dic = [center sendMessageAndReceiveReplyName:@"listAll" userInfo:nil];
    if (dic == nil) {
        return nil;
    }
    return dic[@"data"];
}

@interface DaemanMultilineCell: PSTableCell
@end

@implementation DaemanMultilineCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString*)reuseIdentifier specifier:(PSSpecifier*)specifier {
    self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier specifier:specifier];
    if (self) {
        self.detailTextLabel.numberOfLines = 0;
        self.detailTextLabel.lineBreakMode = NSLineBreakByWordWrapping;
        self.detailTextLabel.text = [specifier propertyForKey:@"content"];
    }
    return self;
}
@end

@interface DaemanDetailController: PSListController
@end

@implementation DaemanDetailController {
    BOOL _Alive;
    BOOL _RunAtLoad;
    BOOL _KeepAlive;
}
- (BOOL)startOne:(BOOL)isStart {
    CPDistributedMessagingCenter* center = get_ipc();
    if (center == nil) {
        return nil;
    }
    NSDictionary* detail = [self.specifier propertyForKey:@"detail"];
    NSString* label = detail[@"Label"];
    
    NSMutableDictionary* policy = [getPref(@"usr_pol", @{}) mutableCopy];
    policy[label] = @(isStart);
    setPref(@"usr_pol", policy);
    
    NSMutableDictionary* info = [NSMutableDictionary dictionary];
    int flag = 0;
    info[@"Label"] = label;
    info[@"isStart"] = @(isStart);
    info[@"flag"] = @(flag);
    if (detail[@"Plist"] != nil) {
        info[@"Plist"] = detail[@"Plist"];
    }
    NSDictionary* dic = [center sendMessageAndReceiveReplyName:@"startOne" userInfo:info];
    if (dic == nil) {
        return NO;
    }
    NSNumber* status = dic[@"status"];
    return status.intValue >= 0;
}
- (id)getAlive:(PSSpecifier*)specifier {
    return @(_Alive);
}
- (void)updateCell {
    NSDictionary* detail = [self.specifier propertyForKey:@"detail"];
    NSString* cur_label = detail[@"Label"];
    NSArray* items = getAllDaemons();
    for (NSDictionary* item in items) {
        NSString* label = item[@"Label"];
        if ([label isEqualToString:cur_label]) {
            [self.specifier setProperty:item forKey:@"detail"];
            break;
        }
    }
    [self reloadSpecifiers];
}
- (void)setAlive:(id)value specifier:(PSSpecifier*)specifier {
    BOOL newAlive = [value boolValue];
    if (!newAlive) {
        NSDictionary* detail = [self.specifier propertyForKey:@"detail"];
        NSString* label = detail[@"Label"];
        if ([@[@"com.apple.SpringBoard", @"com.apple.backboardd"] containsObject:label]) {
            alert(@"Alert", localize(@"$STOPKEY"), 888, NO, nil);
        } else if ([label containsString:@"com.apple"]) {
            alert(@"Alert", localize(@"$STOPSYS"), 888, YES, ^(BOOL ok){
                if (ok) {
                    [self startOne:newAlive];
                    _Alive = newAlive;
                }
                [self updateCell];
            });
        } else {
            [self startOne:newAlive];
            _Alive = newAlive;
        }
    } else {
        [self startOne:newAlive];
        _Alive = newAlive;
    }
    [self updateCell];
}
- (id)getRunAtLoad:(PSSpecifier*)specifier {
    return @(_RunAtLoad);
}
- (void)setRunAtLoad:(id)value specifier:(PSSpecifier*)specifier {
   _RunAtLoad = [value boolValue];
}
- (id)getKeepAlive:(PSSpecifier*)specifier {
    return @(_KeepAlive);
}
- (void)setKeepAlive:(id)value specifier:(PSSpecifier*)specifier {
   _KeepAlive = [value boolValue];
}
- (NSArray*)specifiers {
    NSDictionary* dic = [self.specifier propertyForKey:@"detail"];
    _specifiers = [NSMutableArray array];
    PSSpecifier* spkey = nil, *spval = nil;
    NSString* Label = dic[@"Label"];
    NSNumber* Pid = dic[@"Pid"];
    _Alive = Pid.intValue >= 0;
    spval = [PSSpecifier preferenceSpecifierNamed:@"Alive" target:self set:@selector(setAlive:specifier:) get:@selector(getAlive:) detail:nil cell:PSSwitchCell edit:nil];
    [spval setProperty:@(YES) forKey:@"enabled"];
    [_specifiers addObject:spval];
    _RunAtLoad = NO;
    if (dic[@"RunAtLoad"] != nil) {
        _RunAtLoad = [dic[@"RunAtLoad"] boolValue];
    }
    spval = [PSSpecifier preferenceSpecifierNamed:@"RunAtLoad" target:self set:@selector(setRunAtLoad:specifier:) get:@selector(getRunAtLoad:) detail:nil cell:PSSwitchCell edit:nil];
    [spval setProperty:@(NO) forKey:@"enabled"];
    [_specifiers addObject:spval];
    _KeepAlive = NO;
    if (dic[@"KeepAlive"] != nil) {
        _KeepAlive = [dic[@"KeepAlive"] boolValue];
    }
    spval = [PSSpecifier preferenceSpecifierNamed:@"KeepAlive" target:self set:@selector(setKeepAlive:specifier:) get:@selector(getKeepAlive:) detail:nil cell:PSSwitchCell edit:nil];
    [spval setProperty:@(NO) forKey:@"enabled"];
    [_specifiers addObject:spval];
    
    spval = [PSSpecifier preferenceSpecifierNamed:@"" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
    [_specifiers addObject:spval];
    spval = [PSSpecifier preferenceSpecifierNamed:@"" target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
    [spval setProperty:DaemanMultilineCell.class forKey:@"cellClass"];
    [spval setProperty:get_desc(Label, YES) forKey:@"content"];
    [_specifiers addObject:spval];
    spkey = [PSSpecifier preferenceSpecifierNamed:@"Label" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
    [_specifiers addObject:spkey];
    spval = [PSSpecifier preferenceSpecifierNamed:Label target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
    [_specifiers addObject:spval];
    spkey = [PSSpecifier preferenceSpecifierNamed:@"Pid" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
    [_specifiers addObject:spkey];
    spval = [PSSpecifier preferenceSpecifierNamed:[Pid stringValue] target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
    [_specifiers addObject:spval];
    NSString* Plist = dic[@"Plist"];
    if (Plist != nil) {
        spkey = [PSSpecifier preferenceSpecifierNamed:@"Plist" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [_specifiers addObject:spkey];
        spval = [PSSpecifier preferenceSpecifierNamed:@"" target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
        [spval setProperty:DaemanMultilineCell.class forKey:@"cellClass"];
        [spval setProperty:Plist forKey:@"content"];
        [_specifiers addObject:spval];
    }
    NSString* Program = @"";
    if (dic[@"ProgramArguments"] != nil) {
        Program = [dic[@"ProgramArguments"] componentsJoinedByString:@" "];
    } else if (dic[@"Program"] != nil) {
        Program = dic[@"Program"];
    }
    spkey = [PSSpecifier preferenceSpecifierNamed:@"Program" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
    [_specifiers addObject:spkey];
    spval = [PSSpecifier preferenceSpecifierNamed:@"" target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
    [spval setProperty:DaemanMultilineCell.class forKey:@"cellClass"];
    [spval setProperty:Program forKey:@"content"];
    [_specifiers addObject:spval];
    NSString* User = dic[@"User"];
    if (User == nil) {
        User = @"mobile";
    }
    spkey = [PSSpecifier preferenceSpecifierNamed:@"User" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
    [_specifiers addObject:spkey];
    spval = [PSSpecifier preferenceSpecifierNamed:User target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
    [_specifiers addObject:spval];
    return _specifiers;
}
@end

@interface DaemanRootListController : PSListController
- (void)onExport;
- (void)onImport;
@end

@implementation DaemanRootListController
- (instancetype)init {
    self = [super init];
    [NSTimer scheduledTimerWithTimeInterval:10 target:self selector:@selector(reloadSpecifiers) userInfo:nil repeats:YES];
    return self;
}
- (BOOL)stopOne:(NSDictionary*)detail {
    CPDistributedMessagingCenter* center = get_ipc();
    if (center == nil) {
        return nil;
    }
    NSString* label = detail[@"Label"];
    NSMutableDictionary* info = [NSMutableDictionary dictionary];
    int flag = 0;
    info[@"Label"] = label;
    info[@"isStart"] = @NO;
    info[@"flag"] = @(flag);
    if (detail[@"Plist"] != nil) {
        info[@"Plist"] = detail[@"Plist"];
    }
    NSDictionary* dic = [center sendMessageAndReceiveReplyName:@"startOne" userInfo:info];
    if (dic == nil) {
        return NO;
    }
    NSNumber* status = dic[@"status"];
    return status.intValue >= 0;
}
- (void)onExport {
    NSDictionary* policy = getPref(@"usr_pol", @{});
    if (policy.count == 0) {
        return;
    }
    prompt(@"", localize(@"$INPUTNAME"), @"", ^(NSString* text){
        if (text.length < 1) {
            return;
        }
        NSString* path = [NSString stringWithFormat:@"/var/mobile/Media/%@", text];
        CPDistributedMessagingCenter* center = get_ipc();
        if (center == nil) {
            return;
        }
        NSDictionary* dic = [center sendMessageAndReceiveReplyName:@"export" userInfo:@{
            @"path": path,
            @"data": policy,
        }];
        if (dic != nil) {
            NSNumber* status = dic[@"status"];
            if (status.intValue >= 0) {
                NSString* msg = [NSString stringWithFormat:@"%@:%@", localize(@"$EXPSUC"), path];
                alert(@"", msg, 888, NO, nil);
                return;
            }
        }
        alert(@"", localize(@"$EXPERR"), 888, NO, nil);
    });
}
- (void)onImport {
    alert(@"", localize(@"$STOPSYS"), 888, YES, ^(BOOL ok){
        if (!ok) {
            return;
        }
        prompt(@"", localize(@"$INPUTNAME"), @"", ^(NSString* text){
            if (text.length < 1) {
                return;
            }
            NSString* path = [NSString stringWithFormat:@"/var/mobile/Media/%@", text];
            NSDictionary* dic = [NSDictionary dictionaryWithContentsOfFile:path];
            if (dic != nil && dic.count > 0) {
                NSArray* items = getAllDaemons();
                for (NSString* key in dic) {
                    if ([dic[key] boolValue]) {
                        continue;
                    }
                    for (NSDictionary* item in items) {
                        NSString* Label = item[@"Label"];
                        if ([key isEqualToString:Label]) {
                            [self stopOne:item];
                            break;
                        }
                    }
                }
                NSString* msg = [NSString stringWithFormat:@"%@:%@", localize(@"$IMPSUC"), path];
                alert(@"", msg, 888, NO, nil);
            } else {
                NSString* msg = [NSString stringWithFormat:@"%@:%@", localize(@"$IMPERR"), localize(@"$NOEXIST")];
                alert(@"", msg, 888, NO, nil);
            }
        });
    });
}
- (void)onRefresh {
    [self reloadSpecifiers];
}
- (id)getShowSys:(PSSpecifier*)specifier {
    return getPref(@"show_sys", @NO);
}
- (void)setShowSys:(id)value specifier:(PSSpecifier*)specifier {
    setPref(@"show_sys", value);
    [self reloadSpecifiers];
}
- (void)parseLocalizationsForSpecifiers:(NSArray*)specifiers {
    NSMutableArray* mutableSpecifiers = (NSMutableArray *)specifiers;
    for (PSSpecifier* specifier in mutableSpecifiers) {
        NSString* localizedTitle = localize(specifier.properties[@"label"]);
        if (localizedTitle != nil) {
            specifier.name = localizedTitle;
        }
    }
}
- (NSDictionary*)getBatteryState {
    CPDistributedMessagingCenter* center = get_ipc();
    if (center == nil) {
        return nil;
    }
    NSDictionary* dic = [center sendMessageAndReceiveReplyName:@"getBat" userInfo:nil];
    if (dic == nil) {
        return nil;
    }
    return dic;
}
- (NSArray*)specifiers {
    _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    [self parseLocalizationsForSpecifiers:_specifiers];
    NSArray* items = getAllDaemons();
    BOOL show_sys = [getPref(@"show_sys",  @NO) boolValue];
    NSString* desc = localize(@"$BATDROP");
    NSDictionary* bat_dic = [self getBatteryState];
    int bat_status = [bat_dic[@"status"] intValue];
    float bat_value = [bat_dic[@"value"] floatValue];
    if (bat_status == -1) {
        desc = [desc stringByAppendingFormat:@": %@", localize(@"$WAIT")];
    } else if (bat_status == -2) {
        desc = [desc stringByAppendingFormat:@": %@", localize(@"$CHARGE")];
    } else if (bat_status == -3) {
        desc = [desc stringByAppendingString:@": error1"];
    } else {
        desc = [desc stringByAppendingFormat:@": %f", bat_value];
    }
    PSSpecifier* sp = nil;
    sp = [PSSpecifier preferenceSpecifierNamed:desc target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
     [_specifiers addObject:sp];
    sp = [PSSpecifier preferenceSpecifierNamed:localize(@"$DAEMONLIST") target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
    [_specifiers addObject:sp];
    if (items != nil) {
        for (NSDictionary* item in items) {
            NSString* label = item[@"Label"];
            NSNumber* type = item[@"Type"];
            NSNumber* pid = item[@"Pid"];
            if (!show_sys && type.intValue >= 10) {
                continue;
            }
            NSString* desc = @"";
            if (pid.intValue >= 0) {
                desc = [NSString stringWithFormat:@"%@ %@:%@", get_desc(label, NO), localize(@"$STATUS"), localize(@"$RUNNING")];
            } else {
                desc = [NSString stringWithFormat:@"%@ %@:%@", get_desc(label, NO), localize(@"$STATUS"), localize(@"$STOPPED")];
            }
            PSSpecifier* sp = [PSSpecifier preferenceSpecifierNamed:label target:self set:nil get:nil detail:DaemanDetailController.class cell:PSLinkCell edit:nil];
            [sp setProperty:DaemanMultilineCell.class forKey:@"cellClass"];
            [sp setProperty:desc forKey:@"content"];
            [sp setProperty:@YES forKey:@"enabled"];
            [sp setProperty:label forKey:@"key"];
            [sp setProperty:item forKey:@"detail"];
            [_specifiers addObject:sp];
        }
    }
    return _specifiers;
}
@end

