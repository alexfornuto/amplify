//
//  AmplifyViewController.m
//  amplify
//
//  Created by Ezra Zigmond on 6/29/15.
//  Copyright (c) 2015 Ezra Zigmond. All rights reserved.
//

#import "PreferencesViewController.h"
#import "AmplifyViewController.h"
#import "AmplifyScrollLabel.h"
#import "AmplifyHoverButton.h"
#import "Spotify.h"
#import "AmplifyThemeManager.h"
#import "NSImage+Transform.h"
#include <ShortcutRecorder/ShortcutRecorder.h>
#include <Carbon/Carbon.h>

@interface AmplifyViewController () <NSUserNotificationCenterDelegate>

@property (weak) IBOutlet AmplifyHoverButton *nextButton;
@property (weak) IBOutlet AmplifyHoverButton *prevButton;
@property (weak) IBOutlet AmplifyHoverButton *playButton;

// not a hover button because the visual effect would be confusing
// (shuffle button changes color when clicked to indicate shuffling / not shuffling)≥
@property (weak) IBOutlet NSButton *shuffleButton;

@property (weak) IBOutlet NSButton *volumeUp;
@property (weak) IBOutlet NSButton *volumeDown;
@property (weak) IBOutlet NSImageView *volumeImage;

@property (weak) IBOutlet NSSlider *volumeSlider;
@property (weak) IBOutlet NSImageView *albumArtView;
@property (weak) IBOutlet AmplifyScrollLabel *songScrollLabel;

@property (nonatomic, strong) SpotifyApplication *spotify;

@property (nonatomic, strong) NSString *currentTrackURL;

@property (nonatomic, strong) NSColor *normalColor;
@property (nonatomic, strong) NSColor *hoverColor;

@property (nonatomic, strong) NSImage *albumArt;

@property (nonatomic, strong) NSImage *shuffleImage;
@property (nonatomic, strong) NSImage *shuffleTinted;

@end

@implementation AmplifyViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Do view setup here.
    [[NSUserDefaultsController sharedUserDefaultsController] addObserver:self forKeyPath:@"values.buttonTheme" options:NSKeyValueObservingOptionInitial context:NULL];
    [[NSUserDefaultsController sharedUserDefaultsController] addObserver:self forKeyPath:@"values.popoverTheme" options:NSKeyValueObservingOptionInitial context:NULL];
    
    [self bindButtons];
    
    [self setupImages];
    
    [NSUserNotificationCenter defaultUserNotificationCenter].delegate = self;
    
    self.spotify = [SBApplication applicationWithBundleIdentifier:@"com.spotify.client"];
    
    self.albumArtView.imageScaling = NSImageScaleAxesIndependently;
    
    self.songScrollLabel.speed = 0.02;
    self.songScrollLabel.text = @"No song";

    if ([self.spotify isRunning]) {
        self.songScrollLabel.text = [self getFormattedSongTitle];
        
        // if there was already album art before the view loaded, set it
        if (self.albumArt) {
            self.albumArtView.image = self.albumArt;
        }
        // otherwise, get the album artwork
        else {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^ {
                [self updateArtworkWithCompletion:nil];
            });
        }
        
        // set the play button image (normally this changes whenever the playback changes, but
        // set it manually once when the view loads)
        if (self.spotify.playerState == SpotifyEPlSPlaying) {
            [self.playButton setImage:[NSImage imageNamed:@"pause"] withTint:self.normalColor hoverTint:self.hoverColor];
        } else {
            [self.playButton setImage:[NSImage imageNamed:@"play"] withTint:self.normalColor hoverTint:self.hoverColor];
        }
    }
    
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self
                                                        selector:@selector(playbackChanged:)
                                                            name:@"com.spotify.client.PlaybackStateChanged"
                                                          object:nil
                                              suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
}

