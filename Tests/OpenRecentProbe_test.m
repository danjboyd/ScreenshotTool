/*
 * OpenRecentProbe_test.m
 * Verifies the File > Open Recent submenu persists and refreshes correctly.
 */

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScreenshotToolSettings.h"
#import "TestEnvironmentHelpers.h"

@interface AppDelegate (OpenRecentTesting)
- (void)setupMenus;
- (void)addRecentDocumentURL:(NSURL *)url;
- (void)clearRecentDocuments:(id)sender;
- (NSMenu *)openRecentMenu;
@end

@interface OpenRecentProbeTests : XCTestCase {
    AppDelegate *_appDelegate;
    NSString *_tempRoot;
}
@end

@implementation OpenRecentProbeTests

+ (void)load {
    STConfigureTestDefaults();
}

- (void)setUp {
    [super setUp];
    [NSApplication sharedApplication];

    [[NSUserDefaults standardUserDefaults] removeObjectForKey:STDefaultsRecentDocumentsKey];

    _tempRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    NSError *error = nil;
    BOOL created = [[NSFileManager defaultManager] createDirectoryAtPath:_tempRoot
                                             withIntermediateDirectories:YES
                                                              attributes:nil
                                                                   error:&error];
    XCTAssertTrue(created, @"Failed to create temp root: %@", error);

    _appDelegate = [[AppDelegate alloc] init];
    [_appDelegate setupMenus];
}

- (void)tearDown {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:STDefaultsRecentDocumentsKey];
    if (_tempRoot.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:_tempRoot error:NULL];
    }
    _appDelegate = nil;
    [super tearDown];
}

- (NSString *)createRecentDocumentNamed:(NSString *)name inSubdirectory:(NSString *)subdirectory {
    NSString *directory = [_tempRoot stringByAppendingPathComponent:subdirectory];
    NSError *error = nil;
    BOOL created = [[NSFileManager defaultManager] createDirectoryAtPath:directory
                                             withIntermediateDirectories:YES
                                                              attributes:nil
                                                                   error:&error];
    XCTAssertTrue(created, @"Failed to create %@: %@", directory, error);

    NSString *path = [directory stringByAppendingPathComponent:name];
    NSData *data = [@"stub" dataUsingEncoding:NSUTF8StringEncoding];
    BOOL wrote = [data writeToFile:path options:NSDataWritingAtomic error:&error];
    XCTAssertTrue(wrote, @"Failed to write %@: %@", path, error);
    return [path stringByStandardizingPath];
}

- (void)testRecentDocumentsPersistInMostRecentOrder {
    NSString *alpha = [self createRecentDocumentNamed:@"capture.png" inSubdirectory:@"alpha"];
    NSString *beta = [self createRecentDocumentNamed:@"capture.png" inSubdirectory:@"beta"];

    [_appDelegate addRecentDocumentURL:[NSURL fileURLWithPath:alpha]];
    [_appDelegate addRecentDocumentURL:[NSURL fileURLWithPath:beta]];
    [_appDelegate addRecentDocumentURL:[NSURL fileURLWithPath:alpha]];

    NSArray<NSString *> *storedPaths = [[NSUserDefaults standardUserDefaults] arrayForKey:STDefaultsRecentDocumentsKey];
    XCTAssertEqualObjects(storedPaths, (@[ alpha, beta ]), @"Recent documents should deduplicate and move reopened files to the front");

    NSMenu *menu = [_appDelegate openRecentMenu];
    XCTAssertNotNil(menu, @"Open Recent submenu should exist");
    XCTAssertEqual(menu.numberOfItems, 4, @"Two recent files should render two entries plus separator and clear item");

    NSMenuItem *firstItem = [menu itemAtIndex:0];
    NSMenuItem *secondItem = [menu itemAtIndex:1];
    XCTAssertEqualObjects(firstItem.representedObject, alpha);
    XCTAssertEqualObjects(secondItem.representedObject, beta);
    XCTAssertTrue([[firstItem title] hasPrefix:@"capture.png ("], @"Duplicate basenames should include directory context");
    XCTAssertTrue([[secondItem title] hasPrefix:@"capture.png ("], @"Duplicate basenames should include directory context");
    XCTAssertTrue([[menu itemAtIndex:2] isSeparatorItem], @"Open Recent should separate document entries from the clear action");
    XCTAssertEqualObjects([[menu itemAtIndex:3] title], @"Clear Menu");
}

- (void)testClearRecentDocumentsRestoresEmptyPlaceholder {
    NSString *alpha = [self createRecentDocumentNamed:@"capture.png" inSubdirectory:@"alpha"];
    [_appDelegate addRecentDocumentURL:[NSURL fileURLWithPath:alpha]];

    [_appDelegate clearRecentDocuments:nil];

    NSArray<NSString *> *storedPaths = [[NSUserDefaults standardUserDefaults] arrayForKey:STDefaultsRecentDocumentsKey];
    XCTAssertTrue(storedPaths.count == 0, @"Clear Menu should remove persisted recent documents");

    NSMenu *menu = [_appDelegate openRecentMenu];
    XCTAssertEqual(menu.numberOfItems, 1, @"Empty recent menu should collapse to the placeholder item");
    NSMenuItem *placeholder = [menu itemAtIndex:0];
    XCTAssertEqualObjects(placeholder.title, @"No Recent Documents");
    XCTAssertFalse(placeholder.isEnabled, @"Placeholder item should not be selectable");
}

@end
