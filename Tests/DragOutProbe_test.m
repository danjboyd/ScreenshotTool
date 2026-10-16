/*
 * DragOutProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * The Copy toolbar button on GNUstep: a click copies, a drag of 4 points or more hands the
 * image out as a file (the export the drag carries), and a twitch under that is still a click.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (DragOutTesting) <NSToolbarDelegate>
- (void)setupWindowAndContent;
@end

/// The private button's provider, as AppDelegate sets it.
@interface NSButton (DragOutTesting)
@property (nonatomic, copy, nullable) NSURL * _Nullable (^dragFileProvider)(void);
@end

@interface DragOutClickRecorder : NSObject
@property (nonatomic, assign) NSInteger clicks;
- (void)clicked:(id)sender;
@end

@implementation DragOutClickRecorder
- (void)clicked:(id)sender {
    (void)sender;
    self.clicks += 1;
}
@end

@interface DragOutProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_appDelegate;
    NSWindow *_window;
}
@end

@implementation DragOutProbeTests

+ (void)load {
    STConfigureTestDefaults();
}

- (void)setUp {
    [super setUp];
    _shouldSkip = NO;
    @try {
        [NSApplication sharedApplication];
        _appDelegate = [[AppDelegate alloc] init];
        [_appDelegate setupWindowAndContent];
    } @catch (NSException *exception) {
        NSLog(@"Skipping test: failed to connect to window server (%@)", [exception reason]);
        _shouldSkip = YES;
    }
}

- (void)tearDown {
    [_window orderOut:nil];
    _window = nil;
    _appDelegate = nil;
    [super tearDown];
}

/// The Copy item's button, in a window of its own, enabled, sent to `recorder`.
- (NSButton *)copyButtonWithRecorder:(DragOutClickRecorder *)recorder {
    NSToolbarItem *item = [_appDelegate toolbar:nil
                          itemForItemIdentifier:@"com.screenshottool.toolbar.copy"
                      willBeInsertedIntoToolbar:YES];
    NSButton *button = (NSButton *)item.view;
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 300, 120)
                                          styleMask:NSTitledWindowMask
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    [button setFrameOrigin:NSMakePoint(50, 40)];
    [_window.contentView addSubview:button];
    button.enabled = YES;
    button.target = recorder;
    button.action = @selector(clicked:);
    return button;
}

- (NSEvent *)mouse:(NSEventType)type at:(NSPoint)point in:(NSView *)view {
    return [NSEvent mouseEventWithType:type
                              location:[view convertPoint:point toView:nil]
                         modifierFlags:0
                             timestamp:0
                          windowNumber:[view.window windowNumber]
                               context:nil
                           eventNumber:0
                            clickCount:1
                              pressure:1.0];
}

#if defined(GNUSTEP)
- (void)testCopyDragsTheImageOut {
    XCTSkipIf(_shouldSkip, @"No window server");
    DragOutClickRecorder *recorder = [[DragOutClickRecorder alloc] init];
    NSButton *button = [self copyButtonWithRecorder:recorder];
    XCTAssertEqualObjects(NSStringFromClass([button class]), @"STDragExportButton", @"Copy drags out on GNUstep too");
    XCTAssertNotNil(button.dragFileProvider, @"With the export it drags");

    NSPoint middle = NSMakePoint(NSMidX(button.bounds), NSMidY(button.bounds));
    [button mouseDown:[self mouse:NSLeftMouseDown at:middle in:button]];
    [button mouseUp:[self mouse:NSLeftMouseUp at:middle in:button]];
    XCTAssertEqual(recorder.clicks, 1, @"A click copies");

    __block NSInteger exports = 0;
    button.dragFileProvider = ^NSURL * {
        exports += 1;
        return nil; // No file: nothing is dragged, and the test needn't drop anything.
    };
    [button mouseDown:[self mouse:NSLeftMouseDown at:middle in:button]];
    [button mouseDragged:[self mouse:NSLeftMouseDragged at:NSMakePoint(middle.x + 2.0, middle.y) in:button]];
    [button mouseUp:[self mouse:NSLeftMouseUp at:NSMakePoint(middle.x + 2.0, middle.y) in:button]];
    XCTAssertEqual(exports, 0, @"A twitch under 4 points isn't a drag");
    XCTAssertEqual(recorder.clicks, 2, @"It's still a click");

    [button mouseDown:[self mouse:NSLeftMouseDown at:middle in:button]];
    [button mouseDragged:[self mouse:NSLeftMouseDragged at:NSMakePoint(middle.x + 12.0, middle.y) in:button]];
    [button mouseUp:[self mouse:NSLeftMouseUp at:NSMakePoint(middle.x + 12.0, middle.y) in:button]];
    XCTAssertEqual(exports, 1, @"A drag exports the image to drag it");
    XCTAssertEqual(recorder.clicks, 2, @"and doesn't copy");

    [button mouseDown:[self mouse:NSLeftMouseDown at:middle in:button]];
    [button mouseUp:[self mouse:NSLeftMouseUp at:NSMakePoint(NSMaxX(button.bounds) + 40.0, middle.y) in:button]];
    XCTAssertEqual(recorder.clicks, 2, @"Released off the button: nothing");
}
#endif

@end