- (void)viewWillAppear {
    NSString *popoverTheme = [[[NSUserDefaultsController sharedUserDefaultsController] defaults] valueForKey:@"popoverTheme"];
    
    if ([popoverTheme isEqualToString:@"classic"]) {
        self.view.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    } else if ([popoverTheme isEqualToString:@"vibrant"]) {
        self.view.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantLight];
    } else {
        self.view.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];
    }
}

- (void) viewDidAppear {
    if ([self.spotify isRunning]) {
        self.volumeSlider.intValue = (int) self.spotify.soundVolume;
        
        if ([self.spotify shuffling]) {
            self.shuffleButton.image = self.shuffleTinted;
        } else {
            self.shuffleButton.image = self.shuffleImage;
        }
    } else {
        self.songScrollLabel.text = @"No song";
        self.albumArtView.image = [NSImage imageNamed:@"noArtworkImage"];
    }
    
    [self.view.window becomeKeyWindow];
}

- (void) setupImages {
    NSString *popoverTheme = [[[NSUserDefaultsController sharedUserDefaultsController] defaults] valueForKey:@"popoverTheme"];
    NSString *buttonTheme = [[[NSUserDefaultsController sharedUserDefaultsController] defaults] valueForKey:@"buttonTheme"];
    
    if ([popoverTheme isEqualToString:@"dark"]) {
        self.songScrollLabel.color = [NSColor lightGrayColor];
    } else {
        self.songScrollLabel.color = [NSColor blackColor];
    }
    
    self.normalColor = [AmplifyThemeManager normalColorForTheme:popoverTheme];
    self.hoverColor = [AmplifyThemeManager hoverColorForButtonTheme:buttonTheme];
    
    self.volumeImage.image = [[NSImage imageNamed:@"volume"] imageTintedWithColor:self.normalColor];
    
    self.shuffleImage = [[NSImage imageNamed:@"shuffle"] imageTintedWithColor:self.normalColor];
    self.shuffleTinted = [self.shuffleImage imageTintedWithColor:self.hoverColor];
    self.shuffleButton.alternateImage = self.shuffleTinted;
    
    // don't set the play button here because we're going to set that in playbackChanged anyway
    [self.nextButton setImage:[NSImage imageNamed:@"next"] withTint:self.normalColor hoverTint:self.hoverColor];
    [self.prevButton setImage:[NSImage imageNamed:@"previous"] withTint:self.normalColor hoverTint:self.hoverColor];
    [self.playButton setImage:[NSImage imageNamed:@"play"] withTint:self.normalColor hoverTint:self.hoverColor];
}

- (void)playbackChanged:(NSNotification *)notification {
    if ([self.spotify isRunning]) {
        if (self.spotify.playerState == SpotifyEPlSPlaying) {
            
            if (![self.currentTrackURL isEqualToString:self.spotify.currentTrack.spotifyUrl]) {
                self.currentTrackURL = [self.spotify.currentTrack.spotifyUrl copy];
                self.songScrollLabel.text = [self getFormattedSongTitle];
                
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^ {
                    [self updateArtworkWithCompletion:^(NSImage *album) {
                        [self sendNotification:album];
                    }];
                });
            }
            
            [self.playButton setImage:[NSImage imageNamed:@"pause"] withTint:self.normalColor hoverTint:self.hoverColor];
        } else {
            [self.playButton setImage:[NSImage imageNamed:@"play"] withTint:self.normalColor hoverTint:self.hoverColor];
        }
    } else {
        self.songScrollLabel.text = @"No song";
        self.albumArtView.image = [NSImage imageNamed:@"noArtworkImage"];
    }
}

- (NSString *)getFormattedSongTitle {
    return [NSString stringWithFormat:@"%@ - %@", self.spotify.currentTrack.name, self.spotify.currentTrack.artist];
}

- (IBAction)didChangeSlider:(id)sender {
    if ([self.spotify isRunning]) {
        [self.spotify setSoundVolume:self.volumeSlider.integerValue];
    }
}

