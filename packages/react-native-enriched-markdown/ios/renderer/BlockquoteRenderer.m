#import "BlockquoteRenderer.h"
#import "BlockquoteBorder.h"
#import "FontUtils.h"
#import "MarkdownASTNode.h"
#import "ParagraphStyleUtils.h"
#import "RenderContext.h"
#import "RendererFactory.h"
#import "StyleConfig.h"

static NSString *const kNestedInfoDepthKey = @"depth";
static NSString *const kNestedInfoRangeKey = @"range";

// Inner vertical padding between the blockquote background/border edges and the
// text, so the quote does not look cramped. Applied to the outermost level only.
static const CGFloat kBlockquotePaddingVertical = 8.0;

@implementation BlockquoteRenderer

- (void)renderNode:(MarkdownASTNode *)node into:(NSMutableAttributedString *)output context:(RenderContext *)context
{
  NSInteger currentDepth = context.blockquoteDepth;
  context.blockquoteDepth = currentDepth + 1;

  [context setBlockStyle:BlockTypeBlockquote
                    font:[_config blockquoteFont]
                   color:[_config blockquoteColor]
            headingLevel:0];

  NSUInteger start = output.length;
  @try {
    [_rendererFactory renderChildrenOfNode:node into:output context:context];
  } @finally {
    [context clearBlockStyle];
    context.blockquoteDepth = currentDepth;
  }

  NSUInteger end = output.length;
  if (end <= start) {
    return;
  }

  [self applyStylingAndSpacing:output start:start end:end currentDepth:currentDepth context:context];
}

#pragma mark - Styling and Spacing

- (void)applyStylingAndSpacing:(NSMutableAttributedString *)output
                         start:(NSUInteger)start
                           end:(NSUInteger)end
                  currentDepth:(NSInteger)currentDepth
                       context:(RenderContext *)context
{
  NSUInteger contentStart = start;
  if (currentDepth == 0) {
    contentStart += applyBlockSpacingBefore(output, start, [_config blockquoteMarginTop]);
  }

  NSRange blockquoteRange = NSMakeRange(contentStart, end - start);
  CGFloat levelSpacing = [_config blockquoteBorderWidth] + [_config blockquoteGapWidth];
  NSArray<NSDictionary *> *nestedInfo = [self collectNestedBlockquotes:output range:blockquoteRange depth:currentDepth];

  // Apply base styling (indentation, depth, background, line height)
  [self applyBaseBlockquoteStyle:output
                           range:blockquoteRange
                           depth:currentDepth
                    levelSpacing:levelSpacing
                 backgroundColor:[_config blockquoteBackgroundColor]
                      lineHeight:[_config blockquoteLineHeight]];

  // Re-apply nested blockquote styles to restore their correct indentation
  // (applyBaseBlockquoteStyle overwrites nested indents with the parent's indent)
  [self reapplyNestedStyles:output nestedInfo:nestedInfo levelSpacing:levelSpacing];

  if (currentDepth == 0) {
    [self applyInnerVerticalPadding:output range:blockquoteRange context:context];
    applyBlockSpacingAfter(output, [_config blockquoteMarginBottom]);
  }
}

#pragma mark - Inner Vertical Padding

// Adds top and bottom inner padding by inserting spacer newlines that carry the
// blockquote depth/background attributes, so the border-and-background drawing
// extends over them (mirrors how the code block renderer pads its background).
- (void)applyInnerVerticalPadding:(NSMutableAttributedString *)output
                            range:(NSRange)blockquoteRange
                          context:(RenderContext *)context
{
  CGFloat padding = kBlockquotePaddingVertical;
  if (padding <= 0) {
    return;
  }

  RCTUIColor *backgroundColor = [_config blockquoteBackgroundColor];
  NSMutableParagraphStyle *contentStyle = getOrCreateParagraphStyle(output, blockquoteRange.location);
  NSWritingDirection writingDirection = contentStyle.baseWritingDirection;

  // Bottom padding: appended right after the content (still inside the background).
  NSUInteger bottomStart = NSMaxRange(blockquoteRange);
  [output appendAttributedString:kNewlineAttributedString];
  [output addAttributes:[self spacerAttributesWithPadding:padding
                                          backgroundColor:backgroundColor
                                         writingDirection:writingDirection
                                                  context:context]
                  range:NSMakeRange(bottomStart, 1)];

  // Top padding: inserted before the content (shifts content down by one char,
  // attributes already applied to the content move with it).
  [output insertAttributedString:kNewlineAttributedString atIndex:blockquoteRange.location];
  [output addAttributes:[self spacerAttributesWithPadding:padding
                                          backgroundColor:backgroundColor
                                         writingDirection:writingDirection
                                                  context:context]
                  range:NSMakeRange(blockquoteRange.location, 1)];
}

