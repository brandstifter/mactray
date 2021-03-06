/* 
    Copyright (C) 2015 Stephen Oliver <steve@infincia.com>

    This code is distributed under the GNU General Public License, version 2 
    (or at your option any later version).
    
    3rd party libraries may be distributed under an alternate Open Source license.
    
    See the Acknowledgements file included with this code for details.
    
*/

#import "FNInstallerWindowController.h"

#import "FNInstallerDestinationViewController.h"
#import "FNInstallerProgressViewController.h"

#import "FNNodeController.h"

#import "FNHelpers.h"

@interface FNInstallerWindowController ()
@property IBOutlet NSPageController *pageController;

@property IBOutlet NSProgressIndicator *installationProgressIndicator;
@property NSURL *selectedInstallLocation;

@property BOOL installationInProgress;
@property BOOL installationFinished;


@end

@implementation FNInstallerWindowController

- (void)windowDidLoad {
    self.window.delegate = self;
    
    [self.pageController setDelegate:self];
    
    NSArray *pageIdentifiers = @[@"FNInstallerDestinationViewController", @"FNInstallerProgressViewController"];
    
    [self.pageController setArrangedObjects:pageIdentifiers];
    
    self.pageController.selectedIndex = FNInstallerPageDestination;
    
    self.selectedInstallLocation = [NSURL fileURLWithPath:[FNInstallDefaultLocation stringByStandardizingPath]];
    
    [self configureMainWindow];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(showInstallerWindow:) name:FNNodeShowInstallerWindow object:nil];
}

#pragma mark - FNInstallerNotification

-(void)showInstallerWindow:(NSNotification *)notification {
    [self showWindow:nil];
}

#pragma mark - IBActions

-(IBAction)next:(id)sender {
    NSAssert([NSThread currentThread] == [NSThread mainThread], @"NOT MAIN THREAD");
    if (self.installationFinished) {
        NSURL *fproxyLocation = self.nodeController.fproxyLocation;
        if (fproxyLocation) {
            // Open the fproxy page in users default browser
            [[NSWorkspace sharedWorkspace] openURL:fproxyLocation];
            [self.window close];
        }
    }
    [self.pageController navigateForward:sender];
    [self configureMainWindow];
}

-(IBAction)previous:(id)sender {
    NSAssert([NSThread currentThread] == [NSThread mainThread], @"NOT MAIN THREAD");
    [self.pageController navigateBack:sender];
    [self configureMainWindow];
}

-(void)configureMainWindow {
    NSAssert([NSThread currentThread] == [NSThread mainThread], @"NOT MAIN THREAD");
    if (self.pageController.selectedIndex == FNInstallerPageProgress) {
        if (self.installationInProgress) {
            self.nextButton.enabled = NO; 
            self.backButton.enabled = NO;
        }
        else if (self.installationFinished) {
            self.nextButton.enabled = YES;    
            self.backButton.enabled = NO;
            self.installationProgressIndicator.doubleValue = self.installationProgressIndicator.maxValue; 
            return;
        }
    }
    else {
        self.nextButton.enabled = self.pageController.selectedIndex < self.pageController.arrangedObjects.count -1 ? YES : NO;
        self.backButton.enabled = self.pageController.selectedIndex > 0 ? YES : NO;      
    }
    self.installationProgressIndicator.minValue = 0;
    self.installationProgressIndicator.maxValue = self.pageController.arrangedObjects.count;
    self.installationProgressIndicator.doubleValue = self.pageController.selectedIndex;
}

#pragma mark - FNInstallerDelegate

-(void)userDidSelectInstallLocation:(NSURL *)installURL {
    self.selectedInstallLocation = installURL;
    [self configureMainWindow];
}

-(void)installerDidCopyFiles {
    self.installationFinished = NO;
    self.installationInProgress = NO;
    [self configureMainWindow];
    [[NSNotificationCenter defaultCenter] postNotificationName:FNInstallStartNodeNotification object:self.selectedInstallLocation];
}

-(void)installerDidFinish {
    self.installationFinished = YES;
    self.installationInProgress = NO;
    [self configureMainWindow];
}

