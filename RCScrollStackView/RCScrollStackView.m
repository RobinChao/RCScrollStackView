
#import "RCScrollStackView.h"
#import <objc/runtime.h>

#pragma mark - NSMutableArray (Extras) -

const char kRCScrollStackViewReorderGesture;

@interface UIView (Extras)

@property (nonatomic,retain)	UILongPressGestureRecognizer	*reorderGesture;

@end

@implementation UIView (Extras)

- (void)setReorderGesture:(UILongPressGestureRecognizer *)reorderGesture {
    objc_setAssociatedObject(self, &kRCScrollStackViewReorderGesture, reorderGesture, OBJC_ASSOCIATION_ASSIGN);
}

- (UILongPressGestureRecognizer*) reorderGesture {
    return objc_getAssociatedObject(self, &kRCScrollStackViewReorderGesture);
}

@end

@interface NSMutableArray (Extras)

- (void) moveObjectsAtIndexes:(NSIndexSet*)indexes toIndex:(NSInteger)index;

@end

@implementation NSMutableArray (Extras)

- (void) moveObjectsAtIndexes:(NSIndexSet*)indexes toIndex:(NSInteger)index {
    NSArray *objectsToMove = [self objectsAtIndexes: indexes];
    // If any of the removed objects come before the index, we want to decrement the index appropriately
    index -= [indexes countOfIndexesInRange: (NSRange){0, index}];
    [self removeObjectsAtIndexes: indexes];
    [self replaceObjectsInRange: (NSRange){index,0} withObjectsFromArray: objectsToMove];
}

@end

@interface RCScrollStackView () {
    NSMutableArray			*viewsArray;		// ordered list of the items
    NSMutableArray			*viewsArrayHeight;  // expanded heights of the views
    // Dragging support
    UIView					*draggingView;
    CGPoint					 draggingLastPoint;
    NSInteger				 draggingViewInitialIdx;
}

@end


#pragma mark - DMScrollViewStack -

@implementation RCScrollStackView

#pragma mark - Initialization -

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setup];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    
    if (self) {
        [self setup];
    }
    return self;
}

- (void)setup {
    _layoutMode = RCScrollStackViewLayoutModelOnlyScrollView;
    _allowsReordering = YES;
    // We want to maintain an internal array with the ordered list of the subviews and their best (expanded) height
    viewsArray = [[NSMutableArray alloc] init];
    viewsArrayHeight = [[NSMutableArray alloc] init];
}

- (void)dealloc {
    NSArray *list = [viewsArray copy];
    for (UIView *subview in list) {
        if ([subview isKindOfClass:[UIScrollView class]]) {
            [subview removeObserver:self forKeyPath:@"contentSize"];
        }
    }
    viewsArray = nil;
    viewsArrayHeight = nil;
}

- (void) prepareViewForRemove:(UIView *) aSubview {
    // remove observer
    if ([aSubview isKindOfClass:[UIScrollView class]])
        [aSubview removeObserver:self forKeyPath:@"contentSize"];
    
    // remove gesture
    NSInteger idx = [viewsArray indexOfObject:aSubview];
    if (aSubview.reorderGesture) {
        [aSubview removeGestureRecognizer:aSubview.reorderGesture];
        aSubview.reorderGesture = nil;
    }
    [aSubview removeFromSuperview];
    [viewsArray removeObject:aSubview];
    [viewsArrayHeight removeObjectAtIndex:idx];
}

#pragma mark - Properties -

- (NSArray *)contentViews {
    return [viewsArray copy];
}

#pragma mark - Manage Subviews -

- (void) setViews:(NSArray *) aSubviews {
    for (UIView *subview in [viewsArray copy])
        [self prepareViewForRemove:subview];
    [viewsArray removeAllObjects];
    [viewsArrayHeight removeAllObjects];
    
    if (aSubviews) {
        for (UIView *subview in aSubviews)
            [self insertSubview:subview atIndex:NSNotFound animated:NO layout:NO scroll:NO completion:NULL];
        [self layoutSubviews];
    }
}

