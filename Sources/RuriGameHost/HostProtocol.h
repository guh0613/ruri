#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
enum { RuriHostProtocolVersion = 1, RuriHostMaximumRequest = 4 * 1024 * 1024 };

@interface RuriHostChannel : NSObject
@property(nonatomic, readonly) NSDictionary *request;
- (nullable instancetype)initFromStandardInput;
- (void)send:(NSString *)event fields:(nullable NSDictionary *)fields;
- (void)close;
@end

BOOL RuriHostString(id value, NSUInteger maximum);
BOOL RuriHostArguments(id value);
NS_ASSUME_NONNULL_END
