
#import <Foundation/Foundation.h>

NSString* ns_2_json(id nsobj);
id json_2_ns(NSString* s);
void alert(NSString* title, NSString* msg, int tmout, BOOL canCancel, void(^cb)(BOOL ok));
void prompt(NSString* title, NSString* msg, NSString* hint, void(^cb)(NSString* text)) ;

int32_t get_mem_limit(int pid);
int set_memory_limit(int pid, int mb);
