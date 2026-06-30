#pragma once
#import "ENRMUIKit.h"

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

/// Resolves the link URL at the tap location.
/// If a link is found, calls onLinkPress and returns YES.
/// Otherwise, if the tap falls inside the current selection and
/// `onTapInsideSelection` is provided, calls it (preserving the selection) and
/// returns YES. If neither, calls ENRMClearSelection and returns NO.
BOOL ENRMHandleTapOnTextView(ENRMPlatformTextView *textView, ENRMTapRecognizer *recognizer,
                             void (^onLinkPress)(NSString *url), void (^_Nullable onTapInsideSelection)(void));

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
