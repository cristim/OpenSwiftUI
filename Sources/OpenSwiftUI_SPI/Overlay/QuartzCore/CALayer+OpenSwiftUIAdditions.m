//
//  CALayer+OpenSwiftUIAdditions.m
//  OpenSwiftUI_SPI
//
//  Audited for 6.5.4
//  Status: Complete

#import "CALayer+OpenSwiftUIAdditions.h"
#import "CANullAction.h"
#import <objc/runtime.h>

#if __has_include(<QuartzCore/QuartzCore.h>)

// MARK: - _OpenSwiftUI_NoAnimationDelegate

/// A class whose sole purpose is to act as a CALayer delegate that
/// suppresses all implicit animations by returning kCFNull.
/// Used as a class object (not an instance) — the class method
/// +actionForLayer:forKey: is dispatched via the metaclass.
@interface _OpenSwiftUI_NoAnimationDelegate : NSObject
@end

@implementation _OpenSwiftUI_NoAnimationDelegate

+ (id<CAAction>)actionForLayer:(CALayer *)layer forKey:(NSString *)event {
    return _CANullAction();
}

@end

// MARK: - CALayer (OpenSwiftUIAdditions)

@implementation CALayer (OpenSwiftUIAdditions)

static char viewTestPropertiesKey;
static char displayListIDKey;

- (uint64_t)openSwiftUI_viewTestProperties {
    NSNumber *properties = objc_getAssociatedObject(self, &viewTestPropertiesKey);
    return properties.unsignedLongLongValue;
}

- (void)setOpenSwiftUI_viewTestProperties:(uint64_t)properties {
    objc_setAssociatedObject(self, &viewTestPropertiesKey,
                             [NSNumber numberWithUnsignedLongLong:properties],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (int64_t)openSwiftUI_displayListID {
    NSNumber *value = objc_getAssociatedObject(self, &displayListIDKey);
    if (value == nil) {
        return INT64_MAX;
    }
    return value.longLongValue;
}

- (void)setOpenSwiftUI_displayListID:(int64_t)displayListID {
    objc_setAssociatedObject(self, &displayListIDKey,
                             [NSNumber numberWithLongLong:displayListID],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)openSwiftUI_setNoAnimationDelegate {
    self.delegate = (id)[_OpenSwiftUI_NoAnimationDelegate class];
}

@end

#endif /* __has_include(<QuartzCore/QuartzCore.h>) */
