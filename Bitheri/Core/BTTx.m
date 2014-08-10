//
//  BTTx.m
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

#import "BTTx.h"
#import "BTKey.h"

#import "BTInItem.h"
#import "BTOutItem.h"
#import "BTSettings.h"
#import "BTTxProvider.h"
#import "BTBlockChain.h"
#import "BTAddress.h"
#import "BTScript.h"
#import "BTScriptChunk.h"
#import "BTScriptOpCodes.h"

@interface BTTx ()

@property (nonatomic, strong) NSMutableArray *hashes, *indexes, *inScripts, *signatures, *sequences;
@property (nonatomic, strong) NSMutableArray *amounts, *addresses, *outScripts;

@end

@implementation BTTx

+ (instancetype)transactionWithMessage:(NSData *)message
{
    return [[self alloc] initWithMessage:message];
}

- (instancetype)init
{
    if (! (self = [super init])) return nil;
    
    _version = TX_VERSION;
    _hashes = [NSMutableArray array];
    _indexes = [NSMutableArray array];
    _inScripts = [NSMutableArray array];
    _amounts = [NSMutableArray array];
    _addresses = [NSMutableArray array];
    _outScripts = [NSMutableArray array];
    _signatures = [NSMutableArray array];
    _sequences = [NSMutableArray array];
    _lockTime = TX_LOCKTIME;
    _blockHeight = TX_UNCONFIRMED;
    _txTime = (uint) [[NSDate date] timeIntervalSince1970];

    return self;
}

- (instancetype)initWithMessage:(NSData *)message
{
    if (! (self = [self init])) return nil;
 
    NSString *address = nil;
    NSUInteger l = 0, off = 0;
    uint64_t count = 0;
    NSData *d = nil;

    _txHash = message.SHA256_2;
    _version = [message UInt32AtOffset:off]; // tx version
    off += sizeof(uint32_t);
    count = [message varIntAtOffset:off length:&l]; // input count
    if (count == 0) return nil; // at least one input is required
    off += l;

    for (NSUInteger i = 0; i < count; i++) { // inputs
        d = [message hashAtOffset:off]; // input tx hash
        if (! d) return nil; // required
        [self.hashes addObject:d];
        off += CC_SHA256_DIGEST_LENGTH;
        [self.indexes addObject:@([message UInt32AtOffset:off])]; // input index
        off += sizeof(uint32_t);
        [self.inScripts addObject:[NSNull null]]; // placeholder for input script (comes from previous transaction)
        d = [message dataAtOffset:off length:&l];
        [self.signatures addObject:d ?: [NSNull null]]; // input signature
        off += l;
        [self.sequences addObject:@([message UInt32AtOffset:off])]; // input sequence number (for replacement tx)
        off += sizeof(uint32_t);
    }

    count = [message varIntAtOffset:off length:&l]; // output count
    off += l;
    
    for (NSUInteger i = 0; i < count; i++) { // outputs
        [self.amounts addObject:@([message UInt64AtOffset:off])]; // output amount
        off += sizeof(uint64_t);
        d = [message dataAtOffset:off length:&l];
        [self.outScripts addObject:d ?: [NSNull null]]; // output script
        off += l;
//        address = [NSString addressWithScript:d]; // address from output script if applicable
        address = [[[BTScript alloc] initWithProgram:d] getToAddress];
        [self.addresses addObject:address ?: [NSNull null]];
    }
    
    _lockTime = [message UInt32AtOffset:off]; // tx locktime
    
    return self;
}

