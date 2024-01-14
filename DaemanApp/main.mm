#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <GCDWebServers/GCDWebServers.h>
#include "utils.h"

static NSString* log_prefix = @"DaemanLogger";

#define TEST
#ifdef TEST
#import <GCDWebServers/GCDWebServers.h>
#define GSERV_PORT      1230
#endif

@interface MainWin : UIViewController<WKNavigationDelegate, WKScriptMessageHandlerWithReply>
+ (instancetype)inst;
- (instancetype)init;
- (void)initWithWindow:(UIWindow*)window;
@property(retain) UIWindow* window;
@end

@interface SceneDelegate : UIResponder<UIWindowSceneDelegate>
@property (strong, nonatomic) UIWindow * window;
@end

@implementation SceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
}
- (void)sceneDidDisconnect:(UIScene *)scene {
}
- (void)sceneWillResignActive:(UIScene *)scene {
}
- (void)sceneWillEnterForeground:(UIScene *)scene {
}
- (void)sceneDidEnterBackground:(UIScene *)scene {
}
- (void)sceneDidBecomeActive:(UIScene *)scene {
    @autoreleasepool {
        [MainWin.inst initWithWindow:self.window];
    }
}
- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext*>*)URLContexts {
}
@end

@interface AppDelegate : UIResponder<UIApplicationDelegate>
@property (strong, nonatomic) UIWindow * window;
@end

@implementation AppDelegate
@synthesize window = _window;
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options {
    @autoreleasepool {
        return [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
    }
}
- (void)application:(UIApplication *)application didDiscardSceneSessions:(NSSet<UISceneSession *> *)sceneSessions {
}
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    @autoreleasepool {
        [MainWin.inst initWithWindow:self.window];
        return YES;
    }
}
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation{
    return YES;
}
@end

@interface ViewController : UIViewController
@end
@implementation ViewController
@end

@implementation MainWin {
    WKWebView* webview;
}
+ (instancetype)inst {
    static dispatch_once_t pred = 0;
    static MainWin* inst_ = nil;
    dispatch_once(&pred, ^{
        inst_ = [self new];
    });
    return inst_;
}
- (instancetype)init {
    self = super.init;
    self.window = nil;
    return self;
}
- (void)serv {
    static GCDWebServer* _webServer = nil;
    if (_webServer == nil) {
        _webServer = [GCDWebServer new];
        NSString* html_root = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"www"];
        [_webServer addGETHandlerForBasePath:@"/" directoryPath:html_root indexFilename:nil cacheAge:3600 allowRangeRequests:YES];
        [_webServer addDefaultHandlerForMethod:@"POST" requestClass:GCDWebServerDataRequest.class processBlock:^GCDWebServerResponse*(GCDWebServerDataRequest* request) {
            NSDictionary* jres = [self handlePOST:request.path with:request.jsonObject];
            return [GCDWebServerDataResponse responseWithJSONObject:jres];
        }];
        BOOL status = [_webServer startWithPort:GSERV_PORT bonjourName:nil];
        if (!status) {
            NSLog(@"%@ serve failed, exit", log_prefix);
            exit(0);
        }
    }
}

- (NSDictionary*)handlePOST:(NSString*)path with:(NSString*)data {
    NSLog(@"post %@ %@", path, data);
    return @{
        @"status": @0,
    };
}
- (void)initWithWindow:(UIWindow*)window_ {
    @autoreleasepool {
#ifdef TEST
        [self serv];
#endif
        if (self.window != nil) {
            return;
        }
        self.window = window_;
        [[WKWebsiteDataStore defaultDataStore] fetchDataRecordsOfTypes:WKWebsiteDataStore.allWebsiteDataTypes completionHandler:^(NSArray<WKWebsiteDataRecord*>* records) {
            [[WKWebsiteDataStore defaultDataStore] removeDataOfTypes:WKWebsiteDataStore.allWebsiteDataTypes forDataRecords:records completionHandler:^{
            }];
        }];
        CGSize size = UIScreen.mainScreen.bounds.size;
        NSString* imgpath = [NSString stringWithFormat:@"%@/splash.png", NSBundle.mainBundle.bundlePath];
        UIImageView* imgview = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, size.width, size.height)];
        imgview.image = [UIImage imageWithContentsOfFile:imgpath];
        [self.window addSubview:imgview];
        
        WKUserContentController* contentController = [WKUserContentController new];
        if (@available(iOS 14.0, *)) {
            [contentController addScriptMessageHandlerWithReply:self contentWorld:WKContentWorld.pageWorld name:@"bridge"];
        }
        WKWebViewConfiguration* webkitConfig = [WKWebViewConfiguration new];
        webkitConfig.userContentController = contentController;
        WKWebView* webview = [[WKWebView alloc] initWithFrame:CGRectMake(0, 0, size.width, size.height) configuration:webkitConfig];
        [self.window addSubview:webview];
        webview.navigationDelegate = self;
        self->webview = webview;
