//
//  GSXCTestRunner.m
//  Eggplant
//
//  Created by Adam Fox on 9/17/18.
//  Copyright © 2018 TestPlant, Inc. All rights reserved.
//
/*
 This file is part of the GNUstep XCTEST Library.

 This library is free software; you can redistribute it and/or
 modify it under the terms of the GNU Lesser General Public
 License as published by the Free Software Foundation; either
 version 2 of the License, or (at your option) any later version.

 This library is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.     See the GNU
 Lesser General Public License for more details.

 You should have received a copy of the GNU Lesser General Public
 License along with this library; see the file COPYING.LIB.
 If not, see <http://www.gnu.org/licenses/> or write to the
 Free Software Foundation, 51 Franklin Street, Fifth Floor,
 Boston, MA 02110-1301, USA.
*/


#import <XCTest/GSXCTestRunner.h>
#import <XCTest/XCTestCase.h>

#import <objc/runtime.h>

@interface GSXCTestRunner ()
- (BOOL)runTestsForTargetName:(NSString *)targetName
          onlyTestIdentifiers:(NSArray *)onlyTestIdentifiers
          skipTestIdentifiers:(NSArray *)skipTestIdentifiers
              legacyTestNames:(NSArray *)legacyTestNames;
@end

static NSArray *GSParseAppleTestIdentifier(NSString *identifier)
{
    NSArray *components = [identifier componentsSeparatedByString:@"/"];

    if ([components count] == 0 || [components count] > 3)
    {
        return nil;
    }

    for (NSString *component in components)
    {
        if ([component length] == 0)
        {
            return nil;
        }
    }

    return components;
}

static BOOL GSAppleTestIdentifierMatches(NSArray *identifierComponents,
                                         NSString *targetName,
                                         NSString *className,
                                         NSString *methodName)
{
    if (![targetName isEqualToString:[identifierComponents objectAtIndex:0]])
    {
        return NO;
    }

    if ([identifierComponents count] >= 2 &&
        ![className isEqualToString:[identifierComponents objectAtIndex:1]])
    {
        return NO;
    }

    if ([identifierComponents count] == 3 &&
        ![methodName isEqualToString:[identifierComponents objectAtIndex:2]])
    {
        return NO;
    }

    return YES;
}

static BOOL GSLegacyTestNameMatches(NSString *testName,
                                    NSString *className,
                                    NSString *methodName)
{
    NSArray *tuple = [testName componentsSeparatedByString:@"."];

    if ([tuple count] == 2)
    {
        return [className isEqualToString:[tuple objectAtIndex:0]] &&
               [methodName isEqualToString:[tuple objectAtIndex:1]];
    }

    if ([tuple count] == 1)
    {
        return [className isEqualToString:[tuple objectAtIndex:0]];
    }

    return NO;
}

// From: https://www.cocoawithlove.com/2010/01/getting-subclasses-of-objective-c-class.html
NSArray *ClassGetSubclasses(Class parentClass)
{
    int numClasses = objc_getClassList(NULL, 0);
    __unsafe_unretained Class *classes = NULL;

    classes = (__unsafe_unretained Class *)malloc(sizeof(Class) * numClasses);
    numClasses = objc_getClassList(classes, numClasses);
    
    NSMutableArray *result = [NSMutableArray array];
    for (NSInteger i = 0; i < numClasses; i++)
    {
        Class superClass = classes[i];
        do
        {
            superClass = class_getSuperclass(superClass);
        } while(superClass && superClass != parentClass);
        
        if (superClass == nil)
        {
            continue;
        }
        
        [result addObject:classes[i]];
    }

    free(classes);
    
    return result;
}

@implementation GSXCTestRunner

- (id)init
{
    self = [super init];
    if (self) {
        runLock = [[NSLock alloc] init];
    }
    
    return self;
}

- (void)dealloc
{
#if !__has_feature(objc_arc)
    [runLock release];
    [super dealloc];
#endif
}

- (BOOL)runAll
{
    return [self runTestsForTargetName:nil
                   onlyTestIdentifiers:nil
                   skipTestIdentifiers:nil];
}

