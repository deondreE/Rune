#include "editor.hpp"
#import <Cocoa/Cocoa.h>
Editor editor;

@interface RuneInputView : NSView
@end

@implementation RuneInputView
- (BOOL)acceptsFirstResponder { return YES; }
- (void)keyDown:(NSEvent *)event {
    NSString *chars = [event charactersIgnoringModifiers];
    if ([chars length] > 0) {
        char c = [chars characterAtIndex:0];
        
        // 127 is the standard macOS Backspace/Delete key code
        if (c == 127 || c == 8) {
            editor.handle_backspace();
        } 
        // 13 is Return, 3 is Enter
        else if (c == 13 || c == 3) { 
            editor.handle_input_buffer('\n');
        } 
        // Printable ASCII
        else if (c >= 32 && c <= 126) {
            editor.handle_input_buffer(c);
        }
        // Tabs
        else if (c == 9) {
            // Insert 4 spaces or a \t
            for(int i = 0; i < 4; ++i) editor.handle_input_buffer(' ');
        }
    }
}
@end

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property (strong) NSWindow* window;
@end

@implementation AppDelegate 

- (void)applicationDidFinishLaunching:(NSNotification*)aNotification {
    NSRect frame = NSMakeRect(0, 0, 1280, 720);
    NSUInteger styleMask = NSWindowStyleMaskTitled | 
                           NSWindowStyleMaskClosable | 
                           NSWindowStyleMaskResizable | 
                           NSWindowStyleMaskMiniaturizable;

    self.window = [[NSWindow alloc] initWithContentRect:frame
                                            styleMask:styleMask
                                              backing:NSBackingStoreBuffered
                                                defer:NO];

    RuneInputView* inputView =  [[RuneInputView alloc] initWithFrame:frame];
    [self.window setContentView:inputView];
    [self.window makeFirstResponder:inputView];

    [self.window setTitle:@"Rune Editor"];
    [self.window center];
    [self.window setAcceptsMouseMovedEvents:YES];
    [self.window setRestorable:YES];
    [self setupMenuBar];

    WindowHandle handle;
    handle.native_handle = (__bridge void*)self.window;
    editor.initialize(handle, "");

    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    [self.window setDelegate:self];

    // Drive the render loop at ~60 fps
    [NSTimer scheduledTimerWithTimeInterval:1.0 / 60.0
                                     target:self
                                   selector:@selector(renderFrame:)
                                   userInfo:nil
                                    repeats:YES];

    printf("Cocoa Window Initialized.\n");
}

- (void)setupMenuBar {
    NSMenu* mainMenu = [[NSMenu alloc] init];
    [NSApp setMainMenu:mainMenu];

    NSMenuItem* appMenuItem = [mainMenu addItemWithTitle:@"App" action:nil keyEquivalent:@""];
    NSMenu* appMenu = [[NSMenu alloc] init];
    [appMenuItem setSubmenu:appMenu];

    NSString* quitTitle = [@"Quit " stringByAppendingString:@"Rune"];
    NSMenuItem* quitMenuItem = [appMenu addItemWithTitle:quitTitle
                                        action:@selector(terminate:)
                                    keyEquivalent:@"q"];

    [quitMenuItem setTarget:NSApp];
}

- (void)renderFrame:(NSTimer*)timer {
    editor.update();
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}


@end

int main(int argc, const char * argv[])
{
    @autoreleasepool {
        NSApplication* app = [NSApplication sharedApplication];

        [app setActivationPolicy:NSApplicationActivationPolicyRegular];

        AppDelegate* delegate = [[AppDelegate alloc] init];
        [app setDelegate:delegate];

        // Your editor setup logic here
        printf("Running on macOS\n");
        [app run];
    }
    return 0; 
}