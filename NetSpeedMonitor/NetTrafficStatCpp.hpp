#pragma once

#include <map>
#include <chrono>
#include <vector>

using clock_type = std::chrono::steady_clock;
using duration_type = std::chrono::nanoseconds;
using time_point_type = std::chrono::time_point<clock_type, duration_type>;

struct NetTrafficStat {
    time_point_type tp_retrieval; // time_point where this stat is retrieved
    uint32_t ifi_ibytes = 0;      // raw ifi_ibytes message
    uint32_t ifi_obytes = 0;      // raw ifi_obytes message
    int64_t total_ibytes = 0;     // i.e. ifi_ibytes accumulated in wider int type
    int64_t total_obytes = 0;     // i.e. ifi_obytes accumulated in wider int type

    double delta_ts_sec = 0.0;
    int64_t delta_ibytes = 0; // difference between 2 consecutive total_ibytes
    int64_t delta_obytes = 0; // difference between 2 consecutive total_obytes
    double ibytes_per_sec = 0.0;
    double obytes_per_sec = 0.0;

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
