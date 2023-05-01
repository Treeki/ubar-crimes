# uBar Crimes

A set of patches to make [uBar](https://ubarapp.com/) more robust against the software I use. Developed and tested with uBar version 4.2.1, on macOS Ventura.

This is not endorsed by or approved by the uBar developers. Use at your own risk.

## Build + Install

These crimes are injected into uBar by replacing the Sparkle update framework. Yes, it's hacky, but it works, even on Apple Silicon with SIP enabled.

```
$ clang -dynamiclib -arch x86_64 -arch arm64 -framework Foundation -framework ApplicationServices -fmodules -o Sparkle.dylib crimes.m
$ cp Sparkle.dylib /Applications/uBar.app/Contents/Frameworks/Sparkle.framework/Versions/A/Sparkle
$ codesign -s - -f --deep /Applications/uBar.app
```

## Acknowledgements

I used the [Hammerspoon](https://github.com/Hammerspoon/hammerspoon) source code (specifically, `HSuicore.m`) as a guide for which functions I should use for focusing windows and hiding applications.

# Included Patches

## Window Activation

Focusing a window now uses `SetFrontProcessWithOptions` (which Apple has deprecated) to bring the window's process to the foreground.

This seems to work better with WINE applications than `-[NSRunningApplication activateWithOptions:]` does, annoyingly enough.

## Application Hiding

Hiding applications (e.g. by clicking the taskbar button for the app that's already at the foreground) uses `AXUISetElementAttributeValue` to set the hidden attribute, instead of `-[NSRunningApplication hide]`. This makes it work with WINE and also makes it work with Twitter for Mac.

## Launching WINE Applications

uBar expects to see "WillLaunchApplication" or "DidLaunchApplication" workspace notifications before an app will show up in its list, but these don't appear for WINE processes.

There's a kludge that bypasses this for apps with a bundle ID containing `com.parallels.winapp.`, and I've extended that to also count WINE apps (by checking to see if the executable ends in `wine-preloader`), so they'll register in uBar when first focused.

## Updating WINE Applications

uBar detects when a running application's windows have changed by watching for accessibility events, which WINE doesn't send.

There are kludges in it to forcibly rebuild the window list on certain events for what it calls "AX Deficient" apps - by default, this includes Chrome, Opera, Edge and X11 (XQuartz).

WINE apps have no bundle ID, so I've simply added an extra condition: any app with no bundle ID is automatically treated as "AX Deficient".

## Enabling "Single Window Uses Title"

This is an undocumented preference that's not shown in the UI as far as I can tell, which causes single-window apps to show their window title in uBar instead of the app name. This is a far better experience for WINE.

# Missing Stuff

## Icons for WINE applications

The WINE Mac driver seems to set the dock icon by using `[NSApp setApplicationIconImage:]` (ref `dlls/winemac.drv/cocoa_app.m` in the WINE repo). I don't know if there's any way to get this from a separate process without delving into the dock's internals, and that's a bit too much yak shaving for tonight.
