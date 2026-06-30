#pragma once
#import "ENRMUIKit.h"
#import "StyleConfig.h"

NS_ASSUME_NONNULL_BEGIN

// Inner vertical padding (points) between the blockquote background/border edges
// and the text. Shared so the renderer, trailing-trim, and measurement agree.
#define ENRMBlockquotePaddingVertical 8.0

extern NSString *const BlockquoteDepthAttributeName;
extern NSString *const BlockquoteBackgroundColorAttributeName;

@interface BlockquoteBorder : NSObject

- (instancetype)initWithConfig:(StyleConfig *)config;
- (void)drawBordersForGlyphRange:(NSRange)glyphsToShow
                   layoutManager:(NSLayoutManager *)layoutManager
                   textContainer:(NSTextContainer *)textContainer
                         atPoint:(CGPoint)origin;

@end

NS_ASSUME_NONNULL_END
