#import <Foundation/Foundation.h>

// Keep native libraries from rebasing relative game paths into the host bundle.
void RuriProtectGameWorkingDirectory(void);