- (instancetype)initWithInputHashes:(NSArray *)hashes inputIndexes:(NSArray *)indexes inputScripts:(NSArray *)scripts
outputAddresses:(NSArray *)addresses outputAmounts:(NSArray *)amounts
{
    if (hashes.count == 0 || hashes.count != indexes.count || hashes.count != scripts.count) return nil;
    if (addresses.count != amounts.count) return nil;

    if (! (self = [super init])) return nil;

    _version = TX_VERSION;
    _hashes = [NSMutableArray arrayWithArray:hashes];
    _indexes = [NSMutableArray arrayWithArray:indexes];
    _inScripts = [NSMutableArray arrayWithArray:scripts];
    _amounts = [NSMutableArray arrayWithArray:amounts];
    _addresses = [NSMutableArray arrayWithArray:addresses];
    _outScripts = [NSMutableArray arrayWithCapacity:addresses.count];
    for (NSUInteger i = 0; i < addresses.count; i++) {
        [self.outScripts addObject:[NSMutableData data]];
        [self.outScripts.lastObject appendScriptPubKeyForAddress:self.addresses[i]];
    }

    _signatures = [NSMutableArray arrayWithCapacity:hashes.count];
    _sequences = [NSMutableArray arrayWithCapacity:hashes.count];
    for (NSInteger i = 0; i < hashes.count; i++) {
        [self.signatures addObject:[NSNull null]];
        [self.sequences addObject:@(TX_IN_SEQUENCE)];
    }

    _lockTime = TX_LOCKTIME;
    _blockHeight = TX_UNCONFIRMED;
    
    return self;
}

- (void)addInputHash:(NSData *)hash index:(NSUInteger)index script:(NSData *)script
{
    [self addInputHash:hash index:index script:script signature:nil sequence:TX_IN_SEQUENCE];
}

- (void)addInputHash:(NSData *)hash index:(NSUInteger)index script:(NSData *)script signature:(NSData *)signature
sequence:(uint32_t)sequence
{
    [self.hashes addObject:hash];
    [self.indexes addObject:@(index)];
    [self.inScripts addObject:script ?: [NSNull null]];
    [self.signatures addObject:signature ?: [NSNull null]];
    [self.sequences addObject:@(sequence)];
}

- (void)clearIns;{
    _hashes = [NSMutableArray new];
    _indexes = [NSMutableArray new];
    _inScripts = [NSMutableArray new];
    _signatures = [NSMutableArray new];
    _sequences = [NSMutableArray new];
}

- (void)addOutputAddress:(NSString *)address amount:(uint64_t)amount
{
    [self.amounts addObject:@(amount)];
    [self.addresses addObject:address];
    [self.outScripts addObject:[NSMutableData data]];
    [self.outScripts.lastObject appendScriptPubKeyForAddress:address];
}

- (void)addOutputScript:(NSData *)script amount:(uint64_t)amount;
{
    NSString *address = [NSString addressWithScript:script];

    [self.amounts addObject:@(amount)];
    [self.outScripts addObject:script];
    [self.addresses addObject:address ?: [NSNull null]];
}

- (void)setInputAddress:(NSString *)address atIndex:(NSUInteger)index;
{
    NSMutableData *d = [NSMutableData data];

    [d appendScriptPubKeyForAddress:address];
    self.inScripts[index] = d;
}

- (NSArray *)inputAddresses
{
    NSMutableArray *addresses = [NSMutableArray arrayWithCapacity:self.inScripts.count];

    for (NSUInteger i = 0; i < self.inScripts.count; i++) {
        NSString *addr = [NSString addressWithScript:self.inScripts[i]];

        if (addr) {
            [addresses addObject:addr];
        } else {
            NSData *signature = self.signatures[i];
            if (signature != (id) [NSNull null]){
                BTScript *script = [[BTScript alloc] initWithProgram:signature];
                if (script != nil) {
                    NSString *address = script.getFromAddress;
                    if (address != nil){
                        [addresses addObject:address];
                        continue;
                    }
                }
            }
            [addresses addObject:[NSNull null]];
        }
    }

    return addresses;
}

- (NSArray *)inputHashes
{
    return self.hashes;
}

- (NSArray *)inputIndexes
{
    return self.indexes;
}

- (NSArray *)inputScripts
{
    return self.inScripts;
}

- (NSArray *)inputSignatures
{
    return self.signatures;
}

- (NSArray *)inputSequences
{
    return self.sequences;
}

- (NSArray *)outputAmounts
{
    return self.amounts;
}

- (NSArray *)outputAddresses
{
    return self.addresses;
}

- (NSArray *)outputScripts
{
    return self.outScripts;
}

- (NSArray *)inValues {
    return [[BTTxProvider instance] txInValues:self.txHash];
}

