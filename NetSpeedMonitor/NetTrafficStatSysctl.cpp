#include "NetTrafficStatSysctl.hpp"

#include <net/if.h>
#include <net/if_dl.h>
#include <net/route.h>
#include <sys/sysctl.h>

int NetTrafficStatGenerator::update() {

    // Get sizing info from sysctl and alloc memory
    int mib[] = {CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST, 0};
    size_t data_bytes = 0;
    if (sysctl(mib, 6, nullptr, &data_bytes, nullptr, 0) != 0) {
        return 1;
    }
    //   std::cout << data_bytes << std::endl;
    if (sysctl_buffer.size() < data_bytes) {
        sysctl_buffer = std::vector<uint8_t>(data_bytes);
    }

    // Read in new data
    if (sysctl(mib, 6, sysctl_buffer.data(), &data_bytes, NULL, 0) != 0) {
        return 1;
    }

    const time_point_type tp_retrieval = clock_type::now();

    uint8_t* const sysctl_buffer_ptr = sysctl_buffer.data();
    uint8_t* data_ptr_cur = sysctl_buffer_ptr;
    uint8_t* const data_ptr_end = sysctl_buffer_ptr + data_bytes;
    while (data_ptr_cur < data_ptr_end) {
        // Expecting interface data
        if_msghdr* ifmsg = (struct if_msghdr*)data_ptr_cur;
        if (ifmsg->ifm_type != RTM_IFINFO) {
            data_ptr_cur += ifmsg->ifm_msglen;
            continue;
        }
        // Must not be loopback
        if (ifmsg->ifm_flags & IFF_LOOPBACK) {
            data_ptr_cur += ifmsg->ifm_msglen;
            continue;
        }
        // Only look at link layer items
        sockaddr_dl* sdl = (struct sockaddr_dl*)(ifmsg + 1);
        if (sdl->sdl_family != AF_LINK) {
            data_ptr_cur += ifmsg->ifm_msglen;
            continue;
        }
        // Get the interface name
        const auto interface_name = std::string(sdl->sdl_data, sdl->sdl_nlen);
        if (interface_name.empty()) {
            data_ptr_cur += ifmsg->ifm_msglen;
            continue;
        }

        if (auto& net_traffic_stat = net_traffic_stat_map[interface_name]; //
            net_traffic_stat.is_valid() && (ifmsg->ifm_flags & IFF_UP)) {
            const auto last_net_traffic_stat = net_traffic_stat;
            net_traffic_stat.tp_retrieval = tp_retrieval;
            net_traffic_stat.ifi_ibytes = ifmsg->ifm_data.ifi_ibytes;
            net_traffic_stat.ifi_obytes = ifmsg->ifm_data.ifi_obytes;
            if (net_traffic_stat.ifi_ibytes < last_net_traffic_stat.ifi_ibytes) {
                net_traffic_stat.delta_ibytes = static_cast<int64_t>(net_traffic_stat.ifi_ibytes)
                                                + std::numeric_limits<uint32_t>::max()
                                                - last_net_traffic_stat.ifi_ibytes;
            } else {
                net_traffic_stat.delta_ibytes =
                    static_cast<int64_t>(net_traffic_stat.ifi_ibytes) - last_net_traffic_stat.ifi_ibytes;
            }
            if (net_traffic_stat.ifi_obytes < last_net_traffic_stat.ifi_obytes) {
                net_traffic_stat.delta_obytes = static_cast<int64_t>(net_traffic_stat.ifi_obytes)
                                                + std::numeric_limits<uint32_t>::max()
                                                - last_net_traffic_stat.ifi_obytes;
            } else {
                net_traffic_stat.delta_obytes =
                    static_cast<int64_t>(net_traffic_stat.ifi_obytes) - last_net_traffic_stat.ifi_obytes;
            }
            net_traffic_stat.total_ibytes = last_net_traffic_stat.total_ibytes + net_traffic_stat.delta_ibytes;
            net_traffic_stat.total_obytes = last_net_traffic_stat.total_obytes + net_traffic_stat.delta_obytes;

            net_traffic_stat.delta_ts_sec =
                std::chrono::duration<double>(net_traffic_stat.tp_retrieval - last_net_traffic_stat.tp_retrieval)
                    .count();
            net_traffic_stat.ibytes_per_sec = net_traffic_stat.delta_ibytes / (net_traffic_stat.delta_ts_sec + 1e-3);
            net_traffic_stat.obytes_per_sec = net_traffic_stat.delta_obytes / (net_traffic_stat.delta_ts_sec + 1e-3);
            if (net_traffic_stat.delta_ts_sec > 60.0) {
                net_traffic_stat.ibytes_per_sec = 0.0;
                net_traffic_stat.obytes_per_sec = 0.0;
            }
        } else {
            net_traffic_stat.tp_retrieval = tp_retrieval;
            net_traffic_stat.ifi_ibytes = ifmsg->ifm_data.ifi_ibytes;
            net_traffic_stat.ifi_obytes = ifmsg->ifm_data.ifi_obytes;
            net_traffic_stat.delta_ibytes = 0;
            net_traffic_stat.delta_obytes = 0;
            net_traffic_stat.total_ibytes = 0;
            net_traffic_stat.total_obytes = 0;

            net_traffic_stat.delta_ts_sec = 0.0;
            net_traffic_stat.ibytes_per_sec = 0.0;
            net_traffic_stat.obytes_per_sec = 0.0;
        }

        // Continue on
        data_ptr_cur += ifmsg->ifm_msglen;
    }

    return 0;
}
