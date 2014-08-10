//
//  BTPasswordSeedTest.m
//  bitheri
//
//  Copyright 2014 http://Bither.net
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

#import <XCTest/XCTest.h>
#import "BTPasswordSeed.h"
#import "BTTestHelper.h"

@interface BTPasswordSeedTest : XCTestCase

@end

@implementation BTPasswordSeedTest

- (void)setUp {
    [super setUp];
    [BTTestHelper setup];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)test {
    BTPasswordSeed *password = [[BTPasswordSeed alloc] initWithString:@"19jnfQFH8oJ2zejk2Chnqr39Jn2gkbeccs:b9879dc940f1b4ff0565b1a27a87c6e2091b2727b6ee03f80462dfa8c824900eef96a0728d54a486cd31e906973a8c9f:a332cf42d67705a6cfdec0c903cef606:6f73ea0a359d02b1"];
    XCTAssertTrue([password checkPassword:@"123456"], @"check password");
    XCTAssertTrue([[password description] isEqualToString:@"19jnfQFH8oJ2zejk2Chnqr39Jn2gkbeccs:b9879dc940f1b4ff0565b1a27a87c6e2091b2727b6ee03f80462dfa8c824900eef96a0728d54a486cd31e906973a8c9f:a332cf42d67705a6cfdec0c903cef606:6f73ea0a359d02b1"], @" password toString");

    BTAddress *address = [[BTAddress alloc] initWithBitcoinjKey:@"b9879dc940f1b4ff0565b1a27a87c6e2091b2727b6ee03f80462dfa8c824900eef96a0728d54a486cd31e906973a8c9f:a332cf42d67705a6cfdec0c903cef606:6f73ea0a359d02b1" withPassphrase:@"123456"];
    BTPasswordSeed *addressPS = [[BTPasswordSeed alloc] initWithBTAddress:address];
    XCTAssertTrue([addressPS checkPassword:@"123456"], @"check password");
    XCTAssertTrue([[addressPS description] isEqualToString:@"19jnfQFH8oJ2zejk2Chnqr39Jn2gkbeccs:b9879dc940f1b4ff0565b1a27a87c6e2091b2727b6ee03f80462dfa8c824900eef96a0728d54a486cd31e906973a8c9f:a332cf42d67705a6cfdec0c903cef606:6f73ea0a359d02b1"], @" password toString");
}

@end
