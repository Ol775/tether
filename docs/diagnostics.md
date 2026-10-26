# Connection diagnostics and recovery

Open **Help → Connection diagnostics…**, use the stethoscope in the toolbar, or choose **Diagnostics…** in Add a device. Select the device service, enter its IP address and debugging port, then press **Run diagnostics**.

Checks read status only; they do not install, remove or change anything on the device. You can stop the checks. Each result describes what was actually observed:

- **Debugging port:** a successful TCP connection establishes network reachability, not authorisation or a working debugging session.
- **Samsung network service:** reads a small selection of connection fields from the TV's port 8001 status endpoint, when available. It checks Developer Mode and whether Host PC IP matches any active Wi-Fi or Ethernet IPv4 address on this Mac. Missing status does not by itself mean the TV is offline.
- **ADB/SDB session:** checks whether the requested address is listed as ready. For a ready Samsung TV it also reads capabilities. Diagnostics do not connect automatically or reboot the TV.

If the debugging port and Samsung network service are both unreachable, check device power and the network path. If several Wi-Fi clients are unreachable while wired clients work, investigate the access point's client forwarding. Do not assume Developer Mode is wrong just because a connection times out.

If the port is open but the debugging session fails, use **Restart SDB…** or **Restart ADB…**. These actions briefly disconnect the affected devices and then try to reconnect devices Tether had listed, plus the address entered for that service. Reconnection failures remain visible in the panel.

- Samsung's **SDB server is shared** with other Samsung tools on this Mac. Restarting it affects their TV sessions too.
- Tether's **ADB server uses port 5038**. Restarting it leaves the system ADB server on 5037 running. Wireless Android devices may still require pairing or approval on the device.
- **Restart Tether** reopens the packaged app and attempts to reconnect previously connected network devices. It does not restart ADB or SDB; those controls are separate. The app restart control is unavailable for a bare `swift run` executable.

Service and app restarts are blocked during operations, including installs, removals, restores, console commands and app updates. Starting another connection while recovery is running is also blocked.

**Copy report** copies the timestamp, service, target and check results. It includes local IP addresses, so review it before sharing. Tether does not upload diagnostic reports. Full Samsung metadata, DUIDs, tokens and certificate files are not included.
