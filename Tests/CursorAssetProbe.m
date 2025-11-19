/*
 * CursorAssetProbe.m
 * Validates cursor metadata and asset coverage to catch packaging regressions.
 */

#import <Foundation/Foundation.h>

static void FailAndExit(NSString *message) {
    fprintf(stderr, "%s\n", message.UTF8String ?: "CursorAssetProbe: unknown failure");
    exit(EXIT_FAILURE);
}

static NSString *CursorDirectory(void) {
    NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
    if (cwd.length == 0) {
        FailAndExit(@"CursorAssetProbe: unable to resolve current directory");
    }
    NSString *cursorDir = [cwd stringByAppendingPathComponent:@"Resources/Cursors"];
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:cursorDir isDirectory:&isDirectory] || !isDirectory) {
        FailAndExit([NSString stringWithFormat:@"CursorAssetProbe: missing cursor directory at %@", cursorDir]);
    }
    return cursorDir;
}

static NSString *ResolveCursorFile(NSString *cursorDir, NSString *basename) {
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

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSString *cursorDir = CursorDirectory();
        NSString *metadataPath = [cursorDir stringByAppendingPathComponent:@"markup-cursors.metadata.json"];
        NSData *metadataData = [NSData dataWithContentsOfFile:metadataPath];
        if (!metadataData) {
            FailAndExit([NSString stringWithFormat:@"CursorAssetProbe: failed to read %@", metadataPath]);
        }

        NSError *error = nil;
        id json = [NSJSONSerialization JSONObjectWithData:metadataData options:0 error:&error];
        if (!json || ![json isKindOfClass:[NSArray class]]) {
            FailAndExit([NSString stringWithFormat:@"CursorAssetProbe: metadata JSON invalid (%@)", error]);
        }

        NSArray *entries = (NSArray *)json;
        if (entries.count == 0) {
            FailAndExit(@"CursorAssetProbe: metadata file is empty");
        }

        NSMutableSet<NSString *> *tools = [[NSMutableSet alloc] init];
        for (NSDictionary *entry in entries) {
            if (![entry isKindOfClass:[NSDictionary class]]) {
                FailAndExit(@"CursorAssetProbe: metadata entry is not a dictionary");
            }

            NSString *tool = entry[@"tool"];
            if (![tool isKindOfClass:[NSString class]] || tool.length == 0) {
                FailAndExit(@"CursorAssetProbe: entry missing 'tool'");
            }
            if ([tools containsObject:tool]) {
                FailAndExit([NSString stringWithFormat:@"CursorAssetProbe: duplicate tool '%@'", tool]);
            }
            [tools addObject:tool];

            NSString *file = entry[@"file"];
            if (![file isKindOfClass:[NSString class]] || file.length == 0) {
                FailAndExit([NSString stringWithFormat:@"CursorAssetProbe: tool %@ missing 'file'", tool]);
            }
            NSString *resolvedFile = ResolveCursorFile(cursorDir, file);
            if (!resolvedFile) {
                FailAndExit([NSString stringWithFormat:@"CursorAssetProbe: tool %@ references missing asset '%@.(png|tiff|tif)'",
                             tool, file]);
            }
            NSData *cursorData = [NSData dataWithContentsOfFile:resolvedFile];
            if (!cursorData) {
                FailAndExit([NSString stringWithFormat:@"CursorAssetProbe: unable to read asset %@", resolvedFile]);
            }

            NSNumber *sizeValue = entry[@"size"];
            if (![sizeValue isKindOfClass:[NSNumber class]] || sizeValue.doubleValue <= 0.0) {
                FailAndExit([NSString stringWithFormat:@"CursorAssetProbe: tool %@ missing/invalid 'size'", tool]);
            }

            NSArray *hotspot = entry[@"hotspot"];
            if (![hotspot isKindOfClass:[NSArray class]] || hotspot.count < 2) {
                FailAndExit([NSString stringWithFormat:@"CursorAssetProbe: tool %@ missing hotspot array", tool]);
            }
            NSNumber *hotspotX = hotspot[0];
            NSNumber *hotspotY = hotspot[1];
            if (![hotspotX isKindOfClass:[NSNumber class]] || ![hotspotY isKindOfClass:[NSNumber class]]) {
                FailAndExit([NSString stringWithFormat:@"CursorAssetProbe: tool %@ hotspot entries must be numbers", tool]);
            }
        }

        return EXIT_SUCCESS;
    }
}