//TODO: support signing pay2pubkey outputs (typically used for coinbase outputs)
- (BOOL)signWithPrivateKeys:(NSArray *)privateKeys
{
    NSMutableArray *addresses = [NSMutableArray arrayWithCapacity:privateKeys.count],
                   *keys = [NSMutableArray arrayWithCapacity:privateKeys.count];
    
    for (NSString *pk in privateKeys) {
        BTKey *key = [BTKey keyWithPrivateKey:pk];

        if (! key) continue;
 
        [keys addObject:key];
        [addresses addObject:key.hash160];
    }

    for (NSUInteger i = 0; i < self.hashes.count; i++) {
        NSUInteger keyIdx = [addresses indexOfObject:[self.inScripts[i]
                             subdataWithRange:NSMakeRange([self.inScripts[i] length] - 22, 20)]];

        if (keyIdx == NSNotFound) continue;
    
        NSMutableData *sig = [NSMutableData data];
        NSData *hash = [self toDataWithSubscriptIndex:i].SHA256_2;
        NSMutableData *s = [NSMutableData dataWithData:[keys[keyIdx] sign:hash]];

        [s appendUInt8:SIG_HASH_ALL];
        [sig appendScriptPushData:s];
        [sig appendScriptPushData:[keys[keyIdx] publicKey]];

        self.signatures[i] = sig;
    }
    
    if (! [self isSigned]) return NO;
    
    _txHash = self.data.SHA256_2;
        
    return YES;
}

// checks if all signatures exist, but does not verify them
- (BOOL)isSigned
{
    return (self.signatures.count > 0 && self.signatures.count == self.hashes.count &&
            ! [self.signatures containsObject:[NSNull null]]);
}

- (BOOL)verifySignatures;{
    if ([self isSigned]) {
        NSMutableArray *inScripts = [NSMutableArray new];
        NSMutableArray *keys = [NSMutableArray new];
        NSMutableArray *scripts = [NSMutableArray new];
        for (NSUInteger i = 0; i < self.signatures.count; i++) {
            BTScript *script = [[BTScript alloc] initWithProgram:self.signatures[i]];
            if (script == nil)
                return NO;
            NSString *address = script.getFromAddress;
            if (address == nil)
                return NO;
            NSMutableData *d = [NSMutableData data];
            [d appendScriptPubKeyForAddress:address];
            [inScripts addObject:d];
            [keys addObject:[BTKey keyWithPublicKey:[script getPubKey]]];

            [scripts addObject:script];
        }
        self.inScripts = inScripts;
        for (NSUInteger i = 0; i < self.signatures.count; i++) {
            NSData *unSignHash = [self toDataWithSubscriptIndex:i withInScripts:inScripts].SHA256_2;
//            NSData *unSignHash2 = [self toDataWithSubscriptIndex:i].SHA256_2;
            BTKey *key = keys[i];
            NSData *signedHash = ((BTScriptChunk *)((BTScript *)scripts[i]).chunks[0]).data;
            if (![key verify:unSignHash signature:signedHash])
                return NO;
        }
        return YES;
    } else {
        return NO;
    }
}

// Returns the binary transaction data that needs to be hashed and signed with the private key for the tx input at
// subscriptIndex. A subscriptIndex of NSNotFound will return the entire signed transaction
- (NSData *)toDataWithSubscriptIndex:(NSUInteger)subscriptIndex
{
    NSMutableData *d = [NSMutableData dataWithCapacity:self.size];

    [d appendUInt32:self.version];
    [d appendVarInt:self.hashes.count];

    for (NSUInteger i = 0; i < self.hashes.count; i++) {
        [d appendData:self.hashes[i]];
        [d appendUInt32:[self.indexes[i] unsignedIntValue]];

        if ([self isSigned] && subscriptIndex == NSNotFound) {
            [d appendVarInt:[self.signatures[i] length]];
            [d appendData:self.signatures[i]];
        }
        else if (i == subscriptIndex) {
            //TODO: to fully match the reference implementation, OP_CODESEPARATOR related checksig logic should go here
            [d appendVarInt:[self.inScripts[i] length]];
            [d appendData:self.inScripts[i]];
        }
        else [d appendVarInt:0];
        
        [d appendUInt32:[self.sequences[i] unsignedIntValue]];
    }
    
    [d appendVarInt:self.addresses.count];
    
    for (NSUInteger i = 0; i < self.addresses.count; i++) {
        [d appendUInt64:[self.amounts[i] unsignedLongLongValue]];
        [d appendVarInt:[self.outScripts[i] length]];
        [d appendData:self.outScripts[i]];
    }
    
    [d appendUInt32:self.lockTime];
    
    if (subscriptIndex != NSNotFound) {
        [d appendUInt32:SIG_HASH_ALL];
    }
    
    return d;
}

