#import "include/AirlockObjC.h"

BOOL AirlockSetWindowStyleMask(NSWindow *window,
                                NSUInteger styleMask,
                                NSView **outContentView) {
    // Grab the content view before the style mask change.  The change
    // reconstructs the window's internal frame view, which removes and
    // re-adds subviews.  If the content view is an NSHostingView, the
    // removal triggers -viewWillMove(toWindow:nil) which tries to tear
    // down KVO observers that may not be fully registered yet, throwing
    // an NSException.  We catch that exception and let the caller
    // re-attach the content view afterwards.
    NSView *contentView = window.contentView;
    if (outContentView) {
        *outContentView = contentView;
    }

    @try {
        [window setStyleMask:styleMask];
        return YES;
    } @catch (NSException *exception) {
        // The style mask change partially completed — the new frame
        // view is in place but the content view was not cleanly
        // transferred.  The caller will re-attach it.
        return NO;
    }
}
