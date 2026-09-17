# MangoUpsideDownCamera

Experimental RootHide/Theos tweak for iOS 16.x.

## Goal

When the device is physically in PortraitUpsideDown, force tracked AVFoundation video connections to use `AVCaptureVideoOrientationPortraitUpsideDown`. When the device leaves upside-down portrait, restore the orientation most recently requested by the client.

## Build

```sh
make clean package
```

The Makefile already sets:

```make
THEOS_PACKAGE_SCHEME = roothide
```

## Test

After installation, restart the target camera client (or sbreload for a clean first test), open any AVFoundation-based camera client, then rotate the device into upside-down portrait.

Watch logs containing:

```text
[MangoUpsideDownCamera]
```

Useful expected messages include:

```text
Loaded into ...
Tracking connection ...
Device entered PortraitUpsideDown
Intercept orientation ... -> PortraitUpsideDown
Device left PortraitUpsideDown
```

## Important

This version operates at the AVFoundation `AVCaptureConnection` layer. It does not patch Camera.app UI and does not patch `cameracaptured` / FigCapture directly.
