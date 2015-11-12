

#import <UIKit/UIKit.h>


typedef NS_ENUM(NSInteger, RCScrollStackViewLayoutModel) {
    RCScrollStackViewLayoutModelZeroAll,
    RCScrollStackViewLayoutModelOnlyScrollView
};

@class RCScrollStackView;

@protocol RCScrollStackViewReorderDelegate <NSObject>

@optional
- (void) stack:(RCScrollStackView *) stack willMoveSubview:(UIView *) aSubview atIndex:(NSInteger) aIdx;
- (void) stack:(RCScrollStackView *) stack didMoveSubview:(UIView *) aSubview;
- (BOOL) stack:(RCScrollStackView *)stack shouldMoveSubview:(UIView *) aSubview atIndex:(NSInteger) aIdx;
@end


@interface RCScrollStackView : UIScrollView


/**
 *  Read only copy of the subviews inside the stack
 */
@property (nonatomic,readonly)	NSArray		*contentViews;

/**
 *  YES to allows reordering with long-tap on subview and drag
 */
@property (nonatomic,assign)	BOOL		 allowsReordering;

/**
 *  Setup layout mode in -layoutSubviews
 */
@property (nonatomic,assign)	RCScrollStackViewLayoutModel	layoutMode;

/**
 *  Reorder actions delegate
 */
@property (nonatomic,weak)		id <RCScrollStackViewReorderDelegate>	reorderDelegate;

/**
 *  Set order subviews of the stack (from the top)
 *
 *  @param aSubviews list of ordered subviews to set (any other existing subview will be removed)
 */
- (void) setViews:(NSArray *) aSubviews;

/**
 *  Append a new subview at the bottom of the stack
 *
 *  @param aSubview  subview to place at the bottom of the stack
 *  @param aAnimated YES to animate the operation
 *  @param aCompletion define a completion block to execute at the end of the operation
 */
- (void) addSubview:(UIView *) aSubview animated:(BOOL) aAnimated completion:(void(^)(void)) aCompletion;

/**
 *  Inset a new subview at specified index of the stack
 *
 *  @param aSubview    subview to place
 *  @param aIdx        destination index
 *  @param aAnimated YES to animate the operation
 *  @param aCompletion define a completion block to execute at the end of the operation
 */
- (void) insertSubview:(UIView *)aSubview atIndex:(NSInteger) aIdx animated:(BOOL) aAnimated completion:(void (^)(void)) aCompletion;

/**
 *  Remove subview at index
 *
 *  @param aIdx      index of the subview to remove from the stack
 *  @param aAnimated YES to animate the operation
 *  @param aCompletion define a completion block to execute at the end of the operation
 */
- (void) removeSubviewAtIndex:(NSInteger) aIdx animated:(BOOL) aAnimated completion:(void (^)(void)) aCompletion;

/**
 *  Scroll to specified subview
 *
 *  @param aSubview	target subview
 *	@param aAnimated YES to animate scroll
 **/
- (void) scrollToSubview:(UIView *) aSubview animated:(BOOL)animated;

@end
