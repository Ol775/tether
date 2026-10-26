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

- A TV with no DUID that gets a new IP address looks like a new TV: its restore points and remembered locks stay under the old address.
- The normal SDB connection cannot root the TV or defeat Samsung's locks. An explicit, separately configured
  [experimental root-command adapter](../root-commands.md) is available; compatibility is unverified and those
  commands bypass automatic restore points. Firmware modification is not provided by Tether.
- TVs from before 2019 are refused.
- An open port 26101 confirms TCP reachability, but not a working SDB session. A generic “failed to connect” message
  alone does not identify the cause. Confirm the Host PC IP and fully restart the TV before retrying.
- There is no raw shell for TVs in this release; most TVs report the shell as disabled.

## Certificates

Installing a package needs a valid Samsung signature covering this TV. In Tether, open **Certificate setup…** from
Overview or Apps. **Open Certificate Manager** creates a Samsung → TV profile or imports existing `.p12` certificates;
add the connected TV in its distributor step. If Certificate Manager is missing, use **Open Package Manager** to install
Certificate Manager and Samsung Certificate Extension. Samsung account sign-in and certificate creation stay in Samsung’s tools.

If you already have a signing profile, choose its **profiles.xml** file in Tether, then **Refresh status**. Tether configures
Samsung’s CLI to use that profile; it does not copy your private keys or passwords. Selecting a profile does not re-sign
an existing `.wgt`: sign the package with the profile in Samsung’s tools before installing it. A profile being available
also does not prove it covers this TV; Samsung verifies the package signature during installation.

The CLI is launched through its bundled Java entry point so SDK paths such as macOS Application Support work correctly.
Tool failures are reported separately from missing profiles. Certificate setup is separate from connecting to the TV or
listing apps; those actions do not need a signing certificate.
