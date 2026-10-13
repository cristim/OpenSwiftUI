//
//  CATransactionCompletionItem.m
//  COpenSwiftUI

#import "CATransactionCompletionItem.h"

#if __has_include(<QuartzCore/QuartzCore.h>) && OPENSWIFTUI_TARGET_OS_IPHONE

CATransactionCompletionItem *_CATransactionCompletionItem(void) {
    return [CATransactionCompletionItem completionItem];
}

#endif /* __has_include(<QuartzCore/QuartzCore.h>) && OPENSWIFTUI_TARGET_OS_IPHONE */