- (NSDictionary *)spacerAttributesWithPadding:(CGFloat)padding
                              backgroundColor:(RCTUIColor *)backgroundColor
                             writingDirection:(NSWritingDirection)writingDirection
                                      context:(RenderContext *)context
{
  NSMutableParagraphStyle *spacerStyle = [context spacerStyleWithHeight:padding spacing:0];
  spacerStyle.baseWritingDirection = writingDirection;

  NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
  attributes[NSParagraphStyleAttributeName] = spacerStyle;
  attributes[BlockquoteDepthAttributeName] = @(0);
  if (backgroundColor) {
    attributes[BlockquoteBackgroundColorAttributeName] = backgroundColor;
  }
  return attributes;
}

#pragma mark - Nested Blockquote Handling

- (NSArray<NSDictionary *> *)collectNestedBlockquotes:(NSMutableAttributedString *)output
                                                range:(NSRange)blockquoteRange
                                                depth:(NSInteger)currentDepth
{
  NSMutableArray<NSDictionary *> *nestedInfo = [NSMutableArray array];

  [output
      enumerateAttribute:BlockquoteDepthAttributeName
                 inRange:blockquoteRange
                 options:NSAttributedStringEnumerationLongestEffectiveRangeNotRequired
              usingBlock:^(id value, NSRange range, BOOL *stop) {
                NSInteger depth = [value integerValue];
                if (value && depth > currentDepth) {
                  [nestedInfo
                      addObject:@{kNestedInfoDepthKey : value, kNestedInfoRangeKey : [NSValue valueWithRange:range]}];
                }
              }];

  return nestedInfo;
}

- (void)applyBaseBlockquoteStyle:(NSMutableAttributedString *)output
                           range:(NSRange)blockquoteRange
                           depth:(NSInteger)currentDepth
                    levelSpacing:(CGFloat)levelSpacing
                 backgroundColor:(RCTUIColor *)backgroundColor
                      lineHeight:(CGFloat)lineHeight
{
  NSMutableParagraphStyle *paragraphStyle = getOrCreateParagraphStyle(output, blockquoteRange.location);
  CGFloat totalIndent = [self calculateIndentForDepth:currentDepth levelSpacing:levelSpacing];
  paragraphStyle.firstLineHeadIndent = totalIndent;
  paragraphStyle.headIndent = totalIndent;

  NSMutableDictionary *newAttributes =
      [NSMutableDictionary dictionaryWithObjectsAndKeys:paragraphStyle, NSParagraphStyleAttributeName, @(currentDepth),
                                                        BlockquoteDepthAttributeName, nil];
  if (backgroundColor) {
    newAttributes[BlockquoteBackgroundColorAttributeName] = backgroundColor;
  }
  [output addAttributes:newAttributes range:blockquoteRange];

  applyLineHeight(output, blockquoteRange, lineHeight);
}

- (void)reapplyNestedStyles:(NSMutableAttributedString *)output
                 nestedInfo:(NSArray<NSDictionary *> *)nestedInfo
               levelSpacing:(CGFloat)levelSpacing
{
  // Re-apply indentation to nested blockquotes since applyBaseBlockquoteStyle
  // overwrote them with the parent's indentation
  for (NSDictionary *info in nestedInfo) {
    NSRange nestedRange = [info[kNestedInfoRangeKey] rangeValue];
    NSInteger nestedDepth = [info[kNestedInfoDepthKey] integerValue];
    NSMutableParagraphStyle *style = getOrCreateParagraphStyle(output, nestedRange.location);

    CGFloat indent = [self calculateIndentForDepth:nestedDepth levelSpacing:levelSpacing];
    style.firstLineHeadIndent = indent;
    style.headIndent = indent;
    style.tailIndent = 0;

    [output
        addAttributes:@{NSParagraphStyleAttributeName : style, BlockquoteDepthAttributeName : info[kNestedInfoDepthKey]}
                range:nestedRange];
  }
}

#pragma mark - Helper Methods

- (CGFloat)calculateIndentForDepth:(NSInteger)depth levelSpacing:(CGFloat)levelSpacing
{
  return (depth + 1) * levelSpacing;
}

@end
