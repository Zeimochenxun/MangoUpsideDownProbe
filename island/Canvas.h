// The screen-canvas half of Mango's 灵动岛模拟: "应用分辨率" and "恢复默认分辨率".
// Mango's applyResolutionWithWidth:height: removes the old
// /var/tmp/com.apple.iokit.IOMobileGraphicsFamily.plist, writes
// {canvas_height, canvas_width} into it, makes
// /private/var/mobile/Library/Preferences/com.apple.iokit.IOMobileGraphicsFamily.plist
// a symbolic link to it and restarts user space half a second later;
// restoreDefaultResolution deletes both (all read from its Beta9 and Beta12
// binaries). This does the same from SpringBoard, with three additions: a copy
// of anything it replaces is kept and put back, only what is ours is deleted
// again, and the crash guard (Disguise.h) takes the canvas back if the first
// SpringBoard after applying it dies young. The ten sizes are Mango's presets
// (IslandPolicy.h); the pane sends only an index.
//
// Result dictionaries go straight into result.plist, like Disguise.h's: ok,
// message, respring, and for apply preset/width/height.
#pragma once
#import <Foundation/Foundation.h>

// The panel's own pixel size. While a canvas is active UIScreen.nativeBounds may
// report the canvas instead, so the size seen while no canvas was active is kept
// (panel.plist) and used for every decision about the model value. Call
// DICanvasNotePanel once UIKit is up, with the live nativeBounds size; it stores
// the size only when no canvas is active. DICanvasPanelWidth/Height give the size
// to use: the stored one while a canvas is active, the live one otherwise.
void DICanvasNotePanel(double width, double height);
double DICanvasPanelWidth(double live);
double DICanvasPanelHeight(double live);

// What is on disk right now, for the pane: canvasActive (a link to the canvas
// file exists, ours or Mango's), canvasByUs, canvasWidth/canvasHeight/
// canvasPreset (-1 when the size is not a preset) when the file can be read,
// canvasForeign (the Preferences path holds somebody else's file or link), and
// panelWidth/panelHeight (as above) with the live size next to them.
NSDictionary *DICanvasStatus(double liveWidth, double liveHeight);

// Preset index into IMPresetAt; the live size is noted as the panel's first (when
// no canvas is active yet). Refuses below iOS 16.1 (Mango's gate).
NSDictionary *DICanvasApply(NSInteger preset, double liveWidth, double liveHeight);

// Always allowed. Also what the crash guard and DynamicIsland.restore call at
// SpringBoard launch, so it uses file operations only.
NSDictionary *DICanvasRestore(void);
