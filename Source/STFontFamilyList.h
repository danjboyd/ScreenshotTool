/*
 * STFontFamilyList.h
 * Copyright (C) 2026 Daniel Boyd
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The defaults key holding recently used families, most recent first.
extern NSString * const STRecentFontFamiliesDefaultsKey;
/// How many recently used families are kept.
extern const NSUInteger STRecentFontFamiliesLimit;

/// The font families the text bar offers (#103): recently used ones first, then those that cover
/// the user's language. Thousands of families are installed with a collection like Noto, most of
/// them for other scripts; any family can still be found by typing its name.
@interface STFontFamilyList : NSObject

/// All installed families and the language whose fonts are listed (e.g. "en").
- (instancetype)initWithFamilies:(NSArray<NSString *> *)allFamilies
                coveredFamilies:(nullable NSArray<NSString *> *)coveredFamilies
                         recent:(NSArray<NSString *> *)recentFamilies NS_DESIGNATED_INITIALIZER;
/// The installed families, those covering the user's language, and the recent ones from defaults.
- (instancetype)init;

/// Recent families, then the ones covering the language (all families when that's unknown).
@property (nonatomic, readonly) NSArray<NSString *> *listedFamilies;
/// How many of the listed families are recent ones (they come first).
@property (nonatomic, readonly) NSUInteger recentCount;

/// The installed family named `name`, ignoring case, or nil.
- (nullable NSString *)familyNamed:(NSString *)name;
/// The first family starting with `prefix` (ignoring case): listed families first, then all.
- (nullable NSString *)completionForPrefix:(NSString *)prefix;
/// Puts `family` first among the recent families and saves them to the defaults.
- (void)noteUsedFamily:(NSString *)family;

/// The families fontconfig says cover `language` (e.g. "en"), or nil without fontconfig.
+ (nullable NSArray<NSString *> *)familiesCoveringLanguage:(NSString *)language;
/// The user's language as fontconfig names it, e.g. "en" for en_US.
+ (NSString *)userLanguage;

/// The name to show for a family: "System Font" for the system's own, whose family name on macOS
/// (.AppleSystemUIFont) is private.
+ (NSString *)displayNameForFamily:(NSString *)family;

@end

NS_ASSUME_NONNULL_END
