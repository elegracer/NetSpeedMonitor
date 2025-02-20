#import <Foundation/Foundation.h>

#import "NetTrafficStatSysctl.hpp"


@interface NetTrafficStatOC : NSObject
@property (nonatomic, strong) NSNumber *delta_ts_sec;
@property (nonatomic, assign) NSInteger delta_ibytes;
@property (nonatomic, assign) NSInteger delta_obytes;
@property (nonatomic, strong) NSNumber *ibytes_per_sec;
@property (nonatomic, strong) NSNumber *obytes_per_sec;
@end


@interface NetTrafficStatReceiver : NSObject
@property (nonatomic, strong) NSMutableDictionary *netTrafficStatMap;
- (void)reset;
- (NSMutableDictionary *)getNetTrafficStatMap;
@end
