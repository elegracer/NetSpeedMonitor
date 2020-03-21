//
//     NetSpeedStat.m
//
//     Reader object for network throughput info
//
//     Copyright (c) 2002-2014 Alex Harper
//
//     This file is part of MenuMeters.
//
//     MenuMeters is free software; you can redistribute it and/or modify
//     it under the terms of the GNU General Public License version 2 as
//     published by the Free Software Foundation.
//
//     MenuMeters is distributed in the hope that it will be useful,
//     but WITHOUT ANY WARRANTY; without even the implied warranty of
//     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//     GNU General Public License for more details.
//
//     You should have received a copy of the GNU General Public License
//     along with MenuMeters; if not, write to the Free Software
//     Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
//

#import "NetSpeedStat.h"

#import <AppKit/AppKit.h>

@implementation NetSpeedStat

- (id)init {
    self = [super init];
    if (!self) {
        return nil;
    }

    // Prefetch the data first time
    [self getStatsForInterval:1.0f];

    return self;
}

- (void)dealloc {
    // Free our sysctl buffer
    if (sysctlBuffer) {
        free(sysctlBuffer);
    }
}

// This function does not take pppoe into account
- (NSDictionary *)getStatsForInterval:(NSTimeInterval)sampleInterval {
    // Get sizing info from sysctl and resize as needed.
    int mib[] = { CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST, 0 };
    size_t currentSize = 0;
    if (sysctl(mib, 6, NULL, &currentSize, NULL, 0) != 0) {
        return nil;
    }
    if (!sysctlBuffer || (currentSize > sysctlBufferSize)) {
        if (sysctlBuffer) {
            free(sysctlBuffer);
        }
        sysctlBufferSize = 0;
        sysctlBuffer = malloc(currentSize);
        if (!sysctlBuffer) {
            return nil;
        }
        sysctlBufferSize = currentSize;
    }

    // Read in new data
    if (sysctl(mib, 6, sysctlBuffer, &currentSize, NULL, 0) != 0) {
        return nil;
    }

    // Walk through the reply
    uint8_t *currentData = sysctlBuffer;
    uint8_t *currentDataEnd = sysctlBuffer + currentSize;
    NSMutableDictionary *newStats = [NSMutableDictionary dictionary];
    while (currentData < currentDataEnd) {
        // Expecting interface data
        struct if_msghdr *ifmsg = (struct if_msghdr *)currentData;
        if (ifmsg->ifm_type != RTM_IFINFO) {
            currentData += ifmsg->ifm_msglen;
            continue;
        }
        // Must not be loopback
        if (ifmsg->ifm_flags & IFF_LOOPBACK) {
            currentData += ifmsg->ifm_msglen;
            continue;
        }
        // Only look at link layer items
        struct sockaddr_dl *sdl = (struct sockaddr_dl *)(ifmsg + 1);
        if (sdl->sdl_family != AF_LINK) {
            currentData += ifmsg->ifm_msglen;
            continue;
        }
        // Build the interface name to string so we can key off it
        NSString *interfaceName = [[NSString alloc]
                                   initWithBytes:sdl->sdl_data
                                   length:sdl->sdl_nlen
                                   encoding:NSASCIIStringEncoding];
        if (!interfaceName) {
            currentData += ifmsg->ifm_msglen;
            continue;
        }
        // Load in old statistics for this interface
        NSDictionary *oldStats = [lastData objectForKey:interfaceName];

        if (oldStats && (ifmsg->ifm_flags & IFF_UP)) {
            // The data is sized at uint32_t, so we need uint64_t to avoid overflow
            uint64_t lastTotalIn = [[oldStats objectForKey:@"totalin"] unsignedLongLongValue];
            uint64_t lastTotalOut = [[oldStats objectForKey:@"totalout"] unsignedLongLongValue];
            // Values are always 32 bit and can overflow
            uint32_t lastIfIn = [[oldStats objectForKey:@"ifin"] unsignedIntValue];
            uint32_t lastIfOut = [[oldStats objectForKey:@"ifout"] unsignedIntValue];
            // New totals
            uint64_t totalIn = 0;
            uint64_t totalOut = 0;
            if (lastIfIn > ifmsg->ifm_data.ifi_ibytes) {
                totalIn = lastTotalIn + ifmsg->ifm_data.ifi_ibytes + UINT_MAX - lastIfIn + 1;
            } else {
                totalIn = lastTotalIn + (ifmsg->ifm_data.ifi_ibytes - lastIfIn);
            }
            if (lastIfOut > ifmsg->ifm_data.ifi_obytes) {
                totalOut = lastTotalOut + ifmsg->ifm_data.ifi_obytes + UINT_MAX - lastIfOut + 1;
            } else {
                totalOut = lastTotalOut + (ifmsg->ifm_data.ifi_obytes - lastIfOut);
            }
            // New deltas (64-bit overflow guard, full paranoia)
            uint64_t deltaIn = (totalIn > lastTotalIn) ? (totalIn - lastTotalIn) : 0;
            uint64_t deltaOut = (totalOut > lastTotalOut) ? (totalOut - lastTotalOut) : 0;
            [newStats setObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                 [NSNumber numberWithUnsignedInt:ifmsg->ifm_data.ifi_ibytes],
                                 @"ifin",
                                 [NSNumber numberWithUnsignedInt:ifmsg->ifm_data.ifi_obytes],
                                 @"ifout",
                                 [NSNumber numberWithUnsignedLongLong:deltaIn],
                                 @"deltain",
                                 [NSNumber numberWithUnsignedLongLong:deltaOut],
                                 @"deltaout",
                                 [NSNumber numberWithUnsignedLongLong:totalIn],
                                 @"totalin",
                                 [NSNumber numberWithUnsignedLongLong:totalOut],
                                 @"totalout",
                                 nil]
                         forKey:interfaceName];
        } else {
            [newStats setObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                 // Paranoia, is this where the neg numbers came from?
                                 [NSNumber numberWithUnsignedInt:ifmsg->ifm_data.ifi_ibytes],
                                 @"ifin",
                                 [NSNumber numberWithUnsignedInt:ifmsg->ifm_data.ifi_obytes],
                                 @"ifout",
                                 [NSNumber numberWithUnsignedLongLong:ifmsg->ifm_data.ifi_ibytes],
                                 @"totalin",
                                 [NSNumber numberWithUnsignedLongLong:ifmsg->ifm_data.ifi_obytes],
                                 @"totalout",
                                 nil]
                         forKey:interfaceName];
        }

        // Continue on
        currentData += ifmsg->ifm_msglen;
    }

    // Store and return
    lastData = newStats;
    return newStats;
}

@end
