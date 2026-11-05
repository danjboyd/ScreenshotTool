#import "STPrintPDF.h"

#if defined(__linux__)

#import <GNUstepGUI/GSPDFPrintOperation.h>
#import "STPrintPage.h"

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

BOOL STWritePrintPDF(STPrintLayout *layout, NSImage *image, NSString *path) {
    if (layout.pageCount == 0) {
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

    STPrintPDFOperation *operation = [[STPrintPDFOperation alloc] initWithView:view
                                                                    insideRect:bounds
                                                                        toPath:path
                                                                     printInfo:info];
    [operation setShowsPrintPanel:NO];
    [operation setShowsProgressPanel:NO];
    BOOL ran = [operation runOperation];
    NSFileManager *files = [NSFileManager defaultManager];
    if (!ran || !view.drewEveryPage) {
        [files removeItemAtPath:path error:NULL];
        return NO;
    }
    return [files fileExistsAtPath:path];
}

#endif