- (IBAction)didPressPrev:(id)sender {
    if ([self.spotify isRunning]) {
        [self.spotify previousTrack];
    }
}

- (IBAction)didPressPlay:(id)sender {
    if ([self.spotify isRunning]) {
        [self.spotify playpause];
    }
}

- (IBAction)didPressNext:(id)sender {
    if ([self.spotify isRunning]) {
        [self.spotify nextTrack];
    }
}

- (IBAction)didPressShuffle:(id)sender {
    if ([self.spotify isRunning] && [self.spotify shufflingEnabled]) {
        if (!self.spotify.shuffling) {
            self.spotify.shuffling = YES;
            self.shuffleButton.image = self.shuffleTinted;
        }
        else {
            self.spotify.shuffling = NO;
            self.shuffleButton.image = self.shuffleImage;
        }
    }
}

- (IBAction)didPressVolumeDown:(id)sender {
    self.volumeSlider.integerValue = MAX(0, self.volumeSlider.integerValue - 5);
    [self didChangeSlider:nil];
}

- (IBAction)didPressVolumeUp:(id)sender {
    self.volumeSlider.integerValue = MIN(100, self.volumeSlider.integerValue + 5);
    [self didChangeSlider:nil];
}

#pragma mark - Settings pop up button actions

- (IBAction)didPressPreferences:(id)sender {
    [self.prefsWindow makeKeyAndOrderFront:nil];
    PreferencesViewController *contentView = [[PreferencesViewController alloc] initWithNibName:@"PreferencesViewController" bundle:nil];
    
    contentView.delegate = (id<PreferencesDelegate>)self.delegate;
    
    [self.delegate closePopover:nil];
    
    self.prefsWindow.contentViewController = contentView;
}


- (IBAction)didPressQuit:(id)sender {
    [[NSApplication sharedApplication] terminate:nil];
}

- (IBAction)didPressHide:(id)sender {
    [self.delegate togglePopover:self];
}

#pragma mark - Private methods

- (void)updateArtworkWithCompletion:(void (^)(NSImage *))completion {
    NSImage *album;
    
    NSString *spotifyURL = [self.spotify.currentTrack.spotifyUrl copy];
    
    NSURL *songURL = [NSURL URLWithString:[NSString stringWithFormat:@"https://embed.spotify.com/oembed/?url=%@", spotifyURL]];
    
    NSURLRequest *songRequest = [[NSURLRequest alloc] initWithURL:songURL cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:3.0];
    
    NSData *data = [NSURLConnection sendSynchronousRequest:songRequest returningResponse:nil error:nil];

    if (data) {
        NSURL *artURL = [NSURL URLWithString:[[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:nil] objectForKey:@"thumbnail_url"]];
         
        NSURLRequest *artRequest = [[NSURLRequest alloc] initWithURL:artURL cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:3.0];
         
        data = [NSURLConnection sendSynchronousRequest:artRequest returningResponse:nil error:nil];
        
        if (data) {
            album = [[NSImage alloc] initWithData:data];
        } else {
            album = [NSImage imageNamed:@"noArtworkImage"];
        }
        
    } else {
        album = [NSImage imageNamed:@"noArtworkImage"];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^ {
        if ([spotifyURL isEqualToString:self.spotify.currentTrack.spotifyUrl]) {
            self.albumArt = album;
            self.albumArtView.image = album;
            if (completion) {
                completion(album);
            }
        }
    });
}

- (void) sendNotification:(NSImage *)album {
    // only actually send a notification if
    // 1. notifications are enabled in the settings
    // 2. the popover isn't visible and
    // 3. the user isn't currently in spotify
    if ([[[NSUserDefaultsController sharedUserDefaultsController] defaults] boolForKey:@"notifications"] &&
        !self.isVisible &&
        ![[[NSWorkspace sharedWorkspace] frontmostApplication].bundleIdentifier isEqualToString:@"com.spotify.client"]) {
        NSUserNotification *notification = [[NSUserNotification alloc] init];

        notification.title = self.spotify.currentTrack.name;
        notification.subtitle = self.spotify.currentTrack.album;
        notification.informativeText = self.spotify.currentTrack.artist;
        
        notification.contentImage = album;
        
        [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];
    }
}