- (NSData *)toDataWithSubscriptIndex:(NSUInteger)subscriptIndex withInScripts:(NSArray *)inScripts;
{
    NSMutableData *d = [NSMutableData dataWithCapacity:self.size];

    [d appendUInt32:self.version];
    [d appendVarInt:self.hashes.count];

    for (NSUInteger i = 0; i < self.hashes.count; i++) {
        [d appendData:self.hashes[i]];
        [d appendUInt32:[self.indexes[i] unsignedIntValue]];

        if ([self isSigned] && subscriptIndex == NSNotFound) {
            [d appendVarInt:[self.signatures[i] length]];
            [d appendData:self.signatures[i]];
        }
        else if (i == subscriptIndex) {
            //TODO: to fully match the reference implementation, OP_CODESEPARATOR related checksig logic should go here
            [d appendVarInt:[inScripts[i] length]];
            [d appendData:inScripts[i]];
        }
        else [d appendVarInt:0];

        [d appendUInt32:[self.sequences[i] unsignedIntValue]];
    }

    [d appendVarInt:self.addresses.count];

    for (NSUInteger i = 0; i < self.addresses.count; i++) {
        [d appendUInt64:[self.amounts[i] unsignedLongLongValue]];
        [d appendVarInt:[self.outScripts[i] length]];
        [d appendData:self.outScripts[i]];
    }

    [d appendUInt32:self.lockTime];

    if (subscriptIndex != NSNotFound) {
        [d appendUInt32:SIG_HASH_ALL];
    }

    return d;
}

- (NSData *)toData
{
    return [self toDataWithSubscriptIndex:NSNotFound];
}

- (size_t)size
{
    //TODO: not all keys come from this wallet (private keys can be swept), might cause a lower than standard tx fee
    size_t sigSize = 149; // electrum seeds generate uncompressed keys, bip32 uses compressed
//    size_t sigSize = 181;

    return (size_t) (8 + [NSMutableData sizeOfVarInt:self.hashes.count] + [NSMutableData sizeOfVarInt:self.addresses.count] +
               sigSize*self.hashes.count + 34*self.addresses.count);
}

// priority = sum(input_amount_in_satoshis*input_age_in_blocks)/size_in_bytes
- (uint64_t)priorityForAmounts:(NSArray *)amounts withAges:(NSArray *)ages
{
    uint64_t p = 0;
    
    if (amounts.count != self.hashes.count || ages.count != self.hashes.count || [ages containsObject:@(0)]) return 0;
    
    for (NSUInteger i = 0; i < amounts.count; i++) {    
        p += [amounts[i] unsignedLongLongValue]*[ages[i] unsignedLongLongValue];
    }
    
    return p/self.size;
}

// the block height after which the transaction can be confirmed without a fee, or TX_UNCONFIRMRED for never
- (uint32_t)blockHeightUntilFreeForAmounts:(NSArray *)amounts withBlockHeights:(NSArray *)heights
{
    if (amounts.count != self.hashes.count || heights.count != self.hashes.count ||
        self.size > TX_FREE_MAX_SIZE || [heights containsObject:@(TX_UNCONFIRMED)]) {
        return TX_UNCONFIRMED;
    }

    for (NSNumber *amount in self.amounts) {
        if (amount.unsignedLongLongValue < TX_MIN_OUTPUT_AMOUNT) return TX_UNCONFIRMED;
    }

    uint64_t amountTotal = 0, amountsByHeights = 0;
    
    for (NSUInteger i = 0; i < amounts.count; i++) {
        amountTotal += [amounts[i] unsignedLongLongValue];
        amountsByHeights += [amounts[i] unsignedLongLongValue]*[heights[i] unsignedLongLongValue];
    }
    
    if (amountTotal == 0) return TX_UNCONFIRMED;
    
    // this could possibly overflow a uint64 for very large input amounts and far in the future block heights,
    // however we should be okay up to the largest current bitcoin balance in existence for the next 40 years or so,
    // and the worst case is paying a transaction fee when it's not needed
    return (uint32_t)((TX_FREE_MIN_PRIORITY*(uint64_t)self.size + amountsByHeights + amountTotal - 1llu)/amountTotal);
}

