#import "EditMenuUtils.h"
#import "PasteboardUtils.h"
#import "StyleConfig.h"
#include <TargetConditionals.h>

#if !TARGET_OS_OSX
#import <objc/runtime.h>

static const void *const kEditMenuInteractionKey = &kEditMenuInteractionKey;
static const void *const kEditMenuRepresenterKey = &kEditMenuRepresenterKey;
static const void *const kEditMenuVisibleKey = &kEditMenuVisibleKey;

// Tracks whether an edit menu (system long-press or our own) is on screen for a
// text view, so a tap on the selection can toggle it. Stored on the text view so
// the menu builder can flag it without depending on which interaction presented.
static void setEditMenuVisible(UITextView *textView, BOOL visible)
{
  objc_setAssociatedObject(textView, kEditMenuVisibleKey, @(visible), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Delegate for an edit-menu interaction we own. UITextView does not expose its
// internal edit-menu interaction, so to (re-)present the menu after a programmatic
// selection change we attach our own interaction and drive it through this
// delegate, reusing the same menu builder as the long-press path.
API_AVAILABLE(ios(16.0))
@interface ENRMEditMenuRepresenter : NSObject <UIEditMenuInteractionDelegate>
@property (nonatomic, copy, nullable) ENRMMenuProvider menuProvider;
@end

@implementation ENRMEditMenuRepresenter
- (UIMenu *)editMenuInteraction:(UIEditMenuInteraction *)interaction
           menuForConfiguration:(UIEditMenuConfiguration *)configuration
               suggestedActions:(NSArray<UIMenuElement *> *)suggestedActions API_AVAILABLE(ios(16.0))
{
  return self.menuProvider ? self.menuProvider(suggestedActions) : nil;
}

- (void)editMenuInteraction:(UIEditMenuInteraction *)interaction
    willPresentMenuForConfiguration:(UIEditMenuConfiguration *)configuration
                           animator:(id<UIEditMenuInteractionAnimating>)animator API_AVAILABLE(ios(16.0))
{
  if ([interaction.view isKindOfClass:[UITextView class]]) {
    setEditMenuVisible((UITextView *)interaction.view, YES);
  }
}

- (void)editMenuInteraction:(UIEditMenuInteraction *)interaction
    willDismissMenuForConfiguration:(UIEditMenuConfiguration *)configuration
                           animator:(id<UIEditMenuInteractionAnimating>)animator API_AVAILABLE(ios(16.0))
{
  // Defer clearing so a tap that dismisses the menu still reads "visible" in the
  // tap handler this runloop turn, letting the tap toggle the menu off rather than
  // immediately re-presenting it.
  UITextView *textView = [interaction.view isKindOfClass:[UITextView class]] ? (UITextView *)interaction.view : nil;
  dispatch_async(dispatch_get_main_queue(), ^{
    if (textView) {
      setEditMenuVisible(textView, NO);
    }
  });
}
@end

// Lazily attaches our edit-menu interaction (and its retained delegate) to the
// text view, returning the interaction. The interaction holds its delegate weakly,
// so the representer is retained on the text view alongside the interaction.
static UIEditMenuInteraction *editMenuInteractionFor(UITextView *textView, ENRMMenuProvider menuProvider)
    API_AVAILABLE(ios(16.0))
{
  ENRMEditMenuRepresenter *representer = objc_getAssociatedObject(textView, kEditMenuRepresenterKey);
  UIEditMenuInteraction *interaction = objc_getAssociatedObject(textView, kEditMenuInteractionKey);
  if (representer == nil || interaction == nil) {
    representer = [[ENRMEditMenuRepresenter alloc] init];
    interaction = [[UIEditMenuInteraction alloc] initWithDelegate:representer];
    [textView addInteraction:interaction];
    objc_setAssociatedObject(textView, kEditMenuRepresenterKey, representer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(textView, kEditMenuInteractionKey, interaction, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  }
  representer.menuProvider = menuProvider;
  return interaction;
}

void ENRMPresentEditMenuForSelection(UITextView *textView, ENRMMenuProvider menuProvider) API_AVAILABLE(ios(16.0))
{
  if (textView == nil || menuProvider == nil) {
    return;
  }

  UITextRange *selectedRange = textView.selectedTextRange;
  if (selectedRange == nil) {
    return;
  }

  UIEditMenuInteraction *interaction = editMenuInteractionFor(textView, menuProvider);

  // Anchor the menu to the start of the selection, matching how the system
  // presents it when text is selected by hand.
  CGRect selectionRect = [textView firstRectForRange:selectedRange];
  CGPoint sourcePoint = CGPointMake(CGRectGetMidX(selectionRect), CGRectGetMinY(selectionRect));

  dispatch_async(dispatch_get_main_queue(), ^{
    UIEditMenuConfiguration *configuration = [UIEditMenuConfiguration configurationWithIdentifier:nil
                                                                                      sourcePoint:sourcePoint];
    [interaction presentEditMenuWithConfiguration:configuration];
  });
}

BOOL ENRMEditMenuVisible(UITextView *textView) API_AVAILABLE(ios(16.0))
{
  return [objc_getAssociatedObject(textView, kEditMenuVisibleKey) boolValue];
}

void ENRMDismissEditMenu(UITextView *textView) API_AVAILABLE(ios(16.0))
{
  setEditMenuVisible(textView, NO);
  UIEditMenuInteraction *interaction = objc_getAssociatedObject(textView, kEditMenuInteractionKey);
  [interaction dismissMenu];
}

static NSString *const kMenuIdentifierStandardEdit = @"com.apple.menu.standard-edit";
static NSString *const kActionIdentifierCopy = @"com.swmansion.enriched.markdown.copy";
static NSString *const kActionIdentifierCopyMarkdown = @"com.swmansion.enriched.markdown.copyMarkdown";
static NSString *const kActionIdentifierCopyImageURL = @"com.swmansion.enriched.markdown.copyImageURL";
static NSString *const kActionIdentifierSelectAll = @"com.swmansion.enriched.markdown.selectAll";

static UIAction *createCopyAction(NSAttributedString *selectedText, NSString *markdown, StyleConfig *styleConfig,
                                  NSString *copyLabel)
{
  return [UIAction actionWithTitle:copyLabel
                             image:[RCTUIImage systemImageNamed:@"doc.on.doc"]
                        identifier:kActionIdentifierCopy
                           handler:^(__kindof UIAction *action) {
                             copyAttributedStringToPasteboard(selectedText, markdown, styleConfig);
                           }];
}

static UIAction *_Nullable createCopyMarkdownAction(NSString *markdown, NSString *copyAsMarkdownLabel)
{
  if (markdown.length == 0)
    return nil;

  return [UIAction actionWithTitle:copyAsMarkdownLabel
                             image:[RCTUIImage systemImageNamed:@"doc.text"]
                        identifier:kActionIdentifierCopyMarkdown
                           handler:^(__kindof UIAction *action) { copyStringToPasteboard(markdown); }];
}

static UIAction *_Nullable createCopyImageURLAction(NSArray<NSString *> *imageURLs,
                                                    ENRMSelectionMenuConfig selectionMenuConfig)
{
  if (imageURLs.count == 0)
    return nil;

  NSString *urlsToCopy = [imageURLs componentsJoinedByString:@"\n"];
  NSString *title = ENRMResolveImageURLsTitle(selectionMenuConfig, imageURLs.count);

  return [UIAction actionWithTitle:title
                             image:[RCTUIImage systemImageNamed:@"link"]
                        identifier:kActionIdentifierCopyImageURL
                           handler:^(__kindof UIAction *action) { copyStringToPasteboard(urlsToCopy); }];
}

// Selects the entire content of the text view. iOS strips the system "Select All"
// action when we rebuild the standard-edit submenu, so we recreate it here. The
// text view is held weakly to avoid retaining it through the menu's lifetime.
// `menuProvider` rebuilds the menu for the full selection so it can be re-presented.
// TODO: Remove API_AVAILABLE(ios(16.0)) guard when the minimum iOS deployment target in RN is bumped to 16.
static UIAction *_Nullable createSelectAllAction(ENRMPlatformTextView *_Nullable textView, NSAttributedString *text,
                                                 NSRange range, ENRMMenuProvider menuProvider) API_AVAILABLE(ios(16.0))
{
  // Nothing to add when there is no text view or the whole text is already selected.
  if (textView == nil || range.length >= text.length) {
    return nil;
  }

  __weak ENRMPlatformTextView *weakTextView = textView;
  return [UIAction actionWithTitle:@"Select All"
                             image:nil
                        identifier:kActionIdentifierSelectAll
                           handler:^(__kindof UIAction *action) {
                             ENRMPlatformTextView *strongTextView = weakTextView;
                             if (strongTextView == nil) {
                               return;
                             }
                             // Set the full document range directly: `selectAll:` is a no-op on
                             // non-editable text views, but assigning `selectedTextRange` works
                             // regardless of editability.
                             UITextRange *fullRange =
                                 [strongTextView textRangeFromPosition:strongTextView.beginningOfDocument
                                                            toPosition:strongTextView.endOfDocument];
                             strongTextView.selectedTextRange = fullRange;
                             // Ensure the text view is first responder so the menu can present,
                             // then re-present it so the user can immediately act on the now
                             // fully-selected text (Copy, Copy as Markdown, etc.).
                             [strongTextView becomeFirstResponder];
                             ENRMPresentEditMenuForSelection(strongTextView, menuProvider);
                           }];
}

static UIMenu *createEnhancedStandardEditMenu(UIMenu *originalMenu, UIAction *copyAction,
                                              UIAction *_Nullable selectAllAction)
{
  NSMutableArray<UIMenuElement *> *children = [NSMutableArray arrayWithObject:copyAction];
  if (selectAllAction) {
    [children addObject:selectAllAction];
  }
  return [UIMenu menuWithTitle:originalMenu.title
                         image:originalMenu.image
                    identifier:originalMenu.identifier
                       options:originalMenu.options
                      children:children];
}

static void addOptionalAction(NSMutableArray<UIMenuElement *> *array, UIAction *_Nullable action)
{
  if (action) {
    [array addObject:action];
  }
}

static void insertOptionalAction(NSMutableArray<UIMenuElement *> *array, UIAction *_Nullable action, NSUInteger index)
{
  if (action) {
    [array insertObject:action atIndex:index];
  }
}

// TODO: Remove API_AVAILABLE(ios(16.0)) guard when the minimum iOS deployment target in RN is bumped to 16.
UIMenu *buildEditMenuForSelection(ENRMPlatformTextView *_Nullable textView, NSAttributedString *attributedText,
                                  NSRange range, NSString *_Nullable cachedMarkdown, StyleConfig *styleConfig,
                                  NSArray<UIMenuElement *> *suggestedActions,
                                  NSArray<UIAction *> *_Nullable customActions,
                                  ENRMSelectionMenuConfig selectionMenuConfig) API_AVAILABLE(ios(16.0))
{
  // Building the menu means it is about to be presented (system long-press or our
  // own re-presentation), so flag it visible for tap-to-toggle.
  if (textView != nil) {
    setEditMenuVisible(textView, YES);
  }

  NSAttributedString *selectedText = [attributedText attributedSubstringFromRange:range];
  NSString *markdown = markdownForRange(attributedText, range, cachedMarkdown);
  NSArray<NSString *> *imageURLs = imageURLsInRange(attributedText, range);

  UIAction *copyAction = createCopyAction(selectedText, markdown, styleConfig, selectionMenuConfig.copyLabel);
  UIAction *copyMarkdownAction = selectionMenuConfig.copyAsMarkdown
                                     ? createCopyMarkdownAction(markdown, selectionMenuConfig.copyAsMarkdownLabel)
                                     : nil;
  UIAction *copyImageURLAction =
      selectionMenuConfig.copyImageURL ? createCopyImageURLAction(imageURLs, selectionMenuConfig) : nil;

  // Provider used to rebuild this menu for the full selection when "Select All"
  // re-presents it. Re-entrant: for the full range createSelectAllAction returns
  // nil, so no further Select All (or recursion) is produced.
  __weak ENRMPlatformTextView *weakTextView = textView;
  ENRMMenuProvider menuProvider = ^UIMenu *_Nullable(NSArray<UIMenuElement *> *suggested)
  {
    ENRMPlatformTextView *strongTextView = weakTextView;
    if (strongTextView == nil) {
      return nil;
    }
    NSAttributedString *fullText = strongTextView.attributedText;
    return buildEditMenuForSelection(strongTextView, fullText, NSMakeRange(0, fullText.length), cachedMarkdown,
                                     styleConfig, suggested, customActions, selectionMenuConfig);
  };
  UIAction *selectAllAction = createSelectAllAction(textView, attributedText, range, menuProvider);

  NSMutableArray<UIMenuElement *> *result = [NSMutableArray array];
  BOOL foundStandardEditMenu = NO;

  for (UIMenuElement *element in suggestedActions) {
    if ([element isKindOfClass:[UIMenu class]]) {
      UIMenu *menu = (UIMenu *)element;

      if ([menu.identifier isEqualToString:kMenuIdentifierStandardEdit]) {
        // Replace standard Copy with our enhanced version, re-adding Select All
        // which iOS drops when the submenu is rebuilt.
        [result addObject:createEnhancedStandardEditMenu(menu, copyAction, selectAllAction)];
        addOptionalAction(result, copyMarkdownAction);
        addOptionalAction(result, copyImageURLAction);
        foundStandardEditMenu = YES;
        continue;
      }
    }
    [result addObject:element];
  }

  if (!foundStandardEditMenu) {
    [result insertObject:copyAction atIndex:0];
    NSUInteger nextIndex = 1;
    if (selectAllAction) {
      [result insertObject:selectAllAction atIndex:nextIndex++];
    }
    insertOptionalAction(result, copyMarkdownAction, nextIndex);
    addOptionalAction(result, copyImageURLAction);
  }

  if (customActions.count > 0) {
    return [UIMenu menuWithChildren:[customActions arrayByAddingObjectsFromArray:result]];
  }

  return [UIMenu menuWithChildren:result];
}

#endif
