#import "GameApplication.h"
#import <ImageIO/ImageIO.h>

static char titleObservation, iconObservation;

@implementation RuriGameApplication {
    NSString *_name;
    NSImage *_icon;
    BOOL _appearance;
    BOOL _fullscreenRequested;
    BOOL _windowReported;
    NSWindow *_gameWindow;
    BOOL _observingTitle;
    BOOL _observingIcon;
    BOOL _updatingAppearance;
    RuriHostChannel *_channel;
    NSMutableArray *_observers;
    id _discoveryObserver;
}
- (instancetype)initWithRequest:(NSDictionary *)request channel:(RuriHostChannel *)channel {
    self = [super init];
    if (self) {
        _name = request[@"name"];
        _appearance = [request[@"instanceAppearance"] boolValue];
        _fullscreenRequested = [request[@"nativeFullscreen"] boolValue];
        _channel = channel;
        _observers = [NSMutableArray array];
        NSString *encoded = request[@"iconPNG"];
        if (_appearance && RuriHostString(encoded, 720000)) {
            NSData *data = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
            CGImageSourceRef source = data ? CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL) : NULL;
            if (source) {
                NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
                NSUInteger width = [properties[(__bridge NSString *)kCGImagePropertyPixelWidth] unsignedIntegerValue];
                NSUInteger height = [properties[(__bridge NSString *)kCGImagePropertyPixelHeight] unsignedIntegerValue];
                if (width > 0 && height > 0 && width <= 1024 && height <= 1024) _icon = [[NSImage alloc] initWithData:data];
                CFRelease(source);
            }
        }
    }
    return self;
}
- (void)observe {
    // GLFW and AWT retain ownership of NSApplication, its delegate and event loop.
    // Observe their windows instead of replacing framework delegates or methods.
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    __weak typeof(self) weakSelf = self;
    for (NSNotificationName notification in @[NSWindowDidBecomeKeyNotification, NSWindowDidBecomeMainNotification, NSWindowDidResizeNotification]) {
        [_observers addObject:[center addObserverForName:notification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            [weakSelf windowAvailable:note.object];
        }]];
    }
    // A window can first become key while still hidden or at its bootstrap size.
    // Discover it on a later AppKit update; remove this observer once it is ready.
    _discoveryObserver = [center addObserverForName:NSApplicationDidUpdateNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        (void)note;
        for (NSWindow *window in NSApp.windows) [weakSelf windowAvailable:window];
    }];
    for (NSNotificationName notification in @[NSWindowDidEnterFullScreenNotification, NSWindowDidExitFullScreenNotification]) {
        [_observers addObject:[center addObserverForName:notification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            typeof(self) self = weakSelf;
            if (self && note.object == self->_gameWindow) {
                [self->_channel send:@"fullscreen" fields:@{@"value": @([notification isEqualToString:NSWindowDidEnterFullScreenNotification])}];
            }
        }]];
    }
    [_observers addObject:[center addObserverForName:NSWindowWillCloseNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        typeof(self) self = weakSelf;
        if (self && note.object == self->_gameWindow) [self detachWindow];
    }]];
}
- (void)detachWindow {
    if (_observingTitle) [_gameWindow removeObserver:self forKeyPath:@"title" context:&titleObservation];
    _observingTitle = NO;
    _gameWindow = nil;
}
- (void)applyAppearance {
    if (!_appearance || _updatingAppearance) return;
    _updatingAppearance = YES;
    if (_gameWindow && ![_gameWindow.title isEqualToString:_name] &&
        ![_gameWindow.title hasPrefix:[_name stringByAppendingString:@" — "]]) {
        _gameWindow.title = _gameWindow.title.length ? [NSString stringWithFormat:@"%@ — %@", _name, _gameWindow.title] : _name;
    }
    if (_icon && NSApp.applicationIconImage != _icon) NSApp.applicationIconImage = _icon;
    _updatingAppearance = NO;
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == &titleObservation || context == &iconObservation) {
        // AppKit updates belong to its main thread, including changes from mods.
        if (NSThread.isMainThread) [self applyAppearance];
        else dispatch_async(dispatch_get_main_queue(), ^{ [self applyAppearance]; });
    } else [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}
- (void)windowAvailable:(NSWindow *)window {
    if (![window isKindOfClass:NSWindow.class] || [window isKindOfClass:NSPanel.class] ||
        !window.visible || window.contentView.bounds.size.width < 300 || window.contentView.bounds.size.height < 200) return;
    if (_gameWindow && _gameWindow != window && _gameWindow.visible) return;
    if (_gameWindow != window) {
        [self detachWindow];
        _gameWindow = window;
        if (_appearance) {
            [window addObserver:self forKeyPath:@"title" options:0 context:&titleObservation];
            _observingTitle = YES;
        }
    }
    if (_appearance) {
        if (_icon && !_observingIcon) {
            [NSApp addObserver:self forKeyPath:@"applicationIconImage" options:0 context:&iconObservation];
            _observingIcon = YES;
        }
        [self applyAppearance];
    }
    if (!_windowReported) {
        _windowReported = YES;
        if (_discoveryObserver) {
            [NSNotificationCenter.defaultCenter removeObserver:_discoveryObserver];
            _discoveryObserver = nil;
        }
        [_channel send:@"windowReady" fields:nil];
        if (_fullscreenRequested) {
            // Run after GLFW finishes the current window setup / event callback.
            dispatch_async(dispatch_get_main_queue(), ^{
                if (window.visible && !(window.styleMask & NSWindowStyleMaskFullScreen)) {
                    window.collectionBehavior |= NSWindowCollectionBehaviorFullScreenPrimary;
                    [window toggleFullScreen:nil];
                }
            });
        }
    }
}
- (void)dealloc {
    [self detachWindow];
    if (_observingIcon) [NSApp removeObserver:self forKeyPath:@"applicationIconImage" context:&iconObservation];
    if (_discoveryObserver) [NSNotificationCenter.defaultCenter removeObserver:_discoveryObserver];
    for (id token in _observers) [NSNotificationCenter.defaultCenter removeObserver:token];
}
@end
