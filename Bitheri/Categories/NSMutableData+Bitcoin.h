//
//  NSMutableData+Bitcoin.h
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

#import <Foundation/Foundation.h>

#if BITCOIN_TESTNET
#define BITCOIN_MAGIC_NUMBER 0x0709110b
#else
#define BITCOIN_MAGIC_NUMBER 0xd9b4bef9
#endif

@interface NSMutableData (Bitcoin)

+ (NSMutableData *)secureData;
+ (NSMutableData *)secureDataWithLength:(NSUInteger)length;
+ (NSMutableData *)secureDataWithCapacity:(NSUInteger)capacity;
+ (NSMutableData *)secureDataWithData:(NSData *)data;

+ (size_t)sizeOfVarInt:(uint64_t)i;

- (void)appendUInt8:(uint8_t)i;
- (void)appendUInt16:(uint16_t)i;
- (void)appendUInt32:(uint32_t)i;
- (void)appendUInt64:(uint64_t)i;
- (void)appendVarInt:(uint64_t)i;
- (void)appendString:(NSString *)s;

- (void)appendScriptPubKeyForHash:(NSData *)hash;
- (void)appendScriptPubKeyForAddress:(NSString *)address;
- (void)appendScriptPushData:(NSData *)d;

- (void)appendMessage:(NSData *)message type:(NSString *)type;
- (void)appendNullPaddedString:(NSString *)s length:(NSUInteger)length;
- (void)appendNetAddress:(uint32_t)address port:(uint16_t)port services:(uint64_t)services;

@end
