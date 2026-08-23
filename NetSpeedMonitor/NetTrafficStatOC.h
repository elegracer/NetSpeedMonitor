#pragma once

#import <Foundation/Foundation.h>

#import "NetTrafficStatCpp.hpp"

NS_ASSUME_NONNULL_BEGIN

@interface NetTrafficStatOC : NSObject
@property (nonatomic, strong) NSNumber *delta_ts_sec;
@property (nonatomic, assign) NSInteger delta_ibytes;
@property (nonatomic, assign) NSInteger delta_obytes;
@property (nonatomic, assign) long long total_ibytes;
@property (nonatomic, assign) long long total_obytes;
@property (nonatomic, strong) NSNumber *ibytes_per_sec;
@property (nonatomic, strong) NSNumber *obytes_per_sec;
@property (nonatomic, assign) BOOL isUp;
@end


@interface NetTrafficStatReceiver : NSObject
@property (nonatomic, strong) NSMutableDictionary *netTrafficStatMap;
- (void)reset;
- (nullable NSMutableDictionary *)getNetTrafficStatMap;
@end

NS_ASSUME_NONNULL_END
