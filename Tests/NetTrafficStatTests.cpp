#include "../NetSpeedMonitor/NetTrafficStatCpp.hpp"

#include <cassert>
#include <cstdint>
#include <iostream>

int main() {
    assert(counter_delta(200, 100) == 100);
    assert(counter_delta(UINT64_MAX, UINT64_MAX - 100) == 100);
    assert(counter_delta(25, UINT64_MAX - 24) == 0);
    std::cout << "C++ traffic tests passed\n";
    return 0;
}
