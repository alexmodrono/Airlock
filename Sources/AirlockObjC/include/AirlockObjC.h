#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

/// Attempts to set the window's style mask, catching any NSException that
/// AppKit throws when NSHostingView's KVO observers are torn down during
/// the frame-view reconstruction.  Returns YES on success.
///
/// After catching, the caller should re-assign the content view because
/// the failed removal may have left it detached.
BOOL AirlockSetWindowStyleMask(NSWindow *_Nonnull window,
                                NSUInteger styleMask,
                                NSView *_Nullable *_Nullable outContentView);
