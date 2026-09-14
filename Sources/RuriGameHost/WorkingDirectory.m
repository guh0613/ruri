#import "WorkingDirectory.h"
#include <stdatomic.h>
#include <sys/stat.h>
#include <unistd.h>

static atomic_bool protectedResources;
static dev_t resourceDevice;
static ino_t resourceInode;

void RuriProtectGameWorkingDirectory(void) {
    struct stat resources;
    NSString *path = NSBundle.mainBundle.resourcePath;
    if (path && stat(path.fileSystemRepresentation, &resources) == 0 && S_ISDIR(resources.st_mode)) {
        resourceDevice = resources.st_dev;
        resourceInode = resources.st_ino;
        atomic_store_explicit(&protectedResources, true, memory_order_release);
    }
}

static BOOL isHostResources(const struct stat *directory) {
    return directory->st_dev == resourceDevice && directory->st_ino == resourceInode;
}

static int gameChdir(const char *path) {
    if (atomic_load_explicit(&protectedResources, memory_order_acquire)) {
        int savedError = errno;
        struct stat destination;
        BOOL rebase = stat(path, &destination) == 0 && isHostResources(&destination);
        errno = savedError;
        if (rebase) return 0;
    }
    return chdir(path);
}

static int gameFchdir(int descriptor) {
    if (atomic_load_explicit(&protectedResources, memory_order_acquire)) {
        int savedError = errno;
        struct stat destination;
        BOOL rebase = fstat(descriptor, &destination) == 0 && isHostResources(&destination);
        errno = savedError;
        if (rebase) return 0;
    }
    return fchdir(descriptor);
}

// GLFW 3.2 changes cwd to Contents/Resources without an opt-out API. Java has
// already cached user.dir by then, so repairing cwd after a window notification
// is too late for mods and races their file IO. Reject only the host-resource
// rebase at its source; other directory changes retain their POSIX behavior.
// dyld keeps calls from this image bound to the original functions.
__attribute__((used, section("__DATA,__interpose,interposing")))
static const struct { const void *replacement; const void *original; } directoryInterpositions[] = {
    {(const void *)gameChdir, (const void *)chdir},
    {(const void *)gameFchdir, (const void *)fchdir}
};
