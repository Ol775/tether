# Android TV, Google TV and Shield setup

These use the same network `adb` as phones and Fire TV.

1. **Settings → System → About**, then click **Build** seven times to unlock Developer options.
2. **Settings → System → Developer options → USB debugging: On.** If you see **Wireless debugging**, turn that on too.
3. **Settings → Network & Internet** (or About → Status) shows the IP address.
4. In Tether choose **Add device → Android / Google TV**, enter the IP (port 5555, or the port Wireless debugging shows)
   and press Connect.
5. Approve **Allow USB debugging?** on the TV and tick **Always allow**.

If the TV has Wireless debugging with a pairing code, use **Add device → Phone or tablet** once to pair, then connect
on the main Wireless debugging port. Mac and TV must be on the same network, with no VPN intercepting local traffic.
