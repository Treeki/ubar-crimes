// I'm about to commit Crime's...

@import Foundation;
@import ApplicationServices;
@import AppKit;
#include <objc/runtime.h>

__attribute__((visibility("default"))) @interface SUUpdater : NSObject
+ (SUUpdater *) sharedUpdater;
- (void) checkForUpdates: (id) delegate;
@property BOOL automaticallyChecksForUpdates;
@end

@implementation SUUpdater
+ (SUUpdater *) sharedUpdater {
	return [[SUUpdater alloc] init];
}
- (void) checkForUpdates: (id) delegate {
	// nothing
}
@end

@interface BSApp : NSObject
- (BOOL) isHidden;
- (BOOL) isActive;
- (void) hide;
- (void) unhide;
- (void) hideOthers;
- (AXUIElementRef) axAppElement;
- (void) rebuildWindows;
- (void) wantsAttentionChanged: (BOOL) flag;
- (void) updateBadge: (BOOL) flag;
- (NSString *) bundleIdentifier;
- (NSRunningApplication *) runningApp;
- (void) bringWindowToFrontByWindowNumber: (int) number;
- (ProcessSerialNumber) psn;
@end

@interface BSAppDelegate : NSObject
- (void) appLaunching: (BSApp *) app;
- (void) appLaunched: (BSApp *) app;
- (void) appRemoved: (BSApp *) app;
- (void) appHidden: (BSApp *) app;
- (void) appUnhidden: (BSApp *) app;
- (void) appActivated: (BSApp *) app;
- (void) appDeactivated: (BSApp *) app;
- (void) appWantsAttention: (BSApp *) app;
- (void) appWantsAttentionCancelled: (BSApp *) app;
- (BOOL) accessibilityCheck;
@end

@interface BSWindow : NSObject
- (int) windowNumber;
@end

@interface BSStackView : NSView
- (NSArray *) getFilteredWindows;
- (BSApp *) barApp;
@end

@interface BSPrefs : NSObject
- (BOOL) singleApplicationMode;
- (BOOL) singleWindowUsesTitle;
- (BOOL) clickActiveAppToHide;
@end

@interface BSApps : NSObject
- (BSApp *) getAppWithPID: (pid_t) pid;
- (BSApp *) addAppWithRunningApplication: (NSRunningApplication *) runningApp;
- (void) removeApp: (BSApp *) app;
- (BSAppDelegate *) delegate;
- (BOOL) isAppBundleIdentifierAXDeficient: (NSString *) bundleID;
@end

/*
 * Fix activation of individual windows
 */
static void new_switchToWindowWithApp_andWID_(BSAppDelegate *self, SEL sel, BSApp *app, int wid) {
	NSLog(@"[%@ switchToWindowWithApp:%@ andWID:%d]", self, app, wid);

	if ([app isHidden])
		[app unhide];

	[app bringWindowToFrontByWindowNumber:wid];

	// [PATCH] original code:
	// [[app runningApp] activateWithOptions:NSApplicationActivateIgnoringOtherApps];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	ProcessSerialNumber psn = [app psn];
	SetFrontProcessWithOptions(&psn, kSetFrontProcessFrontWindowOnly);
#pragma clang diagnostic pop
}

/*
 * Fix clicks on the app button not hiding some apps (e.g. Twitter for Mac),
 * or not showing other apps (e.g. IDA in WINE)
 */