- (void) scrollToSubview:(UIView *) aSubview animated:(BOOL)animated {
    if (![viewsArray containsObject:aSubview]) return;
    CGRect idealFrame = [self rectForSubviewAtIndex:[viewsArray indexOfObject:aSubview]];
    [self scrollRectToVisible:idealFrame animated:animated];
}

- (void) addSubview:(UIView *) aSubview animated:(BOOL) aAnimated completion:(void(^)(void)) aCompletion {
    [self insertSubview:aSubview atIndex:NSNotFound animated:aAnimated completion:aCompletion];
}

- (void) insertSubview:(UIView *)aSubview atIndex:(NSInteger) aIdx animated:(BOOL) aAnimated completion:(void (^)(void)) aCompletion  {
    [self insertSubview:aSubview atIndex:aIdx animated:aAnimated layout:YES scroll:NO completion:aCompletion];
}

- (void) insertSubview:(UIView *)aSubview atIndex:(NSInteger) aIdx animated:(BOOL) aAnimated
                layout:(BOOL) layoutImmediately scroll:(BOOL) scrollToMakeVisible completion:(void (^)(void)) aCompletion {
    
    
    BOOL isSubview = [aSubview isKindOfClass:[UIScrollView class]];
    [self addSubview:aSubview];
    [viewsArray addObject:aSubview];
    [viewsArrayHeight addObject:  @((isSubview ? ((UIScrollView*)aSubview).contentSize.height : CGRectGetHeight(aSubview.frame) ))];
    
    if (aIdx >= viewsArray.count) // Add at the bottom
        aIdx = (viewsArray.count-1);
    else {
        // Apply shift of data if specified index is provided
        if (aIdx < 0)
            aIdx = 0;
        NSIndexSet *moveIndx = [NSIndexSet indexSetWithIndex:viewsArray.count-1];
        [viewsArray moveObjectsAtIndexes:moveIndx toIndex:aIdx];
        [viewsArrayHeight moveObjectsAtIndexes:moveIndx toIndex:aIdx];
    }
    
    if ([aSubview isKindOfClass:[UIScrollView class]]) {
        ((UIScrollView*)aSubview).scrollEnabled = NO;
        [aSubview addObserver:self forKeyPath:@"contentSize" options:0 context:NULL];
    }
    
    if (_allowsReordering)
        [self addLongTapGestureRecognizerTo:aSubview];
    
    // We will use it to perform a slide from bottom animation on add
    if (aIdx > 0 && aAnimated) {
        [self sendSubviewToBack:aSubview];
        aSubview.frame = CGRectMake(0,
                                    CGRectGetMaxY([self rectForSubviewAtIndex:aIdx-1])-CGRectGetHeight(aSubview.frame),
                                    CGRectGetWidth(self.frame),
                                    CGRectGetHeight(aSubview.frame));
    }
    
    if (layoutImmediately) // Perform a layout subviews immedately
        [self layoutSubviews:aAnimated completion:^{
            if (scrollToMakeVisible) // Scroll to make new item visible if required
                [self scrollRectToVisible:[self rectForSubviewAtIndex:aIdx] animated:aAnimated];
            if (aCompletion) aCompletion();
        }];
}

- (void) removeSubviewAtIndex:(NSInteger) aIdx animated:(BOOL) aAnimated completion:(void (^)(void)) aCompletion {
    UIView *targetView = viewsArray[aIdx];
    if (aAnimated) {
        [viewsArray removeObjectAtIndex:aIdx];
        [self layoutSubviews:YES completion:^{
            targetView.alpha = 0.0f;
            [self prepareViewForRemove:targetView];
            if (aCompletion) aCompletion();
        }];
    }
}