- (BOOL)runTestsNamed:(NSArray *)testNames
{
    return [self runTestsForTargetName:nil
                   onlyTestIdentifiers:nil
                   skipTestIdentifiers:nil
                       legacyTestNames:testNames];
}

- (BOOL)runTestsForTargetName:(NSString *)targetName
          onlyTestIdentifiers:(NSArray *)onlyTestIdentifiers
          skipTestIdentifiers:(NSArray *)skipTestIdentifiers
{
    return [self runTestsForTargetName:targetName
                   onlyTestIdentifiers:onlyTestIdentifiers
                   skipTestIdentifiers:skipTestIdentifiers
                       legacyTestNames:nil];
}

- (BOOL)runTestsForTargetName:(NSString *)targetName
          onlyTestIdentifiers:(NSArray *)onlyTestIdentifiers
          skipTestIdentifiers:(NSArray *)skipTestIdentifiers
              legacyTestNames:(NSArray *)legacyTestNames
{
    NSMutableArray *parsedOnlyIdentifiers = nil;
    NSMutableArray *parsedSkipIdentifiers = nil;
    BOOL usingAppleStyleFilters = (legacyTestNames == nil);
    BOOL usingAnyFilters = NO;

    if (usingAppleStyleFilters)
    {
        if ([onlyTestIdentifiers count] > 0)
        {
            parsedOnlyIdentifiers = [NSMutableArray arrayWithCapacity:[onlyTestIdentifiers count]];
            usingAnyFilters = YES;

            for (NSString *identifier in onlyTestIdentifiers)
            {
                NSArray *components = GSParseAppleTestIdentifier(identifier);
                if (components == nil)
                {
                    NSLog(@"XCTest: Invalid test identifier '%@'. Expected TestTarget[/TestClass[/TestMethod]].", identifier);
                    return NO;
                }

                [parsedOnlyIdentifiers addObject:components];
            }
        }

        if ([skipTestIdentifiers count] > 0)
        {
            parsedSkipIdentifiers = [NSMutableArray arrayWithCapacity:[skipTestIdentifiers count]];
            usingAnyFilters = YES;

            for (NSString *identifier in skipTestIdentifiers)
            {
                NSArray *components = GSParseAppleTestIdentifier(identifier);
                if (components == nil)
                {
                    NSLog(@"XCTest: Invalid test identifier '%@'. Expected TestTarget[/TestClass[/TestMethod]].", identifier);
                    return NO;
                }

                [parsedSkipIdentifiers addObject:components];
            }
        }

        if (usingAnyFilters && ([targetName length] == 0))
        {
            NSLog(@"XCTest: A target name is required when using -only-testing or -skip-testing filters.");
            return NO;
        }
    }

    [runLock lock];
    
    NSLog(@"XCTest: Running Unit Tests");
    NSUInteger testCaseFailureCount = 0;
    NSUInteger testCaseSuccessCount = 0;
    NSUInteger selectedTestCount = 0;
    
    NSArray *testCaseClasses = ClassGetSubclasses([XCTestCase class]);
    for (Class testCaseClass in testCaseClasses)
    {
        @autoreleasepool {
            BOOL classNamePrinted = NO;
            NSString *className = NSStringFromClass(testCaseClass);
            
            unsigned int methodCount = 0;
            NSUInteger methodFailureCount = 0;
            NSUInteger methodSuccessCount = 0;
            Method *methods = class_copyMethodList(testCaseClass, &methodCount);
        
            for (unsigned int i = 0; i < methodCount; i++) {
                Method method = methods[i];
        
                SEL selector = method_getName(method);
                NSString *methodName = [NSString stringWithUTF8String:sel_getName(selector)];
                
                BOOL testIsEnabled = YES;
                if (usingAppleStyleFilters)
                {
                    if ([parsedOnlyIdentifiers count] > 0)
                    {
                        testIsEnabled = NO;
                        for (NSArray *identifierComponents in parsedOnlyIdentifiers)
                        {
                            if (GSAppleTestIdentifierMatches(identifierComponents,
                                                             targetName,
                                                             className,
                                                             methodName))
                            {
                                testIsEnabled = YES;
                                break;
                            }
                        }
                    }

                    if (testIsEnabled && [parsedSkipIdentifiers count] > 0)
                    {
                        for (NSArray *identifierComponents in parsedSkipIdentifiers)
                        {
                            if (GSAppleTestIdentifierMatches(identifierComponents,
                                                             targetName,
                                                             className,
                                                             methodName))
                            {
                                testIsEnabled = NO;
                                break;
                            }
                        }
                    }
                }
                else if (legacyTestNames)
                {
                    testIsEnabled = NO; // default to disabled when tests are specified
                    for (NSString *testName in legacyTestNames)
                    {
                        if (GSLegacyTestNameMatches(testName, className, methodName))
                        {
                            testIsEnabled = YES;
                            break;
                        }
                    }
                }
                
                if ([methodName hasPrefix:@"test"]
                    && method_getNumberOfArguments(method) == 2
                    && testIsEnabled)
                {
                    selectedTestCount++;
                    IMP testFunction = method_getImplementation(method);
                    if (testFunction) {
                        BOOL testSucceeded = YES;
                        
                        if (!classNamePrinted) {
                            NSLog(@"XCTest:   Running %@", className);
                            classNamePrinted = YES;
                        }
                        
                        NSLog(@"XCTest:     %@...", methodName);
                        
                        NS_DURING {
                            @autoreleasepool {
                                XCTestCase *testCase = [[testCaseClass alloc] init];
#if !__has_feature(objc_arc)
                                [testCase autorelease];
#endif
                                assertionFailureCount = 0;
                                [testCase setUp];
                                ((void (*)(id, SEL))testFunction)(testCase, selector);
                                [testCase tearDown];
                                if (assertionFailureCount > 0) {
                                    testSucceeded = NO;
                                    NSLog(@"XCTest:     %@ FAILED", methodName);
                                }
                            }
                        }
                        NS_HANDLER {
                            testSucceeded = NO;
                            NSLog(@"XCTest:     %@ FAILED, threw exception: %@", methodName, localException);
                        }
                        NS_ENDHANDLER
                        
                        if (testSucceeded)
                            methodSuccessCount++;
                        else
                            methodFailureCount++;
                    }
                }
            }
        
            free(methods);
            
            if (methodFailureCount == 0 && methodSuccessCount == 0) {
                NSLog(@"XCTest:   %@ SKIPPED", className);
            }
            else if (methodFailureCount > 0) {
                testCaseFailureCount++;
                NSLog(@"XCTest:   %@: %lu/%lu tests FAILED", className, methodFailureCount, methodFailureCount + methodSuccessCount);
            } else {
                testCaseSuccessCount++;
                if (methodSuccessCount > 0) {
                    NSLog(@"XCTest:   %@: %lu tests PASSED", className, methodSuccessCount);
                }
            }
        } // @autoreleasepool
    }
    
    if (testCaseSuccessCount == 0 && testCaseFailureCount == 0) {
        if (usingAppleStyleFilters && usingAnyFilters && selectedTestCount == 0) {
            NSLog(@"XCTest: No tests matched the provided filters.");
        } else {
            NSLog(@"XCTest: No tests found.");
        }
    }
    else if (testCaseFailureCount > 0) {
        NSLog(@"XCTest: %lu/%lu test cases FAILED", testCaseFailureCount, testCaseFailureCount + testCaseSuccessCount);
    } else {
        NSLog(@"XCTest: %lu tests PASSED", testCaseSuccessCount);
    }
    
    [runLock unlock];
    
    return testCaseFailureCount == 0;
}

- (void)waitForCompletion
{
    [runLock lock];
    [runLock unlock];
}

- (void)registerAssertionFailed
{
    @synchronized (self) {
        assertionFailureCount++;
    }
}

+ (GSXCTestRunner *)sharedRunner
{
    static GSXCTestRunner *runner = nil;
    if (!runner) {
        runner = [[GSXCTestRunner alloc] init];
    }
    
    return runner;
}

@end
