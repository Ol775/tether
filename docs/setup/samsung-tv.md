# Samsung TV setup (Tizen, 2019 onwards)

Samsung TVs talk `sdb`, not `adb`, and the TV has to be put into Developer Mode first.

1. On the TV open **Apps**, then press **1 2 3 4 5** on the remote. A Developer mode window opens.
2. Turn **Developer mode** on and type this Mac's IP address into **Host PC IP**. Tether shows it under
   **Add device → Samsung TV**. Restart the TV.
3. In Tether choose **Add device → Samsung TV**. The first time, press **Set up Samsung tools** and accept Samsung's
   licence: Tether downloads Samsung's official command-line installer (about 265 MB), checks it against a pinned
   SHA-256 and installs it inside Tether's own folder. Nothing from Samsung is bundled or committed here.
4. Enter the TV's IP address (port 26101) and press **Connect**.

## What Tether can do on a TV

- List the apps on the TV and show what it knows about each.
- **Remove** apps. Tether saves a restore point, tries the removal, re-reads the TV and reports the result. Apps Samsung
  has locked stay installed and are shown as **Locked by Samsung**; Tether remembers them per TV.
- **Install** a signed `.wgt` or `.tpk`. Tether keeps a copy so removing that app later can be undone.
- **Revert** removals of apps Tether installed itself. Samsung's own preinstalled apps usually come back through
  Smart Hub; Tether says so rather than promising a restore.

## What it cannot do

- Rooting, firmware changes or defeating Samsung's locks are out of scope.
- TVs from before 2019 are refused.
- Some 2023+ models are reported to refuse `sdb` connections even with Developer Mode on. If Connect says the TV
  refused, that is the TV, not the network.
- There is no raw shell for TVs in this release; most TVs report the shell as disabled.

## Certificates

Installing needs a Samsung certificate that includes this TV's DUID, created in Samsung's Certificate Manager (part of
the tools Tether installs). Tether shows **Certificate ready**, **missing**, **not for this TV** or **can't tell** on the
Overview and Apps screens. Whether certificate creation can be scripted without Samsung's sign-in is unresolved and
tracked in [tizen-device-checklist.md](../tizen-device-checklist.md).
