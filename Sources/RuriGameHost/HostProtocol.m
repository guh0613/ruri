#import "HostProtocol.h"
#include <arpa/inet.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>
#include <dispatch/dispatch.h>

BOOL RuriHostString(id value, NSUInteger maximum) {
    return [value isKindOfClass:NSString.class] && [value lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= maximum &&
        [value rangeOfString:[NSString stringWithCharacters:(unichar[]){0} length:1]].location == NSNotFound;
}
BOOL RuriHostArguments(id value) {
    if (![value isKindOfClass:NSArray.class] || [value count] > 32768) return NO;
    for (id item in value) if (!RuriHostString(item, RuriHostMaximumRequest)) return NO;
    return YES;
}

static BOOL readBytes(int fd, void *buffer, size_t size, double deadline) {
    size_t offset = 0;
    while (offset < size) {
        double remaining = deadline - NSProcessInfo.processInfo.systemUptime;
        if (remaining <= 0) return NO;
        struct pollfd item = {.fd = fd, .events = POLLIN};
        int result = poll(&item, 1, (int)(remaining * 1000));
        if (result < 0 && errno == EINTR) continue;
        if (result <= 0) return NO;
        ssize_t count = read(fd, (char *)buffer + offset, size - offset);
        if (count < 0 && (errno == EINTR || errno == EAGAIN)) continue;
        if (count <= 0) return NO;
        offset += (size_t)count;
    }
    return YES;
}

@implementation RuriHostChannel {
    int _descriptor;
    NSString *_sessionID;
    dispatch_source_t _parentExit;
}
- (instancetype)initFromStandardInput {
    self = [super init];
    if (!self) return nil;
    _descriptor = -1;
    int socketType = 0;
    socklen_t size = sizeof(socketType);
    if (getsockopt(STDIN_FILENO, SOL_SOCKET, SO_TYPE, &socketType, &size) || socketType != SOCK_STREAM) return nil;
    uint32_t length;
    double deadline = NSProcessInfo.processInfo.systemUptime + 30;
    if (!readBytes(STDIN_FILENO, &length, sizeof(length), deadline)) return nil;
    length = ntohl(length);
    if (!length || length > RuriHostMaximumRequest) return nil;
    NSMutableData *data = [NSMutableData dataWithLength:length];
    if (!readBytes(STDIN_FILENO, data.mutableBytes, length, deadline)) return nil;
    id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![value isKindOfClass:NSDictionary.class] || ![value[@"version"] isEqual:@(RuriHostProtocolVersion)] ||
        !RuriHostString(value[@"sessionID"], 36) || ![[NSUUID alloc] initWithUUIDString:value[@"sessionID"]]) return nil;
    _request = value;
    _sessionID = value[@"sessionID"];
    _descriptor = fcntl(STDIN_FILENO, F_DUPFD_CLOEXEC, 3);
    if (_descriptor < 0) return nil;
    int flag = 1;
    setsockopt(_descriptor, SOL_SOCKET, SO_NOSIGPIPE, &flag, sizeof(flag));
    // Java and mods see the same null stdin as a conventional Ruri launch.
    int nullInput = open("/dev/null", O_RDONLY | O_CLOEXEC);
    if (nullInput < 0 || dup2(nullInput, STDIN_FILENO) < 0) {
        if (nullInput >= 0) close(nullInput);
        [self close]; return nil;
    }
    close(nullInput);
    // If the supervisor disappears, stop sending output into its abandoned
    // pipes. No JVM signal handlers or crash hooks are replaced. This source
    // sleeps in the kernel for the entire normal game lifetime.
    pid_t parent = getppid();
    if (parent > 1) {
        _parentExit = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, (uintptr_t)parent, DISPATCH_PROC_EXIT,
                                             dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
        dispatch_source_set_event_handler(_parentExit, ^{
            int sink = open("/dev/null", O_WRONLY | O_CLOEXEC);
            if (sink >= 0) { dup2(sink, STDOUT_FILENO); dup2(sink, STDERR_FILENO); close(sink); }
        });
        dispatch_resume(_parentExit);
    }
    return self;
}
- (void)send:(NSString *)event fields:(NSDictionary *)fields {
    @synchronized(self) {
        if (_descriptor < 0) return;
        NSMutableDictionary *payload = [NSMutableDictionary dictionaryWithDictionary:fields ?: @{}];
        [payload addEntriesFromDictionary:@{@"version": @(RuriHostProtocolVersion), @"sessionID": _sessionID,
                                           @"pid": @(getpid()), @"event": event}];
        NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
        if (!data || data.length > 65536) return;
        uint32_t length = htonl((uint32_t)data.length);
        NSMutableData *frame = [NSMutableData dataWithBytes:&length length:sizeof(length)];
        [frame appendData:data];
        // Telemetry must never stall the game if its monitor dies or stops reading.
        ssize_t count;
        do { count = send(_descriptor, frame.bytes, frame.length, MSG_DONTWAIT); } while (count < 0 && errno == EINTR);
        if (count != (ssize_t)frame.length) [self close];
    }
}
- (void)close {
    @synchronized(self) { if (_descriptor >= 0) { close(_descriptor); _descriptor = -1; } }
}
- (void)dealloc { if (_parentExit) dispatch_source_cancel(_parentExit); [self close]; }
@end
