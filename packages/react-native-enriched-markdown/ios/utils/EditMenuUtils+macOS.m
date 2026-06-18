#import "ContextMenuUtils.h"
#import "ENRMMenuAction.h"
#import "EditMenuUtils.h"
#import "PasteboardUtils.h"
#import "StyleConfig.h"
#include <TargetConditionals.h>

#if TARGET_OS_OSX

NSMenu *_Nullable buildEditMenuForSelection(NSTextView *_Nullable textView, NSAttributedString *attributedText,
                                            NSRange range, NSString *_Nullable cachedMarkdown, StyleConfig *styleConfig,
                                            NSArray *suggestedActions, NSArray<NSMenuItem *> *_Nullable customItems,
                                            ENRMSelectionMenuConfig selectionMenuConfig)
{
  // `textView` is unused on macOS: NSTextView's system context menu already
  // includes "Select All", which we preserve by editing the base menu in place.
  (void)textView;
  NSMenu *menu = ([suggestedActions.firstObject isKindOfClass:[NSMenu class]]) ? (NSMenu *)suggestedActions.firstObject
                                                                               : [[NSMenu alloc] initWithTitle:@""];

  if (range.length == 0) {
    return menu;
  }

  NSAttributedString *selectedText = [attributedText attributedSubstringFromRange:range];
  NSString *markdown = markdownForRange(attributedText, range, cachedMarkdown);
  NSArray<NSString *> *imageURLs = imageURLsInRange(attributedText, range);

  // Replace the system Copy item with our enhanced version (copies RTF/HTML/Markdown).
  // This mirrors the iOS behaviour where we replace the standard-edit Copy action.
  NSMenuItem *enhancedCopy =
      ENRMCreateMenuItem(@"Copy", ^{ copyAttributedStringToPasteboard(selectedText, markdown, styleConfig); });
  NSInteger systemCopyIndex = [menu indexOfItemWithTarget:nil andAction:@selector(copy:)];
  if (systemCopyIndex != NSNotFound) {
    [menu removeItemAtIndex:systemCopyIndex];
    [menu insertItem:enhancedCopy atIndex:systemCopyIndex];
  } else {
    if (menu.numberOfItems > 0) {
      [menu addItem:[NSMenuItem separatorItem]];
    }
    [menu addItem:enhancedCopy];
  }

  if (selectionMenuConfig.copyAsMarkdown && markdown.length > 0) {
    [menu addItem:ENRMCreateMenuItem(@"Copy as Markdown", ^{ copyStringToPasteboard(markdown); })];
  }

  if (selectionMenuConfig.copyImageURL && imageURLs.count > 0) {
    NSString *title = (imageURLs.count == 1)
                          ? @"Copy Image URL"
                          : [NSString stringWithFormat:@"Copy %lu Image URLs", (unsigned long)imageURLs.count];
    [menu addItem:ENRMCreateMenuItem(title, ^{
            NSString *urlsToCopy = [imageURLs componentsJoinedByString:@"\n"];
            copyStringToPasteboard(urlsToCopy);
          })];
  }

  ENRMPrependMenuItems(menu, customItems);

  return menu;
}

#endif