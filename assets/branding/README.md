# Vivayu launcher artwork

The owner supplied `vivayu-original.png` and requested no redesign or colour
changes. `tool/prepare_vivayu_icons.ps1` mechanically crops its black margins,
centres the unchanged artwork on black, and resizes it for launcher resources.
No image-generation model was used to modify this chosen artwork.

`vivayu-icon-1024.png` is a square master. Android legacy resources have 64%
artwork width; adaptive foreground resources fit inside the 66dp safe circle
of a 108dp layer. Original Flutter launcher files remain preserved and unused.

Visible name: **Vivayu** (no version suffix). Distribution build metadata:
1.0.0+7. Package identifiers and server addresses are unchanged. No new APK
has been installed on the owner's phone.

Before distribution, back up the current worktree's release signing keystore
and key.properties in a secure location. The older primary-checkout backup
has different bytes and must not be overwritten or assumed to match this key.