#pragma mark - Layout Methods -

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"contentSize"]) {
        NSInteger idx = [viewsArray indexOfObject:object];
        if (idx != NSNotFound && [viewsArrayHeight[idx] floatValue] != ((UIScrollView*)object).contentSize.height) {
            viewsArrayHeight[idx] = [NSNumber numberWithFloat:((UIScrollView*)object).contentSize.height];
            [self layoutSubviews];
        }
    }
}

- (void) layoutSubviews {
    [self layoutSubviews:NO completion:NULL];
}

- (CGRect) rectForSubviewAtIndex:(NSInteger) aIdx {
    CGFloat offsetY = 0.0f;
    for (NSUInteger idx = 0; idx <= aIdx; ++idx) {
        if (idx == aIdx)
            return CGRectMake(0.0f,offsetY, self.frame.size.width,[viewsArrayHeight[idx] floatValue]);
        offsetY += [viewsArrayHeight[idx] floatValue];
    }
    return CGRectZero;
}

- (void) layoutSubviews:(BOOL) aAnimated completion:(void (^)(void)) aCompletion {
    // We put everything about the layout methods inside a block we can execute by animating frames or directly without animations
    void (^layoutBlock)(void) = ^void(void) {
        static BOOL isScrollView;
        static CGRect visibleRect;
        static CGFloat currentOffset;
        static CGRect idealFrame;
        static CGRect subviewFrame;
        
        // This is the visible portion of the enclosing scroll view
        // Any subview otherside this area will have a zero-frame (this is particularly useful for table/collections view where cells are allocated
        // and resued based upon the visible region of their container).
        visibleRect = CGRectMake(0.0f, self.contentOffset.y, CGRectGetWidth(self.frame), CGRectGetHeight(self.frame));
        currentOffset = 0.0f;
        NSUInteger idx = 0;
        for (UIView *subview in viewsArray) {
            isScrollView = [subview isKindOfClass:[UIScrollView class]];
            // This is the ideal (expanded) frame of the subview
            idealFrame = [self rectForSubviewAtIndex:idx];
            if (draggingView == nil || draggingView != subview) { // this is not the current dragging view
                // Real frame (subviewFrame) will be adjusted based upon the real visible area of the subview itself
                subviewFrame = idealFrame;
                if (CGRectIntersectsRect(visibleRect, idealFrame)) {
                    // Subview is (at least partially) visible
                    // With a simple view frame is the expanded frame (=idealFrame), so nothing to do in this case.
                    // With a scroll view we set the size of the scroll big enough to fit only the visible dimension
                    // The origin of the scrollview will be at max the top offset of the enclosing scrollview, height is adjusted based on the area
                    // We should also adjust the scrollview's contentOffset in order to simulate a real scrolling of the enclosing scrollview
                    if (isScrollView) {
                        CGFloat endOfScrollReachedValue = 0;
                        if (CGRectGetMinY(subviewFrame) < self.contentOffset.y) {
                            // When the scrollview offset y is behind the current offset of the outer scroll view we
                            // set the origin of the scrollview at y=0 and the height to the visible height of the scrollview itself from the outer view
                            endOfScrollReachedValue = (self.contentOffset.y+self.frame.size.height - CGRectGetMaxY(idealFrame));
                            subviewFrame.origin.y = self.contentOffset.y;
                            ((UIScrollView*)subview).contentOffset = CGPointMake(0,self.contentOffset.y-idealFrame.origin.y);
                        } else {
                            // We want to mantain the normal content offset until the table offset y > current visible offset
                            ((UIScrollView*)subview).contentOffset = CGPointZero;
                        }
                        CGFloat visibleHeight = MIN(self.contentSize.height,MAX(0,self.contentOffset.y+CGRectGetHeight(self.frame)-CGRectGetMinY(subviewFrame)));
                        subviewFrame.size.height = visibleHeight-endOfScrollReachedValue;
                    }
                    
                } else {
                    // If subview is invisible we can set it's frame to zero (with tables and collection view we can avoid loading hidden cells)
                    if (_layoutMode == RCScrollStackViewLayoutModelZeroAll || isScrollView)
                        subviewFrame = CGRectMake(0, subviewFrame.origin.y, CGRectGetWidth(self.frame), 0);
                    else
                        subviewFrame = idealFrame;
                }
                subview.frame = subviewFrame;
            }
            currentOffset += CGRectGetHeight(idealFrame);
            ++idx;
        }
        // Adjust the content size to reflect the total height of the subviews
        self.contentSize = CGSizeMake(CGRectGetWidth(visibleRect),currentOffset);
    };
    
    if (aAnimated) // we can execute it inside an animation
        [UIView animateWithDuration:0.25f animations:layoutBlock completion:^(BOOL finished) {
            if (aCompletion) aCompletion();
        }];
    else { // or directly without animation
        layoutBlock();
        if (aCompletion) aCompletion();
    }
}