- (uint64_t)standardFee
{
    return ((self.size + 999)/1000)*TX_FEE_PER_KB;
}

- (void)sawByPeer;{
    [[BTTxProvider instance] txSentBySelfHasSaw:self.txHash];
    self.sawByPeerCnt += 1;
}

// returns the fee for the given transaction if all its inputs are from wallet transactions, UINT64_MAX otherwise
- (uint64_t)feeForTransaction;{
    uint64_t amount = 0;
    NSUInteger i = 0;

    for (NSData *hash in self.inputHashes) {
        BTTx *tx = [BTTx txWithTxItem:[[BTTxProvider instance] getTxDetailByTxHash:hash]];
        uint32_t n = [self.inputIndexes[i++] unsignedIntValue];

        if (n >= tx.outputAmounts.count) return UINT64_MAX;
        amount += [tx.outputAmounts[n] unsignedLongLongValue];
    }

    for (NSNumber *amt in self.outputAmounts) {
        amount -= amt.unsignedLongLongValue;
    }

    return amount;
}

// Returns the block height after which the transaction is likely to be processed without including a fee. This is based
// on the default satoshi client settings, but on the real network it's way off. In testing, a 0.01btc transaction that
// was expected to take an additional 90 days worth of blocks to confirm was confirmed in under an hour by Eligius pool.
- (uint32_t)blockHeightUntilFree; {
    // TODO: calculate estimated time based on the median priority of free transactions in last 144 blocks (24hrs)
    NSMutableArray *amounts = [NSMutableArray array], *heights = [NSMutableArray array];
    NSUInteger i = 0;

    for (NSData *hash in self.inputHashes) { // get the amounts and block heights of all the transaction inputs
        BTTx *tx = [BTTx txWithTxItem:[[BTTxProvider instance] getTxDetailByTxHash:hash]];
        uint32_t n = [self.inputIndexes[i++] unsignedIntValue];

        if (n >= tx.outputAmounts.count) break;
        [amounts addObject:tx.outputAmounts[n]];
        [heights addObject:@(tx.blockHeight)];
    };

    return [self blockHeightUntilFreeForAmounts:amounts withBlockHeights:heights];
}

// returns the amount received to the wallet by the transaction (total outputs to change and/or recieve addresses)
- (uint64_t)amountReceivedFrom:(BTAddress *)addr;{
    uint64_t amount = 0;
    NSUInteger n = 0;

    for (NSString *address in self.outputAddresses) {
        if ([addr.address isEqualToString:address])
            amount += [self.outputAmounts[n] unsignedLongLongValue];
        n++;
    }

    return amount;
}

// returns the amount sent from the wallet by the transaction (total wallet outputs consumed, change and fee included)
- (uint64_t)amountSentFrom:(BTAddress *)addr;{
    uint64_t amount = 0;
    NSUInteger i = 0;

    for (NSData *hash in self.inputHashes) {
        BTTx *tx = [BTTx txWithTxItem:[[BTTxProvider instance] getTxDetailByTxHash:hash]];
        uint32_t n = [self.inputIndexes[i++] unsignedIntValue];

        if (n < tx.outputAddresses.count && [addr.address isEqualToString:tx.outputAddresses[n]]) {
            amount += [tx.outputAmounts[n] unsignedLongLongValue];
        }
    }

    return amount;
}

- (uint64_t)amountSentTo:(NSString *)addr;{
    uint64_t amount = 0;
    NSUInteger n = 0;

    for (NSString *address in self.outputAddresses) {
        if ([addr isEqualToString:address])
            amount += [self.outputAmounts[n] unsignedLongLongValue];
        n++;
    }

    return amount;
}