static void new_toggleApp_(BSStackView *self, SEL sel, BOOL flag) {
	NSLog(@"[%@ toggleApp:%s]", self, flag ? "YES" : "NO");

	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UNSPECIFIED, 0), ^{
		NSURL *url = NULL;
		NSArray *filteredWindows = [self getFilteredWindows];
		BSApp *app = [self barApp];
		BSPrefs *prefs = nil;
		object_getInstanceVariable(self, "prefs", (void **) &prefs);

		if (![app isHidden]) {
			if ([app isActive]) {
				if (
					[filteredWindows count] > 0 &&
					![prefs singleApplicationMode] &&
					!flag &&
					[prefs clickActiveAppToHide]
					)
				{
					// User clicked to hide the app while it was active
					// [PATCH] original code:
					// [[app runningApp] hide];
					AXUIElementSetAttributeValue(
						[app axAppElement],
						(CFStringRef) NSAccessibilityHiddenAttribute,
						kCFBooleanTrue
					);
				} else {
					// Try and launch the app using the bundle URL
					url = [[app runningApp] bundleURL];
				}
			} else {
				if ([filteredWindows count] == 1 && [prefs singleWindowUsesTitle]) {
					BSWindow *window = [filteredWindows objectAtIndex:0];
					[app bringWindowToFrontByWindowNumber:[window windowNumber]];
				}

				if ([filteredWindows count] > 0) {
					// [PATCH] original code:
					// [[app runningApp] activateWithOptions:NSApplicationActivateAllWindows | NSApplicationActivateIgnoringOtherApps];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
					ProcessSerialNumber psn = [app psn];
					SetFrontProcessWithOptions(&psn, 0);
#pragma clang diagnostic pop

					// uBar gets the bundle URL here too, but i'm not sure that's needed
				} else {
					url = [[app runningApp] bundleURL];
				}
			}
		} else {
			[[app runningApp] unhide];

			// TODO i should force-enable singleWindowUsesTitle
			if ([filteredWindows count] == 1 && [prefs singleWindowUsesTitle]) {
				BSWindow *window = [filteredWindows objectAtIndex:0];
				[app bringWindowToFrontByWindowNumber:[window windowNumber]];
			}

			if ([filteredWindows count] > 0) {
				// [PATCH] original code:
				// [[app runningApp] activateWithOptions:NSApplicationActivateAllWindows | NSApplicationActivateIgnoringOtherApps];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
				ProcessSerialNumber psn = [app psn];
				SetFrontProcessWithOptions(&psn, 0);
#pragma clang diagnostic pop

				// uBar gets the bundle URL here too, but i'm not sure that's needed
			} else {
				url = [[app runningApp] bundleURL];
			}
		}

		if (url) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
			[[NSWorkspace sharedWorkspace] launchApplicationAtURL:[[app runningApp] bundleURL]
				options:NSWorkspaceLaunchAsync
				configuration:[NSDictionary dictionary]
				error:nil];
#pragma clang diagnostic pop
		}

		if ([prefs singleApplicationMode] || flag)
			[app hideOthers];
	});
}

/*
 * Fix detection of new WINE apps
 */
static BOOL shouldForceAppToAppear(NSRunningApplication *runningApp) {
	NSString *bundleID = [runningApp bundleIdentifier];

	// This was in the original uBar code
	if ([bundleID containsString:@"com.parallels.winapp."])
		return YES;

	// [PATCH] Make sure new WINE apps appear in uBar
	if ([[[runningApp executableURL] lastPathComponent] isEqualToString:@"wine-preloader"])
		return YES;

	return NO;
}

