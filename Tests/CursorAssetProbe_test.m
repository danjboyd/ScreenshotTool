/*
 * CursorAssetProbe_test.m
 * Validates cursor metadata and asset coverage to catch packaging regressions.
 */

#import <XCTest/XCTest.h>

@interface CursorAssetProbeTests : XCTestCase
@end

@implementation CursorAssetProbeTests

- (NSString *)cursorDirectory {
    NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
    XCTAssertTrue(cwd.length > 0, @"Unable to resolve current directory");

    NSString *cursorDir = [cwd stringByAppendingPathComponent:@"Resources/Cursors"];
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:cursorDir isDirectory:&isDirectory] || !isDirectory) {
        XCTFail(@"Missing cursor directory at %@", cursorDir);
        return nil; // Stop test
    }
    return cursorDir;
}

- (NSString *)resolveCursorFile:(NSString *)cursorDir basename:(NSString *)basename {
    NSArray<NSString *> *extensions = @[ @"png", @"tiff", @"tif" ];
    for (NSString *ext in extensions) {
        NSString *candidate = [cursorDir stringByAppendingPathComponent:
                               [NSString stringWithFormat:@"%@.%@", basename, ext]];
        BOOL isDirectory = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:candidate isDirectory:&isDirectory] && !isDirectory) {
            return candidate;
        }
    }
    return nil;
}

- (void)testCursorAssetsAndMetadata {
    NSString *cursorDir = [self cursorDirectory];
    if (!cursorDir) return; // Failures already logged in helper

    NSString *metadataPath = [cursorDir stringByAppendingPathComponent:@"markup-cursors.metadata.json"];
    NSData *metadataData = [NSData dataWithContentsOfFile:metadataPath];
    XCTAssertNotNil(metadataData, @"Failed to read %@", metadataPath);

    NSError *error = nil;
    id json = [NSJSONSerialization JSONObjectWithData:metadataData options:0 error:&error];
    XCTAssertNotNil(json, @"Metadata JSON is invalid: %@", error);
    XCTAssertTrue([json isKindOfClass:[NSArray class]], @"Metadata JSON should be an array");

    NSArray *entries = (NSArray *)json;
    XCTAssertTrue(entries.count > 0, @"Metadata file is empty");

    NSMutableSet<NSString *> *tools = [[NSMutableSet alloc] init];
    for (id entryObj in entries) {
        XCTAssertTrue([entryObj isKindOfClass:[NSDictionary class]], @"Metadata entry is not a dictionary");
        NSDictionary *entry = (NSDictionary *)entryObj;

        NSString *tool = entry[@"tool"];
        XCTAssertTrue([tool isKindOfClass:[NSString class]] && tool.length > 0, @"Entry missing 'tool'");
        XCTAssertFalse([tools containsObject:tool], @"Duplicate tool '%@'", tool);
        [tools addObject:tool];

        NSString *file = entry[@"file"];
        XCTAssertTrue([file isKindOfClass:[NSString class]] && file.length > 0, @"Tool %@ missing 'file'", tool);
        
        NSString *resolvedFile = [self resolveCursorFile:cursorDir basename:file];
        XCTAssertNotNil(resolvedFile, @"Tool %@ references missing asset '%@.(png|tiff|tif)'", tool, file);

        NSData *cursorData = [NSData dataWithContentsOfFile:resolvedFile];
        XCTAssertNotNil(cursorData, @"Unable to read asset %@", resolvedFile);

        NSNumber *sizeValue = entry[@"size"];
        XCTAssertTrue([sizeValue isKindOfClass:[NSNumber class]] && sizeValue.doubleValue > 0.0, @"Tool %@ missing/invalid 'size'", tool);

        id hotspotObj = entry[@"hotspot"];
        XCTAssertTrue([hotspotObj isKindOfClass:[NSArray class]], @"Tool %@ missing hotspot array", tool);
        NSArray *hotspot = (NSArray *)hotspotObj;
        XCTAssertTrue(hotspot.count >= 2, @"Tool %@ hotspot array should have at least 2 elements", tool);
        
        XCTAssertTrue([hotspot[0] isKindOfClass:[NSNumber class]], @"Tool %@ hotspot X must be a number", tool);
        XCTAssertTrue([hotspot[1] isKindOfClass:[NSNumber class]], @"Tool %@ hotspot Y must be a number", tool);
    }
}

@end
