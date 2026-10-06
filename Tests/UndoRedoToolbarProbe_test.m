/*
 * UndoRedoToolbarProbe_test.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * Undo and Redo lead the toolbar (#101): they send undo:/redo: like the Edit menu's items and are
 * enabled exactly when those are.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (UndoRedoToolbarTesting)
- (void)setupWindowAndContent;
- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar;
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)identifier willBeInsertedIntoToolbar:(BOOL)flag;
- (BOOL)validateToolbarItem:(NSToolbarItem *)item;
- (BOOL)validateMenuItem:(NSMenuItem *)item;
- (NSUndoManager *)undoManager;
- (void)undo:(id)sender;
@end

/// Something to undo: a counter the undo manager steps back.
@interface UndoRedoCounter : NSObject
@property (nonatomic, assign) NSInteger value;
- (void)setValueUndoably:(NSNumber *)value withUndoManager:(NSUndoManager *)undoManager;
@end

@implementation UndoRedoCounter
- (void)setValueUndoably:(NSNumber *)value withUndoManager:(NSUndoManager *)undoManager {
    [[undoManager prepareWithInvocationTarget:self] setValueUndoably:@(self.value) withUndoManager:undoManager];
    self.value = value.integerValue;
}
@end

@interface UndoRedoToolbarProbeTests : XCTestCase {
    BOOL _shouldSkip;
    AppDelegate *_appDelegate;
}
@end

@implementation UndoRedoToolbarProbeTests

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
    _appDelegate = nil;
    [super tearDown];
}

- (NSToolbarItem *)itemNamed:(NSString *)identifier {
    return [_appDelegate toolbar:nil itemForItemIdentifier:identifier willBeInsertedIntoToolbar:YES];
}

- (BOOL)menuValidates:(SEL)action {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"" action:action keyEquivalent:@""];
    return [_appDelegate validateMenuItem:item];
}

#if defined(GNUSTEP)
- (void)testUndoAndRedoLeadTheToolbar {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSArray *identifiers = [_appDelegate toolbarDefaultItemIdentifiers:nil];
    XCTAssertEqualObjects([identifiers subarrayWithRange:NSMakeRange(0, 2)],
                          (@[@"com.screenshottool.toolbar.undo", @"com.screenshottool.toolbar.redo"]));
    NSToolbarItem *undo = [self itemNamed:@"com.screenshottool.toolbar.undo"];
    NSToolbarItem *redo = [self itemNamed:@"com.screenshottool.toolbar.redo"];
    XCTAssertEqual(undo.action, @selector(undo:));
    XCTAssertEqual(redo.action, @selector(redo:));
    XCTAssertNotNil(undo.image, @"Undo has its symbolic icon");
    XCTAssertNotNil(redo.image, @"Redo has its symbolic icon");
    XCTAssertEqualObjects(undo.toolTip, @"Undo");
    XCTAssertEqualObjects(redo.toolTip, @"Redo");
}
#endif

- (void)testEnabledExactlyWhenTheEditMenuIs {
    XCTSkipIf(_shouldSkip, @"No window server");
    NSToolbarItem *undo = [self itemNamed:@"com.screenshottool.toolbar.undo"];
    NSToolbarItem *redo = [self itemNamed:@"com.screenshottool.toolbar.redo"];
    NSUndoManager *undoManager = [_appDelegate undoManager];
    [undoManager removeAllActions];
    XCTAssertFalse([_appDelegate validateToolbarItem:undo], @"Nothing to undo");
    XCTAssertFalse([_appDelegate validateToolbarItem:redo], @"Nothing to redo");

    UndoRedoCounter *counter = [[UndoRedoCounter alloc] init];
    [undoManager setGroupsByEvent:NO];
    [undoManager beginUndoGrouping];
    [counter setValueUndoably:@1 withUndoManager:undoManager];
    [undoManager endUndoGrouping];
    XCTAssertTrue([_appDelegate validateToolbarItem:undo]);
    XCTAssertFalse([_appDelegate validateToolbarItem:redo]);
    XCTAssertEqual([_appDelegate validateToolbarItem:undo], [self menuValidates:@selector(undo:)]);

    [_appDelegate undo:undo];
    XCTAssertEqual(counter.value, 0, @"The toolbar's Undo undoes");
    XCTAssertFalse([_appDelegate validateToolbarItem:undo]);
    XCTAssertTrue([_appDelegate validateToolbarItem:redo]);
    XCTAssertEqual([_appDelegate validateToolbarItem:redo], [self menuValidates:@selector(redo:)]);
    [undoManager setGroupsByEvent:YES];
}

@end
