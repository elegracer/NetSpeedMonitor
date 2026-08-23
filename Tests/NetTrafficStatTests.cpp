#include "../NetSpeedMonitor/NetTrafficStatCpp.hpp"

#include <cassert>
#include <cstdint>
#include <iostream>

int main() {
    assert(counter_delta(200, 100) == 100);
    assert(counter_delta(25, UINT32_MAX - 24) == 50);
    assert(counter_delta(0, UINT32_MAX) == 1);
    std::cout << "C++ traffic tests passed\n";
    return 0;
}
