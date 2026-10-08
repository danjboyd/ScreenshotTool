/*
 * STFontFamilyList.m
 * Copyright (C) 2026 Daniel Boyd
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

#import "STFontFamilyList.h"
#import <AppKit/AppKit.h>
#if defined(GNUSTEP) && __has_include(<fontconfig/fontconfig.h>)
#include <fontconfig/fontconfig.h>
#define ST_HAVE_FONTCONFIG 1
#endif

NSString * const STRecentFontFamiliesDefaultsKey = @"ScreenshotToolRecentFontFamilies";
const NSUInteger STRecentFontFamiliesLimit = 6;

@interface STFontFamilyList ()
@property (nonatomic, copy) NSArray<NSString *> *allFamilies;
@property (nonatomic, copy) NSArray<NSString *> *coveredFamilies;
@property (nonatomic, copy) NSArray<NSString *> *recentFamilies;
@property (nonatomic, copy) NSArray<NSString *> *listedFamilies;
@property (nonatomic, assign) NSUInteger recentCount;
/// Lowercased name -> installed name, for matching what's typed.
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *familiesByLowercaseName;
@end

@implementation STFontFamilyList

- (instancetype)initWithFamilies:(NSArray<NSString *> *)allFamilies
                coveredFamilies:(NSArray<NSString *> *)coveredFamilies
                         recent:(NSArray<NSString *> *)recentFamilies {
    self = [super init];
    if (self) {
        _allFamilies = [[allFamilies sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)] copy];
        NSMutableDictionary<NSString *, NSString *> *byName = [[NSMutableDictionary alloc] init];
        for (NSString *family in _allFamilies) {
            byName[[family lowercaseString]] = family;
        }
        // The system font isn't among the installed families on macOS; it goes by "System Font".
        NSString *systemFamily = [NSFont systemFontOfSize:0.0].familyName;
        if ([systemFamily hasPrefix:@"."]) {
            byName[@"system font"] = systemFamily;
        }
        _familiesByLowercaseName = [byName copy];
        // Only families that are installed: fontconfig and AppKit can disagree about a few names.
        NSMutableArray<NSString *> *covered = nil;
        if (coveredFamilies.count > 0) {
            covered = [[NSMutableArray alloc] init];
            for (NSString *family in coveredFamilies) {
                NSString *installed = byName[[family lowercaseString]];
                if (installed && ![covered containsObject:installed]) {
                    [covered addObject:installed];
                }
            }
            [covered sortUsingSelector:@selector(caseInsensitiveCompare:)];
        }
        _coveredFamilies = covered.count > 0 ? [covered copy] : _allFamilies;
        NSMutableArray<NSString *> *recent = [[NSMutableArray alloc] init];
        for (NSString *family in recentFamilies) {
            NSString *installed = byName[[family lowercaseString]];
            if (installed && ![recent containsObject:installed] && recent.count < STRecentFontFamiliesLimit) {
                [recent addObject:installed];
            }
        }
        _recentFamilies = [recent copy];
        [self rebuildListedFamilies];
    }
    return self;
}

- (instancetype)init {
    NSArray<NSString *> *recent = [[NSUserDefaults standardUserDefaults] stringArrayForKey:STRecentFontFamiliesDefaultsKey];
    return [self initWithFamilies:[[NSFontManager sharedFontManager] availableFontFamilies] ?: @[]
                  coveredFamilies:[STFontFamilyList familiesCoveringLanguage:[STFontFamilyList userLanguage]]
                           recent:recent ?: @[]];
}

- (void)rebuildListedFamilies {
    NSMutableArray<NSString *> *listed = [self.recentFamilies mutableCopy];
    for (NSString *family in self.coveredFamilies) {
        if (![self.recentFamilies containsObject:family]) {
            [listed addObject:family];
        }
    }
    self.listedFamilies = listed;
    self.recentCount = self.recentFamilies.count;
}

- (NSString *)familyNamed:(NSString *)name {
    NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    return trimmed.length > 0 ? self.familiesByLowercaseName[[trimmed lowercaseString]] : nil;
}

- (NSString *)completionForPrefix:(NSString *)prefix {
    if (prefix.length == 0) {
        return nil;
    }
    for (NSArray<NSString *> *families in @[self.listedFamilies, self.allFamilies]) {
        for (NSString *family in families) {
            if ([family rangeOfString:prefix options:(NSCaseInsensitiveSearch | NSAnchoredSearch)].location != NSNotFound) {
                return family;
            }
        }
    }
    return nil;
}

- (void)noteUsedFamily:(NSString *)family {
    NSString *installed = [self familyNamed:family];
    if (!installed) {
        return;
    }
    NSMutableArray<NSString *> *recent = [self.recentFamilies mutableCopy];
    [recent removeObject:installed];
    [recent insertObject:installed atIndex:0];
    while (recent.count > STRecentFontFamiliesLimit) {
        [recent removeLastObject];
    }
    self.recentFamilies = recent;
    [[NSUserDefaults standardUserDefaults] setObject:recent forKey:STRecentFontFamiliesDefaultsKey];
    [self rebuildListedFamilies];
}

+ (NSString *)displayNameForFamily:(NSString *)family {
    return [family hasPrefix:@"."] ? @"System Font" : family;
}

+ (NSString *)userLanguage {
    NSString *preferred = [[NSLocale preferredLanguages] firstObject];
    NSString *language = [[preferred componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"-_"]] firstObject];
    return language.length > 0 ? [language lowercaseString] : @"en";
}

+ (NSArray<NSString *> *)familiesCoveringLanguage:(NSString *)language {
#if defined(ST_HAVE_FONTCONFIG)
    if (language.length == 0 || !FcInit()) {
        return nil;
    }
    FcPattern *pattern = FcPatternCreate();
    FcLangSet *langs = FcLangSetCreate();
    FcLangSetAdd(langs, (const FcChar8 *)[language UTF8String]);
    FcPatternAddLangSet(pattern, FC_LANG, langs);
    FcObjectSet *objects = FcObjectSetBuild(FC_FAMILY, (char *)NULL);
    FcFontSet *fonts = FcFontList(NULL, pattern, objects);
    NSMutableSet<NSString *> *families = [[NSMutableSet alloc] init];
    for (int i = 0; fonts && i < fonts->nfont; i++) {
        FcChar8 *family = NULL;
        // A font can list its family in several languages; the first is the one AppKit uses.
        if (FcPatternGetString(fonts->fonts[i], FC_FAMILY, 0, &family) == FcResultMatch && family) {
            [families addObject:[NSString stringWithUTF8String:(const char *)family]];
        }
    }
    if (fonts) {
        FcFontSetDestroy(fonts);
    }
    FcObjectSetDestroy(objects);
    FcLangSetDestroy(langs);
    FcPatternDestroy(pattern);
    return [families allObjects];
#else
    (void)language;
    return nil;
#endif
}

@end
