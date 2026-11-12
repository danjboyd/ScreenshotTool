#import "STPrintPDF.h"

#if defined(__linux__)

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#import <GNUstepGUI/GSPDFPrintOperation.h>
#import "STPrintPage.h"
#import "STPrintPanelController.h"
#import "ScreenshotCanvasView.h"

/// One sheet-sized page at a time: the operation asks for a page's rect, then draws the view in it.
@interface STPrintPDFView : NSView
@property (nonatomic, strong) STPrintLayout *layout;
@property (nonatomic, strong) NSImage *image;
@property (nonatomic) NSUInteger page;
@property (nonatomic) BOOL drewEveryPage;
@end

@implementation STPrintPDFView

- (BOOL)knowsPageRange:(NSRangePointer)range {
    *range = NSMakeRange(1, self.layout.pageCount);
    return YES;
}

- (NSRect)rectForPage:(NSInteger)page {
    self.page = (NSUInteger)(page - 1);
    return self.bounds;
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    if (!STDrawPrintPage(self.layout, self.page, self.image, NO)) {
        self.drewEveryPage = NO;
    }
}

@end

/// GSPDFPrintOperation's own _print draws a single page; this draws all of them.
@interface STPrintPDFOperation : GSPDFPrintOperation
@end

@implementation STPrintPDFOperation

- (void)_print {
    NSView *view = [self view];
    NSGraphicsContext *context = [self context];
    NSRange range = NSMakeRange(1, 0);
    [view knowsPageRange:&range];
    [view beginDocument];
    for (NSInteger page = (NSInteger)range.location; page < (NSInteger)NSMaxRange(range); page++) {
        NSRect rect = [view rectForPage:page];
        [view beginPageInRect:rect atPlacement:NSZeroPoint];
        [view displayRectIgnoringOpacity:rect inContext:context];
        [view endPage];
        [context showPage];
    }
    [view endDocument];
}

@end

/// Read Linux's umask without changing process-global state while other threads may create files.
static mode_t STPrintNewPDFMode(void) {
    mode_t mode = 0644; // Conventional PDF permissions if procfs does not expose the mask.
    FILE *status = fopen("/proc/self/status", "r");
    if (status) {
        char line[256];
        unsigned int mask = 0;
        while (fgets(line, sizeof(line), status)) {
            if (sscanf(line, "Umask: %o", &mask) == 1 && mask <= 0777) {
                mode = 0666 & ~mask;
                break;
            }
        }
        fclose(status);
    }
    return mode;
}

