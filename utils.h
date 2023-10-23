
#import <Foundation/Foundation.h>

NSString* ns_2_json(id nsobj);
id json_2_ns(NSString* s);
int alert(NSString* title, NSString* msg, int tmout, void(^on_ok)());

