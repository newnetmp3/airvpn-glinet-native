# AirVPN GL.iNet Native

AirVPN integration for the GL.iNet Admin Panel on a Flint 2 (GL-MT6000) running firmware 4.9.1. The package adds an AirVPN page under **VPN**, uses the router's native WireGuard/VPN RPCs, and keeps the existing GL.iNet VPN Dashboard and profile model intact.

## What it does

- Adds an **AirVPN** entry to the native VPN sidebar.
- Reads the AirVPN server catalog and supports local sorting/filtering.
- Generates WireGuard profiles with an AirVPN API key and device.
- Adds generated profiles to GL.iNet's native VPN Client Profile store.
- Can connect a selected AirVPN server through the native VPN Dashboard.
- Keeps the API key in OpenWrt UCI configuration and uses the Admin Panel session cookie for privileged browser requests.

## Supported target

This code is currently written and tested for:

- GL.iNet Flint 2 / GL-MT6000
- GL.iNet firmware 4.9.1

`airvpn-ui-patch` deliberately refuses to modify an unrecognized firmware layout.

## Build

From the repository root:

```sh
./build-ipk.sh
```

The output filename is derived from `pkg/control/control`. You can also pass an explicit destination path as the first argument.

## Install

Copy the IPK to the router and install it with `opkg`:

```sh
opkg install /tmp/airvpn-glinet-native_<version>_all.ipk
```

Then reload the GL.iNet Admin Panel. The package installer patches `/www/gl_home.html` with a small loader for the AirVPN UI and keeps a native backup for removal.

## Configuration

The persistent configuration lives in `/etc/config/airvpn_native`. The AirVPN page exposes the normal settings, including API key, AirVPN device, server selectors, ranking/filter options, and WireGuard defaults.

## Tests

The test suite is intentionally lightweight so it can run without router hardware:

```sh
for test in tests/*.sh; do
    sh "$test"
done
```

These checks cover the browser injection contract, authentication bridge, generator behavior, sorting/config handling, and the native GL.iNet WireGuard/VPN calls. They do not replace testing on the target router.

## Uninstall

Removing the package runs `airvpn-ui-patch remove`, restores the saved native GL.iNet page, and removes the package's background refresh entry.