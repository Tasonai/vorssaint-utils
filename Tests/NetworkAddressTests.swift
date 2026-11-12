// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NetworkAddressTests {
    static func run(expect: (Bool, String) -> Void) {
        let running = UInt32(IFF_UP | IFF_RUNNING)
        expect(NetworkAddressService.includesLocalAddress(name: "en0", flags: running, family: AF_INET),
               "an up and running IPv4 interface is included")
        expect(!NetworkAddressService.includesLocalAddress(name: "lo0", flags: running, family: AF_INET),
               "the loopback interface is excluded")
        expect(!NetworkAddressService.includesLocalAddress(name: "utun3", flags: running, family: AF_INET),
               "a VPN tunnel is excluded, as on the rest of the network card")
        expect(!NetworkAddressService.includesLocalAddress(name: "bridge0", flags: running, family: AF_INET),
               "a bridge is excluded, as on the rest of the network card")
        expect(!NetworkAddressService.includesLocalAddress(name: "en0", flags: UInt32(IFF_UP), family: AF_INET),
               "an interface that is not running is excluded")
        expect(!NetworkAddressService.includesLocalAddress(name: "en0", flags: running, family: AF_INET6),
               "IPv6 interfaces are excluded from the local list")
        expect(NetworkAddressService.refreshTolerance >= 0.5
               && NetworkAddressService.refreshTolerance >= NetworkAddressService.refreshInterval * 0.15,
               "NetworkAddressService configures >=0.5s timer tolerance for XNU wakeup coalescing")
        let sectionSource = (try? String(contentsOfFile: "Sources/Vorssaint/UI/MenuPanel/NetworkSection.swift", encoding: .utf8)) ?? ""
        expect(sectionSource.contains("service.startMonitoring()")
               && sectionSource.contains("service.stopMonitoring()")
               && !sectionSource.contains("service.refreshLocalAddresses()"),
               "NetworkAddressBlock gates getifaddrs polling on visibility and panel state instead of SystemMonitor snapshots")
    }
}