- (int64_t)deltaAmountFrom:(BTAddress *)addr;{
    uint64_t receive = 0;
    uint64_t sent = 0;
    NSUInteger i = 0;

    for (NSString *address in self.outputAddresses) {
        if ([addr.address isEqualToString:address])
            receive += [self.outputAmounts[i] unsignedLongLongValue];
        i++;
    }

    i = 0;
    for (NSData *hash in self.inputHashes) {
        BTTx *tx = [BTTx txWithTxItem:[[BTTxProvider instance] getTxDetailByTxHash:hash]];
        uint32_t n = [self.inputIndexes[i++] unsignedIntValue];

        if (n < tx.outputAddresses.count && [addr.address isEqualToString:tx.outputAddresses[n]]) {
            sent += [tx.outputAmounts[n] unsignedLongLongValue];
        }
    }
    return receive - sent;
}

- (uint)confirmationCnt;{
    if (self.blockHeight == TX_UNCONFIRMED){
        return 0;
    } else {
        return [[BTBlockChain instance] lastBlock].height - self.blockHeight + 1;
    }
}

- (NSArray *)unsignedInHashes;{
    NSMutableArray *result = [NSMutableArray new];
    for (NSUInteger i = 0; i < self.hashes.count; i++) {
        [result addObject:[self toDataWithSubscriptIndex:i].SHA256_2];
    }
    return result;
}

- (BOOL)signWithSignatures:(NSArray *)signatures;{
    for (NSUInteger i = 0; i < signatures.count; i++) {
        self.signatures[i] = signatures[i];
    }
    if (![self isSigned])
        return NO;

    _txHash = self.data.SHA256_2;

    return YES;
}

- (NSUInteger)hash
{
    if (self.txHash.length < sizeof(NSUInteger)) return [super hash];
    return *(const NSUInteger *)self.txHash.bytes;
}

- (BOOL)isEqual:(id)object
{
    return self == object || ([object isKindOfClass:[BTTx class]] && [[object txHash] isEqual:self.txHash]);
}

- (BTTxItem *)formatToTxItem
{
    BTTxItem *txItem = [BTTxItem new];
    txItem.txHash = self.txHash;
    txItem.blockNo = self.blockHeight;
    txItem.source = self.source;
    txItem.sawByPeerCnt = self.sawByPeerCnt;
    txItem.txTime = self.txTime;
    txItem.txVer = self.version;
    txItem.txLockTime = self.lockTime;
    txItem.ins = [NSMutableArray new];
    txItem.outs = [NSMutableArray new];
    uint idx = 0;
    while (idx < self.inputHashes.count){
        [txItem.ins addObject:[self setInItemFromTx:self inSn:idx++]];
    }
    idx = 0;
    while (idx < self.outputAddresses.count){
        [txItem.outs addObject:[self setOutItemFromTx:self outSn:idx++]];
    }
    return txItem;
}

//- (BTTxItem *)formatToTxItemWithoutDetail;{
//    BTTxItem *txItem = [BTTxItem new];
//    txItem.txHash = self.txHash;
//    txItem.blockNo = self.blockHeight;
//    txItem.source = self.source;
//    txItem.sawByPeerCnt = self.sawByPeerCnt;
//    txItem.ins = [NSMutableArray new];
//    txItem.outs = [NSMutableArray new];
//    return txItem;
//}

- (BTOutItem *)setOutItemFromTx:(BTTx *)tx outSn:(uint)outSn
{
    BTOutItem *outItem = [BTOutItem new];
    outItem.txHash = tx.txHash;
    outItem.outSn = outSn;
    outItem.outAddress = tx.outputAddresses[outSn] == [NSNull null] ? nil : tx.outputAddresses[outSn];
    outItem.outScript = tx.outputScripts[outSn];
    outItem.outValue = [tx.outputAmounts[outSn] unsignedLongValue];
    return outItem;
}

