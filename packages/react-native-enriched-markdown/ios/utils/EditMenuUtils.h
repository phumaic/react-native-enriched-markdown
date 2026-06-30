#pragma once
#import "ENRMUIKit.h"
#import <Foundation/Foundation.h>

@class StyleConfig;

NS_ASSUME_NONNULL_BEGIN

typedef struct {
  BOOL copyAsMarkdown;
  BOOL copyImageURL;
} ENRMSelectionMenuConfig;

#ifdef __cplusplus
extern "C" {
#endif

#if !TARGET_OS_OSX
// Rebuilds the edit menu for a given selection. `suggestedActions` are the system
// actions offered by the presenting interaction.
typedef UIMenu *_Nullable (^ENRMMenuProvider)(NSArray<UIMenuElement *> *suggestedActions);

// TODO: Remove API_AVAILABLE(ios(16.0)) guard when the minimum iOS deployment target in RN is bumped to 16.
UIMenu *buildEditMenuForSelection(ENRMPlatformTextView *_Nullable textView, NSAttributedString *attributedText,
                                  NSRange range, NSString *_Nullable cachedMarkdown, StyleConfig *styleConfig,
                                  NSArray<UIMenuElement *> *suggestedActions,
                                  NSArray<UIAction *> *_Nullable customActions,
                                  ENRMSelectionMenuConfig selectionMenuConfig) API_AVAILABLE(ios(16.0));

// Presents the edit menu for the text view's current selection, building it via
// `menuProvider`. Used to (re-)show the menu after a programmatic selection change.
void ENRMPresentEditMenuForSelection(ENRMPlatformTextView *textView, ENRMMenuProvider menuProvider)
    API_AVAILABLE(ios(16.0));

// Whether our managed edit menu is currently presented for this text view.
BOOL ENRMEditMenuVisible(ENRMPlatformTextView *textView) API_AVAILABLE(ios(16.0));

// Dismisses our managed edit menu for this text view, if presented.
void ENRMDismissEditMenu(ENRMPlatformTextView *textView) API_AVAILABLE(ios(16.0));
#else
NSMenu *_Nullable buildEditMenuForSelection(NSTextView *_Nullable textView, NSAttributedString *attributedText,
                                            NSRange range, NSString *_Nullable cachedMarkdown, StyleConfig *styleConfig,
                                            NSArray *suggestedActions, NSArray<NSMenuItem *> *_Nullable customItems,
                                            ENRMSelectionMenuConfig selectionMenuConfig);
#endif

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
