#import "STCanvasContextMenu.h"

static NSMenuItem *STContextItem(NSMenu *menu, NSString *title, SEL action, id target,
                                 NSString *key, NSEventModifierFlags modifiers) {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];
    // The shortcut is shown so it can be learnt; the menu bar's item is the one that answers it.
    if (key.length > 0) {
        [item setKeyEquivalentModifierMask:modifiers];
    }
    item.target = target;
    [menu addItem:item];
    return item;
}

NSMenu *STCanvasContextMenu(STCanvasContextKind kind, BOOL singleText,
                            id<STCanvasContextCommands> canvas, id controller,
                            NSArray<NSMenuItem *> *extraItems) {
    const NSEventModifierFlags command = NSEventModifierFlagCommand;
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    switch (kind) {
        case STCanvasContextKindNone:
            return nil;

        case STCanvasContextKindSelection:
            STContextItem(menu, @"Crop to Selection", @selector(cropImage:), controller, @"k", command);
            STContextItem(menu, @"Copy Selection", @selector(copy:), controller, @"c", command);
            STContextItem(menu, @"Redact Selection", @selector(redactSelection:), canvas, @"", 0);
            [menu addItem:[NSMenuItem separatorItem]];
            STContextItem(menu, @"Deselect", @selector(deselect:), canvas, @"", 0);
            break;

        case STCanvasContextKindAnnotation:
            if (singleText) {
                STContextItem(menu, @"Edit Text", @selector(editSelectedText:), canvas, @"", 0);
                [menu addItem:[NSMenuItem separatorItem]];
            }
            STContextItem(menu, @"Duplicate", @selector(duplicateAnnotations:), canvas, @"", 0);
            STContextItem(menu, @"Bring to Front", @selector(bringAnnotationsToFront:), canvas, @"", 0);
            STContextItem(menu, @"Send to Back", @selector(sendAnnotationsToBack:), canvas, @"", 0);
            [menu addItem:[NSMenuItem separatorItem]];
            STContextItem(menu, @"Delete", @selector(deleteAnnotations:), canvas, @"", 0);
            break;

        case STCanvasContextKindImage:
            STContextItem(menu, @"Copy Image", @selector(copy:), controller, @"c", command);
            STContextItem(menu, @"Paste as New Image", @selector(pasteAsNewImage:), controller, @"V",
                          command | NSEventModifierFlagShift);
            [menu addItem:[NSMenuItem separatorItem]];
            STContextItem(menu, @"Fit to Window", @selector(zoomFitToWindow:), controller, @"0", command);
            STContextItem(menu, @"Zoom to 100%", @selector(zoomPreset100:), controller, @"1", command);
            [menu addItem:[NSMenuItem separatorItem]];
            STContextItem(menu, @"Save As…", @selector(saveDocumentAs:), controller, @"s", command);
            if (extraItems.count > 0) {
                [menu addItem:[NSMenuItem separatorItem]];
            }
            for (NSMenuItem *item in extraItems) {
                [menu addItem:item];
            }
            break;
    }
    return menu;
}
