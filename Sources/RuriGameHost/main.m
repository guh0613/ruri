#import "HostProtocol.h"
#import "GameApplication.h"
#import "WorkingDirectory.h"
#include <dlfcn.h>
#include <unistd.h>

// OpenJDK libjli launcher ABI (Java 8+). The selected runtime remains external.
typedef int (*LaunchJava)(int, char **, int, const char **, int, const char **,
                         const char *, const char *, const char *, const char *,
                         unsigned char, unsigned char, unsigned char, int);
static LaunchJava launchJava;
static const char *javaVersion;
static RuriHostChannel *channel;
static RuriGameApplication *application;

static int runJava(int argc, char **argv) {
    return launchJava(argc, argv, 0, NULL, 0, NULL, javaVersion, javaVersion, "java", "java", 0, 1, 0, 0);
}
static char **arguments(NSString *executable, NSArray *values) {
    char **result = calloc(values.count + 2, sizeof(char *));
    if (!result) return NULL;
    result[0] = strdup(executable.fileSystemRepresentation);
    for (NSUInteger i = 0; i < values.count; i++) result[i + 1] = strdup([values[i] UTF8String]);
    for (NSUInteger i = 0; i <= values.count; i++) {
        if (!result[i]) { for (NSUInteger j = 0; j <= values.count; j++) free(result[j]); free(result); return NULL; }
    }
    return result;
}
static int fail(NSString *code) {
    [channel send:@"failed" fields:@{@"code": code}];
    return 125;
}
static int fallback(NSDictionary *request, NSString *reason) {
    [channel send:@"fallback" fields:@{@"code": reason}];
    char **args = arguments(request[@"javaExecutable"], request[@"directArguments"]);
    if (!args) return fail(@"allocation");
    execv(args[0], args);
    return fail(@"javaExec");
}

int main(int argc, char **argv) {
    // macOS libjli parks the primordial thread and reenters main on a launcher
    // thread. Bootstrap input must be consumed once; preserve its Java argv.
    if (launchJava) return runJava(argc, argv);
    @autoreleasepool {
        if (argc != 2 || strcmp(argv[1], "run")) return 64;
        channel = [[RuriHostChannel alloc] initFromStandardInput];
        if (!channel) return 125;
        NSDictionary *request = channel.request;
        for (NSString *key in @[@"javaExecutable", @"jliLibrary", @"directory"]) {
            if (!RuriHostString(request[key], 32768) || ![request[key] hasPrefix:@"/"]) return fail(@"request");
        }
        if (!RuriHostString(request[@"name"], 32768) || !RuriHostString(request[@"javaVersion"], 256) ||
            !RuriHostArguments(request[@"arguments"]) || !RuriHostArguments(request[@"directArguments"])) return fail(@"request");
        for (NSString *key in @[@"instanceAppearance", @"nativeFullscreen"]) {
            if (![request[key] isKindOfClass:NSNumber.class]) return fail(@"request");
        }
        if (chdir([request[@"directory"] fileSystemRepresentation])) return fail(@"directory");
        RuriProtectGameWorkingDirectory();
        [channel send:@"ready" fields:nil];
        void *library = dlopen([request[@"jliLibrary"] fileSystemRepresentation], RTLD_NOW | RTLD_GLOBAL);
        if (!library) return fallback(request, @"runtimeLoad");
        LaunchJava launch = (LaunchJava)dlsym(library, "JLI_Launch");
        if (!launch) { dlclose(library); return fallback(request, @"runtimeEntry"); }
        char **javaArgv = arguments(request[@"javaExecutable"], request[@"arguments"]);
        javaVersion = strdup([request[@"javaVersion"] UTF8String]);
        if (!javaArgv || !javaVersion) return fail(@"allocation");
        application = [[RuriGameApplication alloc] initWithRequest:request channel:channel];
        [application observe];
        [channel send:@"jvmStarting" fields:nil];
        launchJava = launch;
        // No retry beyond this boundary: game code may already have run.
        return runJava((int)[request[@"arguments"] count] + 1, javaArgv);
    }
}
