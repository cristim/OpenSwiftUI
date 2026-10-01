//
//  NSStringDrawing.h
//  OpenSwiftUI_SPI

#pragma once

#import "OpenSwiftUIBase.h"

#if OPENSWIFTUI_TARGET_OS_DARWIN

// Modified based on iOS 18.5 SDK

//
//  NSStringDrawing.h
//  UIKit
//
//  Copyright (c) 2011-2024, Apple Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class NSAttributedString;
@class NSString;
@class NSStringDrawingContext;

NS_HEADER_AUDIT_BEGIN(nullability, sendability)

// When attributes=nil, the methods declared here uses the default behavior for each attribute described in <UIKitCore/NSAttributedString.h>. When stringDrawingContext=nil, it's equivalent of passing the default instance initialized with [[NSStringDrawingContext alloc] init].

OPENSWIFTUI_EXPORT API_AVAILABLE(macos(10.11), ios(6.0), tvos(9.0), watchos(2.0), visionos(1.0))
@interface NSStringDrawingContext : NSObject

// Minimum scale factor for drawWithRect:options:context: and boundingRectWithSize:options:context: methods. If this property is set, the extended string drawing methods will attempt to draw the attributed string in the given bounds by proportionally scaling the font(s) in the attributed string
@property (NS_NONATOMIC_IOSONLY)CGFloat minimumScaleFactor;

// actual scale factor used by the last drawing call where minimum scale factor was specified
@property (readonly, NS_NONATOMIC_IOSONLY) CGFloat actualScaleFactor;

// bounds of the string drawn by the previous invocation of drawWithRect:options:context:
@property (readonly, NS_NONATOMIC_IOSONLY) CGRect totalBounds;

@end

@interface NSString(NSStringDrawing)
- (CGSize)sizeWithAttributes:(nullable NSDictionary<NSAttributedStringKey, id> *)attrs API_AVAILABLE(macos(10.0), ios(7.0), tvos(9.0), watchos(2.0), visionos(1.0));
- (void)drawAtPoint:(CGPoint)point withAttributes:(nullable NSDictionary<NSAttributedStringKey, id> *)attrs API_AVAILABLE(macos(10.0), ios(7.0), tvos(9.0), watchos(2.0), visionos(1.0));
- (void)drawInRect:(CGRect)rect withAttributes:(nullable NSDictionary<NSAttributedStringKey, id> *)attrs API_AVAILABLE(macos(10.0), ios(7.0), tvos(9.0), watchos(2.0), visionos(1.0));
@end

@interface NSAttributedString(NSStringDrawing)
- (CGSize)size API_AVAILABLE(macos(10.0), ios(6.0), tvos(9.0), watchos(2.0), visionos(1.0));
- (void)drawAtPoint:(CGPoint)point API_AVAILABLE(macos(10.0), ios(6.0), tvos(9.0), watchos(2.0), visionos(1.0));
- (void)drawInRect:(CGRect)rect API_AVAILABLE(macos(10.0), ios(6.0), tvos(9.0), watchos(2.0), visionos(1.0));
@end


// AppKit declares NSStringDrawingOptions itself, as an anonymous enum plus a typedef to
// NSInteger, and declares the same option constants. Redeclaring them here is a
// redefinition of both the constants and the type, and AppKit's copy is the one this
// package compiles against, so it is the one that stands. The Swift name it needs lives
// on cocotron's declaration instead.
API_AVAILABLE(macos(10.0), ios(6.0), tvos(9.0), watchos(2.0), visionos(1.0));


// NOTE: All of the following methods will default to drawing on a baseline, limiting drawing to a single line.
// To correctly draw and size multi-line text, pass NSStringDrawingUsesLineFragmentOrigin in the options parameter.
@interface NSString (NSExtendedStringDrawing)
- (void)drawWithRect:(CGRect)rect options:(NSStringDrawingOptions)options attributes:(nullable NSDictionary<NSAttributedStringKey, id> *)attributes context:(nullable NSStringDrawingContext *)context API_AVAILABLE(macos(10.11), ios(7.0), tvos(9.0), watchos(2.0), visionos(1.0));
- (CGRect)boundingRectWithSize:(CGSize)size options:(NSStringDrawingOptions)options attributes:(nullable NSDictionary<NSAttributedStringKey, id> *)attributes context:(nullable NSStringDrawingContext *)context API_AVAILABLE(macos(10.11), ios(7.0), tvos(9.0), watchos(2.0), visionos(1.0));
@end

@interface NSAttributedString (NSExtendedStringDrawing)
- (void)drawWithRect:(CGRect)rect options:(NSStringDrawingOptions)options context:(nullable NSStringDrawingContext *)context API_AVAILABLE(macos(10.11), ios(6.0), tvos(9.0), watchos(2.0), visionos(1.0));
- (CGRect)boundingRectWithSize:(CGSize)size options:(NSStringDrawingOptions)options context:(nullable NSStringDrawingContext *)context API_AVAILABLE(macos(10.11), ios(6.0), tvos(9.0), watchos(2.0), visionos(1.0));
@end

NS_HEADER_AUDIT_END(nullability, sendability)

#endif
