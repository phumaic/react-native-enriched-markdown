#import "EditMenuUtils.h"
#import "PasteboardUtils.h"
#import "StyleConfig.h"
#include <TargetConditionals.h>

#if !TARGET_OS_OSX
// Re-presents the text view's edit menu after a programmatic selection change.
// UIKit dismisses the current menu once a menu action runs, so the presentation
// is deferred to the next runloop turn and anchored to the new selection rect.
// TODO: Remove API_AVAILABLE(ios(16.0)) guard when the minimum iOS deployment target in RN is bumped to 16.
static void representEditMenuForSelection(UITextView *textView) API_AVAILABLE(ios(16.0))
{
  UIEditMenuInteraction *editMenuInteraction = nil;
  for (id<UIInteraction> interaction in textView.interactions) {
    if ([interaction isKindOfClass:[UIEditMenuInteraction class]]) {
      editMenuInteraction = (UIEditMenuInteraction *)interaction;
      break;
    }
  }
  if (editMenuInteraction == nil) {
    return;
  }

  UITextRange *selectedRange = textView.selectedTextRange;
  if (selectedRange == nil) {
    return;
  }

  // Anchor the menu to the start of the selection, matching how the system
  // presents it when text is selected by hand.
  CGRect selectionRect = [textView firstRectForRange:selectedRange];
  CGPoint sourcePoint = CGPointMake(CGRectGetMidX(selectionRect), CGRectGetMinY(selectionRect));

  dispatch_async(dispatch_get_main_queue(), ^{
    UIEditMenuConfiguration *configuration = [UIEditMenuConfiguration configurationWithIdentifier:nil
                                                                                      sourcePoint:sourcePoint];
    [editMenuInteraction presentEditMenuWithConfiguration:configuration];
  });
}

static NSString *const kMenuIdentifierStandardEdit = @"com.apple.menu.standard-edit";
static NSString *const kActionIdentifierCopy = @"com.swmansion.enriched.markdown.copy";
static NSString *const kActionIdentifierCopyMarkdown = @"com.swmansion.enriched.markdown.copyMarkdown";
static NSString *const kActionIdentifierCopyImageURL = @"com.swmansion.enriched.markdown.copyImageURL";
static NSString *const kActionIdentifierSelectAll = @"com.swmansion.enriched.markdown.selectAll";

static UIAction *createCopyAction(NSAttributedString *selectedText, NSString *markdown, StyleConfig *styleConfig)
{
  return [UIAction actionWithTitle:@"Copy"
                             image:[RCTUIImage systemImageNamed:@"doc.on.doc"]
                        identifier:kActionIdentifierCopy
                           handler:^(__kindof UIAction *action) {
                             copyAttributedStringToPasteboard(selectedText, markdown, styleConfig);
                           }];
}

static UIAction *_Nullable createCopyMarkdownAction(NSString *markdown)
{
  if (markdown.length == 0)
    return nil;

  return [UIAction actionWithTitle:@"Copy as Markdown"
                             image:[RCTUIImage systemImageNamed:@"doc.text"]
                        identifier:kActionIdentifierCopyMarkdown
                           handler:^(__kindof UIAction *action) { copyStringToPasteboard(markdown); }];
}

static UIAction *_Nullable createCopyImageURLAction(NSArray<NSString *> *imageURLs)
{
  if (imageURLs.count == 0)
    return nil;

  NSString *urlsToCopy = [imageURLs componentsJoinedByString:@"\n"];
  NSString *title = (imageURLs.count == 1)
                        ? @"Copy Image URL"
                        : [NSString stringWithFormat:@"Copy %lu Image URLs", (unsigned long)imageURLs.count];

  return [UIAction actionWithTitle:title
                             image:[RCTUIImage systemImageNamed:@"link"]
                        identifier:kActionIdentifierCopyImageURL
                           handler:^(__kindof UIAction *action) { copyStringToPasteboard(urlsToCopy); }];
}

// Selects the entire content of the text view. iOS strips the system "Select All"
// action when we rebuild the standard-edit submenu, so we recreate it here. The
// text view is held weakly to avoid retaining it through the menu's lifetime.
// TODO: Remove API_AVAILABLE(ios(16.0)) guard when the minimum iOS deployment target in RN is bumped to 16.
static UIAction *_Nullable createSelectAllAction(ENRMPlatformTextView *_Nullable textView, NSAttributedString *text,
                                                 NSRange range) API_AVAILABLE(ios(16.0))
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
                             // Re-present the menu so the user can immediately act on the
                             // now fully-selected text (Copy, Copy as Markdown, etc.).
                             representEditMenuForSelection(strongTextView);
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
  NSAttributedString *selectedText = [attributedText attributedSubstringFromRange:range];
  NSString *markdown = markdownForRange(attributedText, range, cachedMarkdown);
  NSArray<NSString *> *imageURLs = imageURLsInRange(attributedText, range);

  UIAction *copyAction = createCopyAction(selectedText, markdown, styleConfig);
  UIAction *copyMarkdownAction = selectionMenuConfig.copyAsMarkdown ? createCopyMarkdownAction(markdown) : nil;
  UIAction *copyImageURLAction = selectionMenuConfig.copyImageURL ? createCopyImageURLAction(imageURLs) : nil;
  UIAction *selectAllAction = createSelectAllAction(textView, attributedText, range);

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
