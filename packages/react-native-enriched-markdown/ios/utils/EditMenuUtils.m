#import "EditMenuUtils.h"
#import "PasteboardUtils.h"
#import "StyleConfig.h"
#include <TargetConditionals.h>

#if !TARGET_OS_OSX

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
static UIAction *_Nullable createSelectAllAction(ENRMPlatformTextView *_Nullable textView, NSAttributedString *text,
                                                 NSRange range)
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

  UIAction *copyAction = createCopyAction(selectedText, markdown, styleConfig, selectionMenuConfig.copyLabel);
  UIAction *copyMarkdownAction = selectionMenuConfig.copyAsMarkdown
                                     ? createCopyMarkdownAction(markdown, selectionMenuConfig.copyAsMarkdownLabel)
                                     : nil;
  UIAction *copyImageURLAction =
      selectionMenuConfig.copyImageURL ? createCopyImageURLAction(imageURLs, selectionMenuConfig) : nil;
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