-(void)installerDidFailWithLog:(NSString *)log {
    self.installationFinished = NO;
    self.installationInProgress = NO;
    [self configureMainWindow];
    [[NSNotificationCenter defaultCenter] postNotificationName:FNInstallFailedNotification object:nil];
    
    NSAlert *installFailedAlert = [[NSAlert alloc] init];
    installFailedAlert.messageText = NSLocalizedString(@"Installation failed", @"String informing the user that the installation failed");
    installFailedAlert.informativeText = NSLocalizedString(@"The installation log can be automatically uploaded to GitHub. Please report this failure to the Freenet developers and provide the GitHub link to them.", @"String asking the user to provide the Gist link to the Freenet developers");
    [installFailedAlert addButtonWithTitle:NSLocalizedString(@"Upload", @"Button title")];
    [installFailedAlert addButtonWithTitle:NSLocalizedString(@"Quit", nil)];
   
     NSInteger button = [installFailedAlert runModal];
    
    if (button == NSAlertFirstButtonReturn) {
        
        // upload the gist, then open it in a browser, then quit
        [FNHelpers createGist:log withTitle:@"Installation Log" success:^(NSURL *url) {
            
            NSPasteboard *pasteBoard = [NSPasteboard generalPasteboard];
            [pasteBoard declareTypes:[NSArray arrayWithObjects:NSStringPboardType, nil] owner:nil]; 
            [pasteBoard setString:url.path forType:NSStringPboardType];
            
            [[NSWorkspace sharedWorkspace] openURL:url];
            
            [NSApp terminate:self];
        
        } failure:^(NSError *error) {
            NSString *desktop = NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES)[0];
            NSString *path = [desktop stringByAppendingPathComponent:@"FreenetTray - Installation Log.txt"];

            NSData *logBuffer = [log dataUsingEncoding:NSUTF8StringEncoding];
            [logBuffer writeToFile:path options:NSDataWritingAtomic error:nil];
            
            NSAlert *uploadFailedAlert = [[NSAlert alloc] init];
            uploadFailedAlert.messageText = NSLocalizedString(@"Upload failed", @"String informing the user that the upload failed");
            uploadFailedAlert.informativeText = NSLocalizedString(@"The installation log could not be uploaded to GitHub, it has been placed on your desktop instead. Please report this failure to the Freenet developers and provide the file to them.", @"String informing the user that the log upload failed");
            NSInteger button = [uploadFailedAlert runModal];
            
        }];
        
        
    }
    else if (button == NSAlertSecondButtonReturn) {
        // display node finder panel
        [NSApp terminate:self];
    }
}

#pragma mark - NSPageControllerDelegate

- (NSString *)pageController:(NSPageController *)pageController identifierForObject:(id)object {
    return object;
}

- (NSViewController *)pageController:(NSPageController *)pageController viewControllerForIdentifier:(NSString *)identifier {
    if ([identifier isEqualToString:@"FNInstallerDestinationViewController"]) {
        FNInstallerDestinationViewController *vc = [[FNInstallerDestinationViewController alloc] initWithNibName:@"FNInstallerDestinationView" bundle:nil];
        vc.stateDelegate = self;
        return vc;
    }
    else if ([identifier isEqualToString:@"FNInstallerProgressViewController"]) {
        FNInstallerProgressViewController *vc = [[FNInstallerProgressViewController alloc] initWithNibName:@"FNInstallerProgressView" bundle:nil];
        vc.stateDelegate = self;
        return vc;
    }
    return nil;
    
}

- (void)pageController:(NSPageController *)pageController
 prepareViewController:(NSViewController *)viewController
            withObject:(id)object { 
    viewController.representedObject = object;
}

- (void)pageController:(NSPageController *)pageController didTransitionToObject:(id)object {
    [self configureMainWindow];
}

- (void)pageControllerDidEndLiveTransition:(NSPageController *)pageController {
    [self.pageController completeTransition];
    if (self.pageController.selectedIndex == FNInstallerPageProgress) {
        FNInstallerProgressViewController *vc = (FNInstallerProgressViewController *)self.pageController.selectedViewController;
        [vc installNodeAtFileURL:self.selectedInstallLocation];
        self.installationInProgress = YES;
        [self configureMainWindow];
    }
}

#pragma mark - NSWindowDelegate

- (BOOL)windowShouldClose:(id)sender {
    if (self.installationInProgress) {
        NSAlert *installInProgressAlert = [[NSAlert alloc] init];
        installInProgressAlert.messageText = NSLocalizedString(@"Installation in progress", @"String informing the user that an installation is in progress");
        installInProgressAlert.informativeText = NSLocalizedString(@"Are you sure you want to cancel?", @"String asking the user if they want to cancel the installation");
        [installInProgressAlert addButtonWithTitle:NSLocalizedString(@"Yes", @"Button title")];
        [installInProgressAlert addButtonWithTitle:NSLocalizedString(@"No", @"Button title")];
        NSInteger button = [installInProgressAlert runModal];
        if (button == NSAlertFirstButtonReturn) {
            [NSApp terminate:self];
        }
        else if (button == NSAlertSecondButtonReturn) {
            // user 
        }
    }
    return self.installationInProgress ? NO : YES; 
}

@end