static void new_workspaceNotificationReceived_(BSApps *self, SEL sel, NSNotification *note) {
	NSLog(@"[%@ workspaceNotificationReceived:%@]", self, note);

	BSAppDelegate *delegate = [self delegate];
	if ([delegate accessibilityCheck])
		return;

	NSRunningApplication *runningApp = [[note userInfo] objectForKeyedSubscript:NSWorkspaceApplicationKey];
	NSString *name = [note name];

	if ([name isEqualToString:NSWorkspaceWillLaunchApplicationNotification]) {
		if ([runningApp activationPolicy] == NSApplicationActivationPolicyRegular) {
			BSApp *app = [self addAppWithRunningApplication:runningApp];
			if (app)
				[delegate appLaunching:app];
		}
	} else if ([name isEqualToString:NSWorkspaceDidLaunchApplicationNotification]) {
		if ([runningApp activationPolicy] == NSApplicationActivationPolicyRegular) {
			BSApp *app = [self addAppWithRunningApplication:runningApp];
			if (app)
				[delegate appLaunched:app];
		}
	} else if ([name isEqualToString:NSWorkspaceDidTerminateApplicationNotification]) {
		BSApp *app = [self getAppWithPID:[runningApp processIdentifier]];
		if (app) {
			[self removeApp:app];
			[delegate appRemoved:app];
		}
	} else if ([name isEqualToString:NSWorkspaceDidHideApplicationNotification]) {
		BSApp *app = [self getAppWithPID:[runningApp processIdentifier]];
		if (app)
			[delegate appHidden:app];
	} else if ([name isEqualToString:NSWorkspaceDidUnhideApplicationNotification]) {
		BSApp *app = [self getAppWithPID:[runningApp processIdentifier]];
		if (app)
			[delegate appUnhidden:app];
	} else if ([name isEqualToString:NSWorkspaceDidActivateApplicationNotification]) {
		BSApp *app = [self getAppWithPID:[runningApp processIdentifier]];
		if (!app) {
			// [PATCH] extracted the Parallels check into a separate function,
			// so we can add more possible apps to this list
			if (shouldForceAppToAppear(runningApp) && [runningApp activationPolicy] == NSApplicationActivationPolicyRegular) {
				BSApp *app = [self addAppWithRunningApplication:runningApp];
				if (app)
					[delegate appLaunched:app];
			} else {
				NSLog(@"Activated missing app: %@ from %@", [runningApp bundleIdentifier], runningApp);
				NSLog(@"Localised name: %@", [runningApp localizedName]);
				NSLog(@"Icon: %@", [runningApp icon]);
				NSLog(@"Bundle URL: %@", [runningApp bundleURL]);
				NSLog(@"Executable URL: %@", [runningApp executableURL]);
				NSLog(@"Finished Launching: %s", [runningApp isFinishedLaunching] ? "YES" : "NO");
				NSLog(@"Process ID: %d", [runningApp processIdentifier]);
				NSLog(@"Activation Policy: %d", (int) [runningApp activationPolicy]);
			}
		}

		if ([app axAppElement]) {
			dispatch_after(
				dispatch_time(DISPATCH_TIME_NOW, 1000000000),
				dispatch_get_main_queue(),
				^{
					[app updateBadge:NO];
				});

			// this seems to fire for Chrome, Edge, Opera and XQuartz X11
			if ([self isAppBundleIdentifierAXDeficient:[app bundleIdentifier]])
				[app rebuildWindows];
		}

		[app wantsAttentionChanged:NO];
		[delegate appWantsAttentionCancelled:app];
		if (app)
			[delegate appActivated:app];
	} else if ([name isEqualToString:NSWorkspaceDidDeactivateApplicationNotification]) {
		BSApp *app = [self getAppWithPID:[runningApp processIdentifier]];
		if ([app axAppElement]) {
			[app updateBadge:NO];
			if ([self isAppBundleIdentifierAXDeficient:[app bundleIdentifier]])
				[app rebuildWindows];
		}

		if (app)
			[delegate appDeactivated:app];
	}
}

/*
 * Force WINE apps to be treated as "AX deficient"
 */
static BOOL (*orig_isAppBundleIdentifierAXDeficient_)(BSApps *self, SEL sel, NSString *bundleID);

static BOOL new_isAppBundleIdentifierAXDeficient_(BSApps *self, SEL sel, NSString *bundleID) {
	// WINE applications have no bundle ID, so...

	// Let's just assume that any app without one is going to be Weirdly Behaved(tm) enough
	// to be classed as AX deficient
	if (bundleID == nil)
		return YES;

	return orig_isAppBundleIdentifierAXDeficient_(self, sel, bundleID);
}

/*
 * Force "Single Window Uses Title" option on
 */
static BOOL new_singleWindowUsesTitle(BSPrefs *self, SEL sel) {
	return YES;
}


__attribute__((constructor)) static void doCrimes() {
	Method m;

	NSLog(@"Doing crimes hahaha");

	m = class_getInstanceMethod(
		objc_getClass("BSAppDelegate"),
		@selector(switchToWindowWithApp:andWID:)
	);
	method_setImplementation(m, (IMP) new_switchToWindowWithApp_andWID_);

	m = class_getInstanceMethod(
		objc_getClass("BSStackView"),
		@selector(toggleApp:)
	);
	method_setImplementation(m, (IMP) new_toggleApp_);

	m = class_getInstanceMethod(
		objc_getClass("BSApps"),
		@selector(workspaceNotificationReceived:)
	);
	method_setImplementation(m, (IMP) new_workspaceNotificationReceived_);

	m = class_getInstanceMethod(
		objc_getClass("BSApps"),
		@selector(isAppBundleIdentifierAXDeficient:)
	);
	orig_isAppBundleIdentifierAXDeficient_ = (BOOL (*) (BSApps *, SEL, NSString *)) method_getImplementation(m);
	method_setImplementation(m, (IMP) new_isAppBundleIdentifierAXDeficient_);

	m = class_getInstanceMethod(
		objc_getClass("BSPrefs"),
		@selector(singleWindowUsesTitle)
	);
	method_setImplementation(m, (IMP) new_singleWindowUsesTitle);
}