BOOL STWritePrintPDF(STPrintLayout *layout, NSImage *image, NSString *path) {
    if (layout.pageCount == 0) {
        return NO;
    }
    NSFileManager *files = [NSFileManager defaultManager];
    NSString *destination = path;
    struct stat target;
    if (lstat(path.fileSystemRepresentation, &target) == 0) {
        char *resolved = realpath(path.fileSystemRepresentation, NULL);
        // Preserve a dangling or otherwise unresolvable link instead of replacing the link itself.
        if (!resolved) return NO;
        destination = [files stringWithFileSystemRepresentation:resolved length:strlen(resolved)];
        free(resolved);
        if (!destination) return NO;
    } else if (errno != ENOENT) {
        return NO;
    }
    mode_t mode;
    if (stat(destination.fileSystemRepresentation, &target) == 0) {
        mode = target.st_mode & 0777;
    } else if (errno == ENOENT) {
        mode = STPrintNewPDFMode();
    } else {
        return NO;
    }
    NSSize sheet = layout.orientedPaperSize;
    NSRect bounds = NSMakeRect(0.0, 0.0, sheet.width, sheet.height);

    STPrintPDFView *view = [[STPrintPDFView alloc] initWithFrame:bounds];
    view.layout = layout;
    view.image = image;
    view.drewEveryPage = YES;

    NSPrintInfo *info = [[NSPrintInfo sharedPrintInfo] copy];
    [info setPaperSize:sheet];
    // After setPaperSize:, which sets the orientation from the shape: see the header.
    [info dictionary][NSPrintOrientation] = @(NSPortraitOrientation);
    [info dictionary][@"NSPrintSheetBounds"] = [NSValue valueWithRect:bounds];
    [info setTopMargin:0.0];
    [info setBottomMargin:0.0];
    [info setLeftMargin:0.0];
    [info setRightMargin:0.0];

    // Keep an existing PDF intact until every page has been written. A sibling is on the same
    // filesystem, so rename replaces the target atomically only after a successful operation.
    NSString *directory = destination.stringByDeletingLastPathComponent;
    if (directory.length == 0) directory = @".";
    NSString *template = [directory stringByAppendingPathComponent:@".ScreenshotTool-print-XXXXXX"];
    char *temporaryPath = strdup(template.fileSystemRepresentation);
    if (!temporaryPath) return NO;
    int fd = mkstemp(temporaryPath);
    if (fd < 0) {
        free(temporaryPath);
        return NO;
    }
    close(fd);
    NSString *temporary = [files stringWithFileSystemRepresentation:temporaryPath length:strlen(temporaryPath)];
    free(temporaryPath);
    @try {
        STPrintPDFOperation *operation = [[STPrintPDFOperation alloc] initWithView:view
                                                                        insideRect:bounds
                                                                            toPath:temporary
                                                                         printInfo:info];
        [operation setShowsPrintPanel:NO];
        [operation setShowsProgressPanel:NO];
        BOOL ran = [operation runOperation];
        if (!ran || !view.drewEveryPage) return NO;
        // mkstemp already created an empty file; its existence alone is not successful output.
        int output = open(temporary.fileSystemRepresentation, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
        if (output < 0) return NO;
        struct stat written;
        BOOL complete = fstat(output, &written) == 0 && S_ISREG(written.st_mode) && written.st_size > 0 &&
                        fchmod(output, mode) == 0;
        close(output);
        return complete && rename(temporary.fileSystemRepresentation, destination.fileSystemRepresentation) == 0;
    } @finally {
        // After rename the sibling no longer exists; on any failure only this sibling is removed.
        [files removeItemAtPath:temporary error:NULL];
    }
}

BOOL STWriteCanvasPrintPDF(ScreenshotCanvasView *canvas, STPrintOptions *options, NSSize paper,
                           STPrintMargins printerMargins, NSString *path) {
    NSImage *flattened = [canvas flattenedImage];
    if (!flattened) {
        return NO;
    }
    STPrintLayout *layout = [[STPrintLayout alloc] init];
    layout.paperSize = paper;
    layout.margins = STPrintMarginsMake(STPrintDefaultMargin, STPrintDefaultMargin, STPrintDefaultMargin, STPrintDefaultMargin);
    layout.printerMargins = printerMargins;
    STConfigurePrintLayout(layout, options, flattened, [canvas selectionImageRect]);
    if (options.selectionOnly && NSIsEmptyRect(layout.sourceRect)) return NO;

    // The scale comes from this layout; only the bitmap and its pixel counts change after it.
    NSUInteger scale = [layout flattenScaleForImagePixelSize:STPrintImagePixelSize(flattened)];
    NSRect keep = options.selectionOnly ? layout.sourceRect : NSZeroRect;
    NSImage *printed = [canvas flattenedImageForPrintAtScale:scale
                                                  withinRect:STPrintPointRectForPixelRect(flattened, keep)];
    if (!printed) {
        scale = 1;
        printed = options.selectionOnly ? [canvas flattenedImageForSelection] : flattened;
    }
    if (!printed) {
        return NO;
    }
    NSSize pixels = STPrintImagePixelSize(printed);
    layout.sourceRect = NSMakeRect(0.0, 0.0, pixels.width, pixels.height);
    layout.pixelsPerInch = layout.pixelsPerInch * scale;
    return STWritePrintPDF(layout, printed, path);
}

#endif
