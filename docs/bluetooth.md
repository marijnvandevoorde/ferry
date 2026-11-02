# Newer Fuji cameras: Bluetooth hand-off

Research notes for #44, from libfuji's `lib/bluetooth.c` (MIT, github.com/petabyt/libfuji). libfuji marks
much of this as unverified; nothing here has been tested by this project yet.

## How the newer cameras connect

Cameras from roughly 2019 on (X-T3/X-T30 and later; in practice X-T5, X-S20, X100VI, X-H2 and so on) pair with
the phone over Bluetooth Low Energy first. The phone then reads the camera's Wi-Fi network name and password over
Bluetooth, joins that network, and continues with the same PTP-over-TCP protocol this project already speaks
(port 55740). Newer firmware with *FUJIFILM XApp* then uses the newer gallery mode (#45).

## Steps

1. **Find the camera.** In pairing mode the camera advertises manufacturer data that contains a 4-byte token
   (type `0x02`). Without that data the camera isn't in pairing mode. The token is saved for reconnecting later.
2. **Connect.** A first-time pairing creates a BLE bond (the OS shows the pairing prompt).
3. **Acknowledge pairing.** Read the 4-byte status from *secure pairing* service `123d8f06-62a1-4935-9322-833c531ee225`,
   characteristic `f557d96b-8284-4667-8793-b971c1deca2a`, set byte 3 to `0x20`, and write it back.
   Older Bluetooth cameras use pairing service `91f1de68-dff6-466e-8b65-ff13b0f16fb8` and characteristic
   `aba356eb-9633-4e60-b73f-f52516dbd671` instead.
4. **Name the client.** Write the client name (UTF-8) to `85b9163e-62d1-49ff-a6f5-054b4630d4a1` in the pairing service.
5. **Subscribe** to the notification characteristics the app uses (configuration service
   `4c0020fe-f3b6-40de-acc9-77d129067b14`, notification service `4e941240-d01d-46b9-a5ea-67636806830b`, and others;
   see libfuji's subscription table). The camera seems to expect these before it starts its Wi-Fi.
6. **Read the Wi-Fi credentials** from the notification service `4e941240-…`:
   - network name: `bf6dc9cf-3606-4ec9-a4c8-d77576e93ea4`
   - password: `e809256a-915c-4967-92e8-53b7d4cad213`
7. **Join that network** and connect to the camera on port 55740 as usual. Cameras with remote version
   `0x20007` or later then use the XApp gallery mode (#45).

## Other services seen

| Service | What it seems to do |
|---------|--------------------|
| `6514eb81-…` shutter | Remote shutter (out of scope) |
| `3b46ec2b-…` geotag | The camera asks for the phone's location (out of scope) |
| `af854c2e-…` backup / status | Reads files such as `backup.dat` and an equipment-status JSON |
| `15ca59fe-…` lens | Lens name and firmware |
| `00001800-…` generic access | Device name |

## What this means for Fuji Import

- **macOS:** CoreBluetooth can do steps 1–6. Step 7, joining the camera's network automatically, needs CoreWLAN.
  That may not be allowed in the sandboxed App Store build (see #21); the fallback is to show the network name and
  password and let the user join it.
- **Windows and Linux:** the desktop app would need BLE in the sidecar (WinRT Bluetooth APIs, or BlueZ over D-Bus).
- **Testing:** vcam emulates no Bluetooth. This needs someone with an X-T5-era camera, ideally with packet captures
  of Fuji's app pairing.