#ifdef TEST
        NSString* nsurl = [NSString stringWithFormat:@"http://127.0.0.1:%d/index.html", GSERV_PORT];
        NSURL* url = [NSURL URLWithString:nsurl];
#else
        NSString* wwwpath = [NSString stringWithFormat:@"%@/www/index.html", NSBundle.mainBundle.bundlePath];
        NSURL* url = [NSURL fileURLWithPath:wwwpath];
#endif
        NSURLRequest* req = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:3.0];;
        [webview loadRequest:req];
    }
}
- (void)webView:(WKWebView*)webView didFinishNavigation:(WKNavigation *)navigation {
    [self.window bringSubviewToFront:self->webview];
}
- (void)userContentController:(WKUserContentController*)userContentController didReceiveScriptMessage:(WKScriptMessage*)message replyHandler:(void(^)(id reply, NSString* errorMessage))replyHandler {
    @autoreleasepool {
        if ([message.name isEqualToString:@"bridge"]) {
            // window.webkit.messageHandlers.bridge.postMessage(body)
            NSDictionary* args = message.body;
            NSString* api = args[@"api"];
            if ([api isEqualToString:@"init"]) {
                NSString* path = [NSString stringWithFormat:@"%@/KnownDaemon.plist", NSBundle.mainBundle.bundlePath];
                NSDictionary* knownDaemon = [NSDictionary dictionaryWithContentsOfFile:path];
                replyHandler(knownDaemon, nil);
            } else if ([api isEqualToString:@"list_daemon"]) {
                NSArray* data = list_cmd();
                replyHandler(data, nil);
            } else if ([api isEqualToString:@"ctrl_daemon"]) {
                NSString* label = args[@"label"];
                NSString* start = args[@"start"];
                NSString* plist = args[@"plist"];
                int status = 0;
                if (plist != nil) {
                    status = spawn(@[getAppEXEPath(), @"load_daemon", plist, start], nil, nil, nil, SPAWN_FLAG_ROOT);
                    if (status != 0) {
                        return replyHandler(@-1, nil);
                    }
                }
                status = spawn(@[getAppEXEPath(), @"start_daemon", label, start], nil, nil, nil, SPAWN_FLAG_ROOT);
                if (status != 0) {
                    return replyHandler(@-2, nil);
                }
                return replyHandler(@0, nil);
            }
        }
    }
}
@end

int main(int argc, char * argv[]) {
    @autoreleasepool {
        if (argc == 1) {
            return UIApplicationMain(argc, argv, nil, @"AppDelegate");
        } else if (argc >= 4) {
            int ret = -1;
            char* cmd = argv[1];
            if (0 == strcmp(cmd, "start_daemon")) {
                bool start = argv[3][0] == '1';
                char* label = argv[2];
                ret = start_cmd(label, start);
            } else if (0 == strcmp(cmd, "load_daemon")) {
                bool start = argv[3][0] == '1';
                char* plist = argv[2];
                ret = load_cmd(plist, start, 0);
            }
            NSLog(@"%@ cmd %s %s %s -> %d", log_prefix, argv[1], argv[2], argv[3], ret);
            return ret;
        }
    }
}

