#import <AppKit/AppKit.h>
#import "HostProtocol.h"

@interface RuriGameApplication : NSObject
- (instancetype)initWithRequest:(NSDictionary *)request channel:(RuriHostChannel *)channel;
- (void)observe;
@end
