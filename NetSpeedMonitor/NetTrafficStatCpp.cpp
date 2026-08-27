#include "NetTrafficStatCpp.hpp"

#include <cstring>
#include <limits>
#include <net/if.h>
#include <net/if_dl.h>
#include <net/route.h>
#include <sys/sysctl.h>

int NetTrafficStatGenerator::update() {

    // Get sizing info from sysctl and alloc memory
    int mib[] = {CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0};
    size_t data_bytes = 0;
    if (sysctl(mib, 6, nullptr, &data_bytes, nullptr, 0) != 0) {
        return 1;
    }
    if (sysctl_buffer.size() < data_bytes) {
        sysctl_buffer = std::vector<uint8_t>(data_bytes);
    }

    // Read in new data
    if (sysctl(mib, 6, sysctl_buffer.data(), &data_bytes, NULL, 0) != 0) {
        return 1;
    }

    const time_point_type tp_retrieval = clock_type::now();
    std::set<std::string> seen_interfaces;

    uint8_t* const sysctl_buffer_ptr = sysctl_buffer.data();
    uint8_t* data_ptr_cur = sysctl_buffer_ptr;
    uint8_t* const data_ptr_end = sysctl_buffer_ptr + data_bytes;
    while (data_ptr_cur < data_ptr_end) {
        const size_t remaining = static_cast<size_t>(data_ptr_end - data_ptr_cur);
        if (remaining < sizeof(uint16_t) + 2 * sizeof(uint8_t)) {
            return 1;
        }

        uint16_t message_length = 0;
        memcpy(&message_length, data_ptr_cur, sizeof(message_length));
        const uint8_t message_type = data_ptr_cur[3];
        if (message_length < sizeof(uint16_t) + 2 * sizeof(uint8_t) || message_length > remaining) {
            return 1;
        }
        uint8_t* const next_message = data_ptr_cur + message_length;
        if (message_type != RTM_IFINFO2) {
            data_ptr_cur = next_message;
            continue;
        }
        if (message_length < sizeof(if_msghdr2)) {
            return 1;
        }
        const auto* ifmsg = reinterpret_cast<const if_msghdr2*>(data_ptr_cur);
        // Must not be loopback
        if (ifmsg->ifm_flags & IFF_LOOPBACK) {
            data_ptr_cur = next_message;
            continue;
        }
        // Only look at link layer items
        const auto* sdl = reinterpret_cast<const sockaddr_dl*>(ifmsg + 1);
        const auto* sdl_bytes = reinterpret_cast<const uint8_t*>(sdl);
        if (sdl_bytes + offsetof(sockaddr_dl, sdl_data) > next_message ||
            sdl->sdl_family != AF_LINK ||
            sdl_bytes + offsetof(sockaddr_dl, sdl_data) + sdl->sdl_nlen > next_message) {
            data_ptr_cur = next_message;
            continue;
        }
        // Get the interface name
        const auto interface_name = std::string(sdl->sdl_data, sdl->sdl_nlen);
        if (interface_name.empty()) {
            data_ptr_cur = next_message;
            continue;
        }

        seen_interfaces.insert(interface_name);
        const bool is_up = (ifmsg->ifm_flags & IFF_UP) != 0;

        if (auto& net_traffic_stat = net_traffic_stat_map[interface_name]; //
            net_traffic_stat.is_valid() && is_up) {
            const auto last_net_traffic_stat = net_traffic_stat;
            net_traffic_stat.tp_retrieval = tp_retrieval;
            net_traffic_stat.ifi_ibytes = ifmsg->ifm_data.ifi_ibytes;
            net_traffic_stat.ifi_obytes = ifmsg->ifm_data.ifi_obytes;
            net_traffic_stat.is_up = true;
            net_traffic_stat.delta_ibytes =
                counter_delta(net_traffic_stat.ifi_ibytes, last_net_traffic_stat.ifi_ibytes);
            net_traffic_stat.delta_obytes =
                counter_delta(net_traffic_stat.ifi_obytes, last_net_traffic_stat.ifi_obytes);
            net_traffic_stat.total_ibytes = last_net_traffic_stat.total_ibytes + net_traffic_stat.delta_ibytes;
            net_traffic_stat.total_obytes = last_net_traffic_stat.total_obytes + net_traffic_stat.delta_obytes;

            net_traffic_stat.delta_ts_sec =
                std::chrono::duration<double>(net_traffic_stat.tp_retrieval - last_net_traffic_stat.tp_retrieval)
                    .count();
            if (net_traffic_stat.delta_ts_sec >= 0.05) {
                net_traffic_stat.ibytes_per_sec =
                    static_cast<double>(net_traffic_stat.delta_ibytes) / net_traffic_stat.delta_ts_sec;
                net_traffic_stat.obytes_per_sec =
                    static_cast<double>(net_traffic_stat.delta_obytes) / net_traffic_stat.delta_ts_sec;
            } else {
                net_traffic_stat.ibytes_per_sec = 0.0;
                net_traffic_stat.obytes_per_sec = 0.0;
            }
        } else {
            net_traffic_stat.tp_retrieval = tp_retrieval;
            net_traffic_stat.ifi_ibytes = ifmsg->ifm_data.ifi_ibytes;
            net_traffic_stat.ifi_obytes = ifmsg->ifm_data.ifi_obytes;
            net_traffic_stat.is_up = is_up;
            net_traffic_stat.delta_ibytes = 0;
            net_traffic_stat.delta_obytes = 0;
            net_traffic_stat.total_ibytes = 0;
            net_traffic_stat.total_obytes = 0;

            net_traffic_stat.delta_ts_sec = 0.0;
            net_traffic_stat.ibytes_per_sec = 0.0;
            net_traffic_stat.obytes_per_sec = 0.0;
        }

        // Continue on
        data_ptr_cur = next_message;
    }

    // Remove interfaces that are no longer present in this update
    for (auto it = net_traffic_stat_map.begin(); it != net_traffic_stat_map.end(); ) {
        if (seen_interfaces.find(it->first) == seen_interfaces.end()) {
            it = net_traffic_stat_map.erase(it);
        } else {
            ++it;
        }
    }

    return 0;
}
