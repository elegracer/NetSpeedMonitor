#include "../NetSpeedMonitor/NetTrafficStatCpp.hpp"

#include <cassert>
#include <iostream>

int main() {
    NetTrafficStatGenerator generator;
    assert(generator.update() == 0);
    const auto first = generator.get_latest_net_traffic_stat_map();
    assert(!first.empty());
    assert(generator.update() == 0);
    const auto second = generator.get_latest_net_traffic_stat_map();
    assert(!second.empty());
    std::cout << "C++ traffic runtime tests passed\n";
    return 0;
}
