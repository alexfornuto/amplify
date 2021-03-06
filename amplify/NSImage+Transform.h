//
//  NSImage+Transform.h
//  amplify
//
//  Created by Ezra Zigmond on 7/12/15.
//  Copyright (c) 2015 Ezra Zigmond. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface NSImage (Transform)

// returns the image tinted with the given color
- (NSImage *)imageTintedWithColor:(NSColor *)tint;

@end
