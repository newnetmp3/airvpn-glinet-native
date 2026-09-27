# Changelog

## 0.11.12

- Fixed the Server Browser repeatedly rebuilding its table while VPN status was polled.
- VPN status polling now updates only the selected-server row highlight, preserving table scroll position.
- Includes the 0.11.11 Info dialog Close-button fix.

## 0.11.11

- Fixed the Close button in the server Info dialog.
- Bound the dialog close action directly to the modal instead of relying on the AirVPN page click delegate.
- Added a regression check for the Info dialog close path.

## 0.11.10

- Simplified the Server Browser Actions column to **Info** and **Select**.
- Removed Favorite, Exclude, IP, and Country row buttons.
- Made the server Info dialog informational only.
- Reduced the Actions column width to match the smaller control set.
- Cleaned source comments and removed internal audit/rebase artifacts from the distribution.
- Kept the 0.11.9 Admin Panel geometry fix that anchors the AirVPN page to the native header and primary sidebar.

## 0.11.9

- Fixed AirVPN page placement on centered GL.iNet Admin Panel layouts.
- Anchored the page to the native Admin Panel header and primary sidebar.
- Added page-geometry diagnostics under `window.__airvpn491.debug`.