#pragma mark - Reordering Support -

- (BOOL) addLongTapGestureRecognizerTo:(UIView *) aSubview {
    if (![viewsArray containsObject:aSubview])
        return NO;
    UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLong:)];
    [aSubview setUserInteractionEnabled:YES];
    [aSubview addGestureRecognizer:press];
    aSubview.reorderGesture = press;
    return YES;
}

#define DMScrollingSensitiveAreaHeight	50
#define DMScrollingScrollingSpace		20

- (void)setAllowsReordering:(BOOL)allowsReordering {
    _allowsReordering = allowsReordering;
    for (UIView *subview in viewsArray) {
        if (!allowsReordering) {
            [subview removeGestureRecognizer:subview.reorderGesture];
            subview.reorderGesture = nil;
        } else {
            if (!subview.reorderGesture)
                [self addLongTapGestureRecognizerTo:subview];
        }
    }
}

- (void) handleLong:(UILongPressGestureRecognizer *) gesture {
    
    if ([self.reorderDelegate respondsToSelector:@selector(stack:shouldMoveSubview:atIndex:)] &&
        ![self.reorderDelegate stack:self shouldMoveSubview:gesture.view atIndex:[viewsArray indexOfObject:gesture.view]]) {
        // This view does not support reorder
        gesture.enabled = NO;
        gesture.enabled = YES;
        return;
    }
    
    if (gesture.state == UIGestureRecognizerStateBegan) { // GESTURE BEGAN
        // Save the instance of dragging view so we don't touch it's frame during layoutSubviews while a dragging session is active
        draggingLastPoint = [gesture locationInView:self];
        draggingView = gesture.view;
        draggingView.frame = [self rectForSubviewAtIndex:[viewsArray indexOfObject:draggingView]];
        draggingViewInitialIdx = [viewsArray indexOfObject:draggingView];
        [self bringSubviewToFront:draggingView];
        
        self.clipsToBounds = NO;
        [UIView animateWithDuration:0.25f delay:0.0f usingSpringWithDamping:0.5f initialSpringVelocity:0.0f options:0 animations:^{
            draggingView.transform = CGAffineTransformMakeScale(1.05, 1.05);
        } completion:NULL];
        
    } else if (gesture.state == UIGestureRecognizerStateChanged) { // GESTURE CHANGED
        CGRect visibleRect = CGRectMake(0.0f, self.contentOffset.y, CGRectGetWidth(self.frame), CGRectGetHeight(self.frame));
        // Evaluate the translation and move the draggingView's y coordinate according to it
        CGPoint location = [gesture locationInView:self];
        CGPoint translation = CGPointMake( (location.x - draggingLastPoint.x), (location.y - draggingLastPoint.y) );
        draggingView.center = CGPointMake(draggingView.center.x, draggingView.center.y+translation.y);
        
        
        // If we are at the top of another we want to shift it up to take space for our draggingView
        UIView *behindView = [self subviewBehindPoint:CGPointMake(0.0f, CGRectGetMinY(draggingView.frame))];
        BOOL isScrollingDown = (translation.y > 0);
        
        // There is a sensitive area at the top/bottom edges of the enclosing scrollview
        // When the up/bottom (based upon translation direction) edge of the draggingView reach these parts
        // enclosing scroll view did scroll to make enough free space and move around inside the scrollview.
        // During this step reorder action is disabled.
        BOOL isInsideScrollingArea = NO;
        if (behindView) {
            if (isScrollingDown && CGRectGetMaxY(visibleRect) < self.contentSize.height) // scroll down
                isInsideScrollingArea = (CGRectGetMaxY(behindView.frame) >= CGRectGetMaxY(visibleRect)-30);
            else if (!isScrollingDown && CGRectGetMinY(visibleRect) > 0) // scroll up
                isInsideScrollingArea = (CGRectGetMinY(behindView.frame) <= CGRectGetMinY(visibleRect)+30);
        }
        
        if (isInsideScrollingArea) {
            // Scroll contentoffset up/down during dragging to make draggingView always visible and scrolling around enabled
            CGFloat visibleOffsetY;
            if (translation.y > 0) // scrolling down
                visibleOffsetY = CGRectGetMaxY(draggingView.frame)+MIN(DMScrollingSensitiveAreaHeight,CGRectGetHeight(draggingView.frame));
            else
                visibleOffsetY = CGRectGetMinY(draggingView.frame)-MIN(DMScrollingSensitiveAreaHeight,CGRectGetHeight(draggingView.frame));
            [self scrollRectToVisible:CGRectMake(0, visibleOffsetY, draggingView.frame.size.width, 1.0f) animated:NO];
        } else if (!isInsideScrollingArea && behindView) {
            // You want to reorder a subview, exchange behindView with draggingView and shift
            CGRect behindViewSensitiveRect = CGRectMake(0.0f,
                                                        CGRectGetMinY(behindView.frame),
                                                        CGRectGetWidth(visibleRect),
                                                        MIN(DMScrollingScrollingSpace,CGRectGetHeight(behindView.frame)));
            if (CGRectIntersectsRect(draggingView.frame, behindViewSensitiveRect)) {
                NSInteger exchangeBehindViewIdx = [viewsArray indexOfObject:behindView];
                NSInteger exchangeWithDraggingViewIdx = [viewsArray indexOfObject:draggingView];
                
                if ([_reorderDelegate respondsToSelector:@selector(stack:willMoveSubview:atIndex:)])
                    [_reorderDelegate stack:self willMoveSubview:draggingView atIndex:exchangeWithDraggingViewIdx];
                
                [viewsArray moveObjectsAtIndexes:[NSIndexSet indexSetWithIndex:exchangeWithDraggingViewIdx] toIndex:exchangeBehindViewIdx];
                [viewsArrayHeight moveObjectsAtIndexes:[NSIndexSet indexSetWithIndex:exchangeWithDraggingViewIdx] toIndex:exchangeBehindViewIdx];
                [self layoutSubviews:YES completion:NULL];
            }
        }
        
        draggingLastPoint = location;
        
    } else if (gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateEnded) { // GESTURE ENDED
        // End gesture, place draggingView to it's new position
        
        if ([_reorderDelegate respondsToSelector:@selector(stack:didMoveSubview:)] &&
            draggingViewInitialIdx != [viewsArray indexOfObject:draggingView])
            [_reorderDelegate stack:self didMoveSubview:draggingView];
        
        [UIView animateWithDuration:0.25 animations:^{
            draggingView.transform = CGAffineTransformIdentity;
        } completion:^(BOOL finished) {
            self.clipsToBounds = YES;
            draggingView = nil;
            [self layoutSubviews:YES completion:NULL];
        }];
    }
}

- (UIView *) subviewBehindPoint:(CGPoint) aPoint {
    for (UIView *subview in viewsArray)
        if (CGRectContainsPoint(subview.frame, aPoint) && subview != draggingView)
            return subview;
    return nil;
}

@end