- (void) bindButtons {
    NSUserDefaultsController *defaults = [NSUserDefaultsController sharedUserDefaultsController];
    
    [self.playButton bind:@"keyEquivalent"
                 toObject:defaults
              withKeyPath:@"values.play"
                  options:@{NSValueTransformerBindingOption: [SRKeyEquivalentTransformer new]}];
    [self.playButton bind:@"keyEquivalentModifierMask"
                 toObject:defaults
              withKeyPath:@"values.play"
                  options:@{NSValueTransformerBindingOption: [SRKeyEquivalentModifierMaskTransformer new]}];
    
    [self.nextButton bind:@"keyEquivalent"
                 toObject:defaults
              withKeyPath:@"values.next"
                  options:@{NSValueTransformerBindingOption: [SRKeyEquivalentTransformer new]}];
    [self.nextButton bind:@"keyEquivalentModifierMask"
                 toObject:defaults
              withKeyPath:@"values.next"
                  options:@{NSValueTransformerBindingOption: [SRKeyEquivalentModifierMaskTransformer new]}];
    
    [self.prevButton bind:@"keyEquivalent"
                 toObject:defaults
              withKeyPath:@"values.prev"
                  options:@{NSValueTransformerBindingOption: [SRKeyEquivalentTransformer new]}];
    [self.prevButton bind:@"keyEquivalentModifierMask"
                 toObject:defaults
              withKeyPath:@"values.prev"
                  options:@{NSValueTransformerBindingOption: [SRKeyEquivalentModifierMaskTransformer new]}];
    
    [self.shuffleButton bind:@"keyEquivalent"
                 toObject:defaults
              withKeyPath:@"values.shuffle"
                  options:@{NSValueTransformerBindingOption: [SRKeyEquivalentTransformer new]}];
    [self.shuffleButton bind:@"keyEquivalentModifierMask"
                 toObject:defaults
              withKeyPath:@"values.shuffle"
                  options:@{NSValueTransformerBindingOption: [SRKeyEquivalentModifierMaskTransformer new]}];
    
    [self.volumeUp bind:@"keyEquivalent"
                    toObject:defaults
                 withKeyPath:@"values.volumeUp"
                     options:@{NSValueTransformerBindingOption: [SRKeyEquivalentTransformer new]}];
    [self.volumeUp bind:@"keyEquivalentModifierMask"
                    toObject:defaults
                 withKeyPath:@"values.volumeUp"
                     options:@{NSValueTransformerBindingOption: [SRKeyEquivalentModifierMaskTransformer new]}];
    
    [self.volumeDown bind:@"keyEquivalent"
               toObject:defaults
            withKeyPath:@"values.volumeDown"
                options:@{NSValueTransformerBindingOption: [SRKeyEquivalentTransformer new]}];
    [self.volumeDown bind:@"keyEquivalentModifierMask"
               toObject:defaults
            withKeyPath:@"values.volumeDown"
                options:@{NSValueTransformerBindingOption: [SRKeyEquivalentModifierMaskTransformer new]}];
}

# pragma mark - NSObject
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"values.buttonTheme"] || [keyPath isEqualToString:@"values.popoverTheme"]) {
        [self setupImages];
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

# pragma mark - NSUserNotificationCenterDelegate methods

- (BOOL) userNotificationCenter:(NSUserNotificationCenter *)center shouldPresentNotification:(NSUserNotification *)notification{
    return YES;
}

// clicking on notification launches Spotify
- (void) userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)notification {
    [[NSWorkspace sharedWorkspace] launchApplication:@"Spotify"];
}

@end