- (BTInItem *)setInItemFromTx:(BTTx *)tx inSn:(uint)inSn
{
    BTInItem *inItem = [BTInItem new];
    inItem.txHash = tx.txHash;
    inItem.inSn = inSn;
//    inItem.inScript = tx.inputScripts[in_sn];
    inItem.prevTxHash = tx.inputHashes[inSn];
    inItem.prevOutSn = [tx.inputIndexes[inSn] unsignedIntValue];
    inItem.inSignature = tx.inputSignatures[inSn];
    inItem.inSequence = [tx.inputSequences[inSn] unsignedIntValue];
    return inItem;
}

+ (instancetype)txWithTxItem:(BTTxItem *)txItem;{
    if (txItem == nil) return nil;
    return [[self alloc] initWithTxItem:txItem];
}

- (instancetype)initWithTxItem:(BTTxItem *)txItem;{
    if (! (self = [self init])) return nil;
    _txHash = txItem.txHash;
    _blockHeight = txItem.blockNo;
    _source = txItem.source;
    _sawByPeerCnt = txItem.sawByPeerCnt;
    _txTime = txItem.txTime;
    _version = txItem.txVer;
    _lockTime = txItem.txLockTime;

    for (BTInItem *inItem in txItem.ins) {
        [self addInputHash:inItem.prevTxHash index:inItem.prevOutSn script:nil signature:inItem.inSignature
                  sequence:inItem.inSequence];
    }

    for (BTOutItem *outItem in txItem.outs){
        [self addOutputScript:outItem.outScript amount:outItem.outValue];
    }
    return self;
}

- (NSData *) hashForSignature:(NSUInteger) inputIndex connectedScript:(NSData *) connectedScript sigHashType:(uint8_t) sigHashType; {
    NSMutableArray *inputHashes = [NSMutableArray arrayWithArray:self.inputHashes];
    NSMutableArray *inputIndexes = [NSMutableArray arrayWithArray:self.inputIndexes];
    NSMutableArray *inputScripts = [NSMutableArray arrayWithArray:self.inputScripts];
    NSMutableArray *inputSignatures = [NSMutableArray arrayWithArray:self.inputSignatures];
    NSMutableArray *inputSequences = [NSMutableArray arrayWithArray:self.inputSequences];
    NSMutableArray *outputScripts = [NSMutableArray arrayWithArray:self.outputScripts];
    NSMutableArray *outputAmounts = [NSMutableArray arrayWithArray:self.outputAmounts];
    for (NSUInteger i = 0; i < inputHashes.count; i++){
        inputScripts[i] = [NSData data];
    }
    if (connectedScript != nil) {
        NSMutableData *codeSeparator = [NSMutableData secureData];
        [codeSeparator appendUInt8:OP_CODESEPARATOR];
        connectedScript = [BTScript removeAllInstancesOf:connectedScript and:codeSeparator];
        inputScripts[inputIndex] = connectedScript;
    } else {
        inputScripts[inputIndex] = self.inputScripts[inputIndex];
    }


    if ((sigHashType & 0x1f) == 2) {
        outputScripts = [NSMutableArray new];
        for (NSUInteger i = 0; i < inputHashes.count; i++) {
            if (i != inputIndex) {
                inputSequences[i] = @0;
            }
        }
    } else if ((sigHashType & 0x1f) == 3) {
        if (inputIndex >= outputScripts.count) {
            // Satoshis bug is that SignatureHash was supposed to return a hash and on this codepath it
            // actually returns the constant "1" to indicate an error, which is never checked for. Oops.
            return [@"0100000000000000000000000000000000000000000000000000000000000000" hexToData];
        }
        outputAmounts = [NSMutableArray arrayWithArray:[outputAmounts subarrayWithRange:NSMakeRange(0, inputIndex + 1)]];
        outputScripts = [NSMutableArray arrayWithArray:[outputScripts subarrayWithRange:NSMakeRange(0, inputIndex + 1)]];

        for (NSUInteger i = 0; i < inputIndex; i++) {
            outputAmounts[i] = @0xffffffffffffffff;
            outputScripts[i] = [NSData data];
        }
        for (NSUInteger i = 0; i < inputHashes.count; i++){
            if (i != inputIndex) {
                inputSequences[i] = @0;
            }
        }
    }

    if ((sigHashType & 0x80) == 0x80) {
        // SIGHASH_ANYONECANPAY means the signature in the input is not broken by changes/additions/removals
        // of other inputs. For example, this is useful for building assurance contracts.
        inputHashes = [NSMutableArray arrayWithArray:@[inputHashes[inputIndex]]];
        inputIndexes = [NSMutableArray arrayWithArray:@[inputIndexes[inputIndex]]];
        inputScripts = [NSMutableArray arrayWithArray:@[inputScripts[inputIndex]]];
        inputSignatures = [NSMutableArray arrayWithArray:@[inputSignatures[inputIndex]]];
        inputSequences = [NSMutableArray arrayWithArray:@[inputSequences[inputIndex]]];
    }

    NSMutableData *d = [NSMutableData secureData];

    [d appendUInt32:self.version];
    [d appendVarInt:inputHashes.count];

    for (NSUInteger i = 0; i < inputHashes.count; i++) {
        [d appendData:inputHashes[i]];
        [d appendUInt32:[inputIndexes[i] unsignedIntValue]];
        [d appendVarInt:[inputScripts[i] length]];
        [d appendData:inputScripts[i]];
        [d appendUInt32:[inputSequences[i] unsignedIntValue]];
    }

    [d appendVarInt:outputAmounts.count];

    for (NSUInteger i = 0; i < outputAmounts.count; i++) {
        [d appendUInt64:[outputAmounts[i] unsignedLongLongValue]];
        [d appendVarInt:[outputScripts[i] length]];
        [d appendData:outputScripts[i]];
    }

    [d appendUInt32:self.lockTime];

    if (inputIndex != NSNotFound) {
        [d appendUInt32:sigHashType];
    }

    return [d SHA256_2];
}

