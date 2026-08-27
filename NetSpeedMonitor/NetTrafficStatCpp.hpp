#pragma once

#include <map>
#include <chrono>
#include <cstdint>
#include <vector>
#include <set>
#include <string>

using clock_type = std::chrono::steady_clock;
using duration_type = std::chrono::nanoseconds;
using time_point_type = std::chrono::time_point<clock_type, duration_type>;

inline uint64_t counter_delta(uint64_t current, uint64_t previous) {
    // The kernel exposes 64-bit counters through NET_RT_IFLIST2. A decrease is
    // therefore a counter reset (interface recreation/driver reset), not a wrap.
    return current >= previous ? current - previous : 0;
}

struct NetTrafficStat {
    time_point_type tp_retrieval; // time_point where this stat is retrieved
    uint64_t ifi_ibytes = 0;      // raw 64-bit byte counter
    uint64_t ifi_obytes = 0;      // raw 64-bit byte counter
    uint64_t total_ibytes = 0;
    uint64_t total_obytes = 0;

    double delta_ts_sec = 0.0;
    uint64_t delta_ibytes = 0;
    uint64_t delta_obytes = 0;
    double ibytes_per_sec = 0.0;
    double obytes_per_sec = 0.0;
    bool is_up = false;

    bool is_valid() const { return tp_retrieval.time_since_epoch().count() > 0; }
};

using NetTrafficStatMap = std::map<std::string, NetTrafficStat>;

struct NetTrafficStatGenerator {
    NetTrafficStatGenerator() = default;
    ~NetTrafficStatGenerator() = default;

    NetTrafficStatMap get_latest_net_traffic_stat_map() const { return net_traffic_stat_map; }
    int update();

private:
    NetTrafficStatMap net_traffic_stat_map;
    std::vector<uint8_t> sysctl_buffer;
};
