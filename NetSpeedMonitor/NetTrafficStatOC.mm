#import "NetTrafficStatOC.h"

#import "NetTrafficStatCpp.hpp"

@implementation NetTrafficStatOC
@end

@implementation NetTrafficStatReceiver {
    NetTrafficStatGenerator netTrafficStatGenerator;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.netTrafficStatMap = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)reset {
    netTrafficStatGenerator = NetTrafficStatGenerator();
}

// This function does not take pppoe into account
- (NSMutableDictionary *)getNetTrafficStatMap {

    netTrafficStatGenerator.update();

    const NetTrafficStatMap net_traffic_stat_map =
    netTrafficStatGenerator.get_latest_net_traffic_stat_map();

    [_netTrafficStatMap removeAllObjects];
    for (const auto &[interface_name, net_traffic_stat] : net_traffic_stat_map) {
        NetTrafficStatOC *netTrafficStatsOC = [[NetTrafficStatOC alloc] init];
        netTrafficStatsOC.delta_ts_sec =
        [NSNumber numberWithDouble:net_traffic_stat.delta_ts_sec];
        netTrafficStatsOC.delta_ibytes = net_traffic_stat.delta_ibytes;
        netTrafficStatsOC.delta_obytes = net_traffic_stat.delta_obytes;
        netTrafficStatsOC.ibytes_per_sec =
        [NSNumber numberWithDouble:net_traffic_stat.ibytes_per_sec];
        netTrafficStatsOC.obytes_per_sec =
        [NSNumber numberWithDouble:net_traffic_stat.obytes_per_sec];

        NSString *key = [NSString stringWithCString:interface_name.c_str()
                                           encoding:NSASCIIStringEncoding];

        [_netTrafficStatMap setObject:netTrafficStatsOC forKey:key];
    }

    return _netTrafficStatMap;
}

@end
