# First phone test on a Windows home PC

This kit is for a **synthetic-data test only**. Do not enter real participant
details or use its temporary keys for field collection. Keep the PC and phone on
the same trusted Wi-Fi network. Do not forward port 8787 to the internet.

## What is in the Drive folder

- `study-collector-1.0.0+2.apk`: the signed, shared Android app. Use this same
  APK on every test phone; it is not tied to a device.
- `nutrition-study-source-first-test.zip`: the server source and test launcher.
- `nutrition-study-admin-web-first-test.zip`: the separate admin webpage.
- `SHA256SUMS.txt`: hashes for checking the three downloads.

The private Android signing key and its password are **not** in this test kit.
They are backed up separately. No participant records are in the kit.

## Start the isolated server

1. Extract the source ZIP to a folder on the Windows PC. Install the Dart SDK
   on that PC and confirm `dart --version` works in PowerShell. Node.js is only
   needed to serve the admin webpage; it is not needed for the record server.
2. In PowerShell, change to the extracted source folder and run:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File tool/start_first_phone_test.ps1
   ```

3. The launcher creates a new isolated synthetic-data directory and prints a
   collector access key, an administrator access key, and the directory path.
   Keep that window open. Write down the keys privately for this test only.
4. Run `ipconfig` and note the PC's IPv4 address on the phone's Wi-Fi network.
   Allow inbound TCP port 8787 through the Windows **Private** network firewall
   for the test. Do not enable it for a Public network or use internet port
   forwarding. The phone URL is `http://<PC IPv4 address>:8787`.

## Test the phone and admin page

1. Unlock the phone, install the APK, then open it. At sign-in, use collector
   number `1`, the phone URL from above, and the collector key printed by the
   server. A fresh sign-in needs the server reachable.
2. Create a *fictional* first visit and submit it. Confirm its sync indicator
   clears and that it appears in the admin webpage.
3. To open the separate admin webpage on the same PC, extract the admin ZIP,
   then run from the source folder:

   ```powershell
   node tool/static_site_server.js --root=<full-path-to-extracted-admin-web> --port=8086
   ```

   Open `http://127.0.0.1:8086` on the PC and enter the administrator key
   printed by the launcher. The admin page is not inside the phone app.
4. Turn off Wi-Fi on the phone, submit another *fictional* visit, and confirm
   it shows as awaiting sync. Turn Wi-Fi back on, sync, and confirm it appears
   in the admin page. Do not uninstall the app while it has pending entries.
5. Stop the server with Ctrl+C. The synthetic records remain in the isolated
   directory printed by the launcher; they are not silently deleted.

This first test checks one phone and first visits. Do not use it to validate
offline repeat-visit lookup across phones: that workflow still needs a separate
end-to-end check before any real-data rollout. Backups and the final operating
procedure also need to be verified before real collection.
