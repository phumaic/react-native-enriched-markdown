#import "ENRMTextInteractionUtils.h"
#import "LinkTapUtils.h"
#include <TargetConditionals.h>

#if !TARGET_OS_OSX
// Whether the tap landed within the rects of the text view's current selection.
static BOOL tapIsInsideSelection(UITextView *textView, UITapGestureRecognizer *recognizer)
{
  UITextRange *selection = textView.selectedTextRange;
  if (selection == nil || textView.selectedRange.length == 0) {
    return NO;
  }
  CGPoint point = [recognizer locationInView:textView];
  // A small tolerance makes edge taps on the selection feel forgiving.
  for (UITextSelectionRect *selectionRect in [textView selectionRectsForRange:selection]) {
    CGRect rect = selectionRect.rect;
    if (rect.size.width > 0 && rect.size.height > 0 && CGRectContainsPoint(CGRectInset(rect, -4, -4), point)) {
      return YES;
    }
  }
  return NO;
}
#endif

BOOL ENRMHandleTapOnTextView(ENRMPlatformTextView *textView, ENRMTapRecognizer *recognizer,
                             void (^onLinkPress)(NSString *url), void (^onTapInsideSelection)(void))
{
  NSString *url = linkURLAtTapLocation(textView, recognizer);
  if (url) {
    if (onLinkPress)
      onLinkPress(url);
    return YES;
  }

#if !TARGET_OS_OSX
  // Tapping the current selection should keep it and toggle the menu rather than
  // clearing it (the default text-view behaviour).
  if (onTapInsideSelection && tapIsInsideSelection(textView, recognizer)) {
    onTapInsideSelection();
    return YES;
  }
#endif

  ENRMClearSelection(textView);
  return NO;
}
