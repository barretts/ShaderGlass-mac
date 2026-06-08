/*
ShaderGlass macOS port -- main.mm

NSApplication bootstrap. Normal launch opens the live GUI. `--selftest <out.png>`
runs headless: builds the pipeline against a layer-less backend, renders the sample
image offscreen through passthrough, and writes a PNG (auto-verifiable golden,
never touches a drawable / TCC).
*/

#import <Cocoa/Cocoa.h>
#import "SGAppDelegate.h"
#import "LivePipeline.h"

static int runSelftest(NSString* outPath) {
    @autoreleasepool {
        NSString* shaderDir = @"../spike";
        NSString* img = @"../../images/screen6.png";
        // layer-less pipeline (Initialize(nil) => headless backend, present path inert)
        LivePipeline* pipe = [[LivePipeline alloc] initWithLayer:nil width:0 height:0 shaderDir:shaderDir];
        if (!pipe) { fprintf(stderr, "selftest FAIL: pipeline init\n"); return 2; }
        if (![pipe setStaticImagePath:img]) { fprintf(stderr, "selftest FAIL: image load\n"); return 2; }
        if (![pipe renderOffscreenToPNG:outPath]) { fprintf(stderr, "selftest FAIL: offscreen render\n"); return 1; }
        fprintf(stderr, "selftest OK: wrote %s\n", outPath.UTF8String);
        return 0;
    }
}

int main(int argc, const char* argv[]) {
    @autoreleasepool {
        for (int i = 1; i < argc; ++i) {
            if (strcmp(argv[i], "--selftest") == 0 && i + 1 < argc)
                return runSelftest([NSString stringWithUTF8String:argv[i+1]]);
        }
        NSApplication* app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        SGAppDelegate* delegate = [[SGAppDelegate alloc] init];
        app.delegate = delegate;

        // minimal menu bar with Quit (Cmd-Q)
        NSMenu* menubar = [[NSMenu alloc] init];
        NSMenuItem* appItem = [[NSMenuItem alloc] init];
        [menubar addItem:appItem];
        NSMenu* appMenu = [[NSMenu alloc] init];
        [appMenu addItemWithTitle:@"Quit ShaderGlass" action:@selector(terminate:) keyEquivalent:@"q"];
        appItem.submenu = appMenu;
        app.mainMenu = menubar;

        [app run];
    }
    return 0;
}