- (BOOL)verify; {
    if (self.inputHashes.count == 0 || self.outputAmounts.count == 0)
        return NO;

//    if (this.getMessageSize() > Block.MAX_BLOCK_SIZE)
//        throw new VerificationException("Transaction larger than MAX_BLOCK_SIZE");
    uint64_t valueOut = 0;
    for (NSNumber *outAmount in self.outputAmounts) {
        // amount < 0
        uint64_t outAmountValue = [outAmount unsignedLongLongValue];
        if (outAmountValue > 2100000000000000)
            return NO;
        valueOut += outAmountValue;
    }
    BOOL isCoinBase = NO;
    if (self.inputHashes.count == 1 && [self.inputHashes[0] isEqualToData:[@"0000000000000000000000000000000000000000000000000000000000000000" hexToData]]
            && [self.indexes[0] isEqual:@0xFFFFFFFFL]) {
        isCoinBase = YES;
    }

    if (isCoinBase) {
        if ( ((NSData *)self.inputSignatures[0]).length < 2 || ((NSData *)self.inputSignatures[0]).length > 100)
            return NO;
    } else {
        for (NSData *inputHash in self.inputHashes) {
            if ([inputHash isEqualToData:[@"0000000000000000000000000000000000000000000000000000000000000000" hexToData]]
                    && [self.indexes[0] isEqual:@0xFFFFFFFFL])
                return NO;
        }
    }
    NSMutableSet *prevOutSet = [NSMutableSet new];
    for (NSUInteger i = 0; i < self.inputIndexes.count; i++) {
        NSMutableData *d = [NSMutableData dataWithCapacity:CC_SHA256_DIGEST_LENGTH + sizeof(uint32_t)];
        [d appendData:self.inputHashes[i]];
        [d appendUInt32:[self.inputIndexes[i] unsignedIntValue]];
        if ([prevOutSet containsObject:d]) {
            return NO;
        } else {
            [prevOutSet addObject:d];
        }
    }

    return YES;
}

- (void)setInScript:(NSData *)script forInHash:(NSData *)inHash andInIndex:(NSUInteger) inIndex;{
    for (NSUInteger i = 0; i < self.inputIndexes.count; i++) {
        if ([self.inputHashes[i] isEqualToData:inHash] && [self.inputIndexes[i] isEqual:@(inIndex)]) {
            self.inScripts[i] = script;
        }
    }
}
@end
