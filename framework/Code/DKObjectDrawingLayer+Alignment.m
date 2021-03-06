/**
 @author Contributions from the community; see CONTRIBUTORS.md
 @date 2005-2015
 @copyright GNU LGPL3; see LICENSE
*/

#import "DKObjectDrawingLayer+Alignment.h"

#import "DKDrawableShape.h"
#import "DKDrawing.h"
#import "DKGridLayer.h"
#import "LogEvent.h"

#pragma mark Static Functions

/** @brief Determines the relative vertical position order of a pair of objects

 Objects must respond to the -apparentBounds method
 @param a>, <b the objects to compare
 @return sort order constant */
static NSInteger vertLocSortFunc(DKDrawableObject* a, DKDrawableObject* b, void* context);

/** @brief Determines the relative horizontal position order of a pair of objects

 Objects must respond to the -apparentBounds method
 @param a>, <b the objects to compare
 @return sort order constant */
static NSInteger horizLocSortFunc(DKDrawableObject* a, DKDrawableObject* b, void* context);

#pragma mark -
@implementation DKObjectDrawingLayer (Alignment)
#pragma mark As a DKObjectDrawingLayer

/** @brief Nominates an object as the master to be used for alignment operations, etc

 The object is not retained as it should already be owned. A nil object can be set to mean that the
 topmost select object should be considered key.
 @param keyObject an object that is to be considered key for alignment ops
 */
- (void)setKeyObject:(DKDrawableObject*)keyObject
{
	if (keyObject != mKeyAlignmentObject) {
		mKeyAlignmentObject = keyObject;
		[[NSNotificationCenter defaultCenter] postNotificationName:kDKLayerKeyObjectDidChange
															object:self];
	}
}

/** @brief Returns the object as the master to be used for alignment operations, etc

 If no specific object is set (nil), then the first object in the selection is returned. If there's
 no selection, returns nil. 
 @return an object that is to be considered key for alignment ops
 */
- (DKDrawableObject*)keyObject
{
	if (mKeyAlignmentObject)
		return mKeyAlignmentObject;
	else {
		NSArray* sa = [self selectedVisibleObjects];

		if ([sa count] > 0)
			return [sa objectAtIndex:0];
		else
			return nil;
	}
}

/** @brief Aligns a set of objects

 Objects are aligned with the layer's nominated key object, by default the first object in the supplied list
 @param objects the objects to align
 @param align the alignment operation required
 */
- (void)alignObjects:(NSArray*)objects withAlignment:(NSInteger)align
{
	[self alignObjects:objects
		toMasterObject:[self keyObject]
		 withAlignment:align];
}

/** @brief Aligns a set ofobjects
 @param objects the objects to align
 @param object the "master" object - the one to which the others are aligned
 @param align the alignment operation required
 */
- (void)alignObjects:(NSArray*)objects toMasterObject:(id)object withAlignment:(NSInteger)align
{
	// if we are distributing the objects, use the distributor method first - master
	// doesn't come into it

	if ((align & kDKAlignmentDistributionMask) != 0)
		[self distributeObjects:objects
				  withAlignment:align];

	// apply other alignment flag if there is any

	if ((align & ~kDKAlignmentDistributionMask) != 0) {
		NSEnumerator* iter;
		id mo;
		NSRect mb, ob;
		NSPoint alignOffset;

		NSAssert(object != nil, @"cannot align - master object is nil");

		LogEvent_(kUserEvent, @"Aligning objects with alignment = %d", align);

		mb = [object apparentBounds];

		iter = [objects objectEnumerator];

		while ((mo = [iter nextObject])) {
			if (mo != object) {
				ob = [mo apparentBounds];
				alignOffset = calculateAlignmentOffset(mb, ob, align);
				[mo offsetLocationByX:alignOffset.x
								  byY:alignOffset.y];
			}
		}
	}
}

/** @brief Aligns a set of objects to a given point
 @param objects the objects to align
 @param loc the point to which the objects are aligned
 @param align the alignment operation required
 */
- (void)alignObjects:(NSArray*)objects toLocation:(NSPoint)loc withAlignment:(NSInteger)align
{
#pragma unused(objects)
#pragma unused(loc)
#pragma unused(align)

	// TO DO
}

#pragma mark -

/** @brief Aligns the objects to the grid, resizing and positioning as necessary so that all edges lie on
 the grid. The logical bounds is used for alignment, consistent with normal snapping behaviour.

 May minimally resize the objects.
 @param objects the objects to align
 @param grid the grid to use
 */
- (void)alignObjectEdges:(NSArray*)objects toGrid:(DKGridLayer*)grid
{
	NSAssert(grid != nil, @"grid parameter is nil");

	NSEnumerator* iter;
	DKDrawableObject* mo;
	NSRect objRect;
	NSSize offset;

	iter = [objects objectEnumerator];

	while ((mo = [iter nextObject])) {
		if ([mo respondsToSelector:@selector(adjustToFitGrid:)])
			[(id)mo adjustToFitGrid:grid];
		else {
			objRect = [mo logicalBounds];
			objRect.size = [mo size];
			offset = [mo offset];

			objRect.origin = [grid nearestGridIntersectionToPoint:objRect.origin];
			objRect.size = [grid nearestGridIntegralToSize:objRect.size];

			[mo setOffset:NSMakeSize(-0.5, -0.5)];

			[mo setLocation:objRect.origin];
			[mo setSize:objRect.size];
			[mo setOffset:offset];
		}
	}
}

/** @brief Aligns a set of objects so their locations lie on a grid intersection

 Does not resize the objects
 @param objects the objects to align
 @param grid the grid to use
 */
- (void)alignObjectLocation:(NSArray*)objects toGrid:(DKGridLayer*)grid
{
	NSAssert(grid != nil, @"grid parameter is nil");

	NSEnumerator* iter;
	DKDrawableObject* mo;
	NSPoint p;

	iter = [objects objectEnumerator];

	while ((mo = [iter nextObject])) {
		p = [grid nearestGridIntersectionToPoint:[mo location]];
		[mo setLocation:p];
	}
}

#pragma mark -

/** @brief Computes the amount of space available for a vertical distribution operation

 The list of objects must be sorted into order of their vertical location.
 The space is the total distance between the top and bottom objects, minus the sum of the heights
 of the objects in between
 @param objects the objects to align
 @return the total space available for distribution in the vertical direction
 */
- (CGFloat)totalVerticalSpace:(NSArray*)objects
{
	CGFloat span, sumHeight = 0.0;
	NSUInteger i;
	id mo;
	NSRect br;
	CGFloat prevLowerEdge;

	prevLowerEdge = NSMaxY([[objects objectAtIndex:0] logicalBounds]);
	span = NSMinY([[objects lastObject] logicalBounds]) - prevLowerEdge;

	for (i = 1; i < [objects count] - 1; i++) {
		mo = [objects objectAtIndex:i];
		br = [mo logicalBounds];
		sumHeight += br.size.height;
	}

	return span - sumHeight;
}

/** @brief Computes the amount of space available for a horizontal distribution operation

 The list of objects must be sorted into order of their horizontal location.
 The space is the total distance between the leftmost and rightmost objects, minus the sum of the widths
 of the objects in between
 @param objects the objects to align
 @return the total space available for distribution in the horizontal direction
 */
- (CGFloat)totalHorizontalSpace:(NSArray*)objects
{
	CGFloat span, sumWidth = 0.0;
	NSUInteger i;
	id mo;
	NSRect br;
	CGFloat prevLowerEdge;

	prevLowerEdge = NSMaxX([[objects objectAtIndex:0] logicalBounds]);
	span = NSMinX([[objects lastObject] logicalBounds]) - prevLowerEdge;

	for (i = 1; i < [objects count] - 1; i++) {
		mo = [objects objectAtIndex:i];
		br = [mo logicalBounds];
		sumWidth += br.size.width;
	}

	return span - sumWidth;
}

#pragma mark -

/** @brief Sorts a set of objects into order of their vertical location
 @param objects the objects to sort
 @return a copy of the array sorted into vertical order
 */
- (NSArray*)objectsSortedByVerticalPosition:(NSArray*)objects
{
	LogEvent_(kReactiveEvent, @"sorting objects into vertical order");

	NSMutableArray* na = [objects mutableCopy];

	[na sortUsingFunction:vertLocSortFunc
				  context:nil];
	return [na autorelease];
}

/** @brief Sorts a set of objects into order of their horizontal location
 @param objects the objects to sort
 @return a copy of the array sorted into horizontal order
 */
- (NSArray*)objectsSortedByHorizontalPosition:(NSArray*)objects
{
	LogEvent_(kReactiveEvent, @"sorting objects into horizontal order");

	NSMutableArray* na = [objects mutableCopy];

	[na sortUsingFunction:horizLocSortFunc
				  context:nil];
	return [na autorelease];
}

#pragma mark -

/** @brief Distributes a set of objects

 Normally this is called by the higher level alignObjects: methods when a distribution alignment is
 detected
 @param objects the objects to distribute
 @param align the distribution required
 @return YES if the operation could be performed, NO otherwise
 */
- (BOOL)distributeObjects:(NSArray*)objects withAlignment:(NSInteger)align
{
	// distribute the objects - this is usually called from the alignment method as needed - calling it directly will
	// ignore any edge alignment set.

	NSArray* sorted;
	NSInteger numToAlign, i;
	CGFloat spanDistance, spanIncrement, min, max;
	DKDrawableObject* mo;

	numToAlign = [objects count];

	// needs to be a minimum of three for this method to do anything useful

	if (numToAlign < 3)
		return NO;

	if (align & kDKAlignmentAlignVDistribution) {
		sorted = [self objectsSortedByVerticalPosition:objects];

		// find the span distance - the difference between the first and last objects

		min = [(DKDrawableObject*)[sorted objectAtIndex:0] location].y;
		max = [(DKDrawableObject*)[sorted lastObject] location].y;

		spanDistance = max - min; //NSMidY( bottom ) - NSMidY( top );
		spanIncrement = spanDistance / (CGFloat)(numToAlign - 1);

		//	LogEvent_(kReactiveEvent, @"vertically distributing %d objects, increment = %f, span = %f", numToAlign, spanIncrement, spanDistance );

		NSPoint cp;

		// iterate through the objects between the two, setting their vertical position accordingly

		for (i = 1; i < (numToAlign - 1); i++) {
			mo = [sorted objectAtIndex:i];

			cp.x = [mo location].x;
			cp.y = min + ((CGFloat)i * spanIncrement);

			//	LogEvent_(kReactiveEvent,  @"positioning object %d, {%f, %f}", i, cp.x, cp.y );

			[mo setLocation:cp];
		}
	}

	if (align & kDKAlignmentAlignHDistribution) {
		sorted = [self objectsSortedByHorizontalPosition:objects];

		// find the span distance - the difference between the first and last objects

		min = [(DKDrawableObject*)[sorted objectAtIndex:0] location].x;
		max = [(DKDrawableObject*)[sorted lastObject] location].x;

		spanDistance = max - min; //NSMidX( bottom ) - NSMidX( top );
		spanIncrement = spanDistance / (CGFloat)(numToAlign - 1);

		NSPoint cp;

		// iterate through the objects between the two, setting their vertical position accordingly

		for (i = 1; i < (numToAlign - 1); i++) {
			mo = [sorted objectAtIndex:i];

			cp.y = [mo location].y;
			cp.x = min + ((CGFloat)i * spanIncrement);

			[mo setLocation:cp];
		}
	}

	if (align & kDKAlignmentAlignVSpaceDistribution) {
		// the space between the objects is shared out equally.
		sorted = [self objectsSortedByVerticalPosition:objects];
		CGFloat space = [self totalVerticalSpace:sorted];
		CGFloat spaceEach = space / (CGFloat)(numToAlign - 1);
		CGFloat nte;
		NSRect mobr;
		NSRect prevBounds = NSZeroRect;

		// if the space is zero or negative, the objects overlap to a degree, and the space can't be distributed

		if (space > 0.0) {
			//	LogEvent_(kReactiveEvent, @"distributing space = %f among %d objects", space, numToAlign );

			NSPoint cp;

			for (i = 0; i < numToAlign - 1; i++) {
				mo = [sorted objectAtIndex:i];
				mobr = [mo logicalBounds];

				if (i > 0) {
					cp.x = [mo location].x;

					// top edge of this object is bottom edge of last + spaceEach, but we are calculating the
					// centre

					nte = NSMaxY(prevBounds) + spaceEach;
					cp.y = NSMidY(mobr) - NSMinY(mobr) + nte;

					[mo setLocation:cp];
					mobr = [mo logicalBounds];
				}
				prevBounds = mobr;
			}
		}
	}

	if (align & kDKAlignmentAlignHSpaceDistribution) {
		// the space between the objects is shared out equally.
		sorted = [self objectsSortedByHorizontalPosition:objects];
		CGFloat space = [self totalHorizontalSpace:sorted];
		CGFloat spaceEach = space / (CGFloat)(numToAlign - 1);
		CGFloat nte;
		NSRect mobr;
		NSRect prevBounds = NSZeroRect;

		// if the space is zero or negative, the objects overlap to a degree, and the space can't be distributed

		if (space > 0.0) {
			//	LogEvent_(kReactiveEvent, @"distributing space = %f among %d objects", space, numToAlign );

			NSPoint cp;

			for (i = 0; i < numToAlign - 1; i++) {
				mo = [sorted objectAtIndex:i];
				mobr = [mo logicalBounds];

				if (i > 0) {
					cp.y = [mo location].y;

					// top edge of this object is bottom edge of last + spaceEach, but we are calculating the
					// centre

					nte = NSMaxX(prevBounds) + spaceEach;
					cp.x = NSMidX(mobr) - NSMinX(mobr) + nte;

					[mo setLocation:cp];
					mobr = [mo logicalBounds];
				}
				prevBounds = mobr;
			}
		}
	}

	return YES;
}

#pragma mark -

/** @brief Returns the minimum number of objects needed to enable the user interface item

 Call this from a generic validateMenuItem method for the layer as a whole
 @param item the user interface item to validate
 @return number of objects needed for validation. If the item isn't a known alignment command, returns 0
 */
- (NSUInteger)alignmentMenuItemRequiredObjects:(id<NSValidatedUserInterfaceItem>)item
{
	SEL action = [item action];

	if (action == @selector(alignLeftEdges:) || action == @selector(alignRightEdges:) || action == @selector(alignHorizontalCentres:) || action == @selector(alignTopEdges:) || action == @selector(alignBottomEdges:) || action == @selector(alignVerticalCentres:))
		return 2;
	else if (action == @selector(distributeVerticalCentres:) || action == @selector(distributeVerticalSpace:) || action == @selector(distributeHorizontalCentres:) || action == @selector(distributeHorizontalSpace:))
		return 3;
	else if (action == @selector(alignEdgesToGrid:) || action == @selector(alignLocationToGrid:) || action == @selector(assignKeyObject:))
		return 1;

	return 0;
}

#pragma mark -
#pragma mark - user actions

/** @brief Aligns the selected objects on their left edges
 @param sender the action's sender
 */
- (IBAction)alignLeftEdges:(id)sender
{
#pragma unused(sender)

	if (![self locked]) {
		[self alignObjects:[self selectedAvailableObjects]
			 withAlignment:kDKAlignmentAlignLeftEdge];
		[[self undoManager] setActionName:NSLocalizedString(@"Align Left Edges", @"undo string for align left edges")];
	}
}

/** @brief Aligns the selected objects on their right edges
 @param sender the action's sender
 */
- (IBAction)alignRightEdges:(id)sender
{
#pragma unused(sender)

	if (![self locked]) {
		[self alignObjects:[self selectedAvailableObjects]
			 withAlignment:kDKAlignmentAlignRightEdge];
		[[self undoManager] setActionName:NSLocalizedString(@"Align Right Edges", @"undo string for align right edges")];
	}
}

/** @brief Aligns the selected objects on their horizontal centres
 @param sender the action's sender
 */
- (IBAction)alignHorizontalCentres:(id)sender
{
#pragma unused(sender)

	if (![self locked]) {
		[self alignObjects:[self selectedAvailableObjects]
			 withAlignment:kDKAlignmentAlignHorizontalCentre];
		[[self undoManager] setActionName:NSLocalizedString(@"Align Horizontal Centres", @"undo string for align h centres")];
	}
}

#pragma mark -

/** @brief Aligns the selected objects on their top edges
 @param sender the action's sender
 */
- (IBAction)alignTopEdges:(id)sender
{
#pragma unused(sender)

	if (![self locked]) {
		[self alignObjects:[self selectedAvailableObjects]
			 withAlignment:kDKAlignmentAlignTopEdge];
		[[self undoManager] setActionName:NSLocalizedString(@"Align Top Edges", @"undo string for align top edges")];
	}
}

/** @brief Aligns the selected objects on their bottom edges
 @param sender the action's sender
 */
- (IBAction)alignBottomEdges:(id)sender
{
#pragma unused(sender)

	if (![self locked]) {
		[self alignObjects:[self selectedAvailableObjects]
			 withAlignment:kDKAlignmentAlignBottomEdge];
		[[self undoManager] setActionName:NSLocalizedString(@"Align Bottom Edges", @"undo string for align bottom edges")];
	}
}

/** @brief Aligns the selected objects on their vertical centres
 @param sender the action's sender
 */
- (IBAction)alignVerticalCentres:(id)sender
{
#pragma unused(sender)

	if (![self locked]) {
		[self alignObjects:[self selectedAvailableObjects]
			 withAlignment:kDKAlignmentAlignVerticalCentre];
		[[self undoManager] setActionName:NSLocalizedString(@"Align Vertical Centres", @"undo string for align v centres")];
	}
}

#pragma mark -

/** @brief Distributes the selected objects to equalize the vertical centres
 @param sender the action's sender
 */
- (IBAction)distributeVerticalCentres:(id)sender
{
#pragma unused(sender)

	if (![self locked]) {
		[self alignObjects:[self selectedAvailableObjects]
			 withAlignment:kDKAlignmentAlignVDistribution];
		[[self undoManager] setActionName:NSLocalizedString(@"Distribute Vertically", @"undo string for distribute v centres")];
	}
}

/** @brief Distributes the selected objects to equalize the vertical space
 @param sender the action's sender
 */
- (IBAction)distributeVerticalSpace:(id)sender
{
#pragma unused(sender)

	if (![self locked]) {
		[self alignObjects:[self selectedAvailableObjects]
			 withAlignment:kDKAlignmentAlignVSpaceDistribution];
		[[self undoManager] setActionName:NSLocalizedString(@"Distribute Vertical Space", @"undo string for distribute v space")];
	}
}

#pragma mark -

/** @brief Distributes the selected objects to equalize the horizontal centres
 @param sender the action's sender
 */
- (IBAction)distributeHorizontalCentres:(id)sender
{
#pragma unused(sender)

	if (![self locked]) {
		[self alignObjects:[self selectedAvailableObjects]
			 withAlignment:kDKAlignmentAlignHDistribution];
		[[self undoManager] setActionName:NSLocalizedString(@"Distribute Horizontally", @"undo string for distribute h centres")];
	}
}

/** @brief Distributes the selected objects to equalize the horizontal space
 @param sender the action's sender
 */
- (IBAction)distributeHorizontalSpace:(id)sender
{
#pragma unused(sender)

	if (![self locked]) {
		[self alignObjects:[self selectedAvailableObjects]
			 withAlignment:kDKAlignmentAlignHSpaceDistribution];
		[[self undoManager] setActionName:NSLocalizedString(@"Distribute Horizontal Space", @"undo string for distribute h space")];
	}
}

#pragma mark -
- (IBAction)alignEdgesToGrid:(id)sender
{
#pragma unused(sender)

	if (![self locked]) {
		DKGridLayer* grid = [[self drawing] gridLayer];
		[self alignObjectEdges:[self selectedAvailableObjects]
						toGrid:grid];
		[[self undoManager] setActionName:NSLocalizedString(@"Align Edges To Grid", @"undo string for align edges to grid")];
	}
}

- (IBAction)alignLocationToGrid:(id)sender
{
#pragma unused(sender)

	if (![self locked]) {
		DKGridLayer* grid = [[self drawing] gridLayer];
		[self alignObjectLocation:[self selectedAvailableObjects]
						   toGrid:grid];
		[[self undoManager] setActionName:NSLocalizedString(@"Align Objects To Grid", @"undo string for align objects to grid")];
	}
}

- (IBAction)assignKeyObject:(id)sender
{
#pragma unused(sender)

	DKDrawableObject* obj = [self singleSelection];
	[self setKeyObject:obj];
}

@end

#pragma mark -
#pragma mark Static Functions

static NSInteger vertLocSortFunc(DKDrawableObject* a, DKDrawableObject* b, void* context)
{
#pragma unused(context)

	CGFloat ya, yb;

	ya = [a location].y;
	yb = [b location].y;

	if (ya < yb)
		return NSOrderedAscending;
	else if (ya > yb)
		return NSOrderedDescending;
	else
		return NSOrderedSame;
}

static NSInteger horizLocSortFunc(DKDrawableObject* a, DKDrawableObject* b, void* context)
{
#pragma unused(context)

	CGFloat xa, xb;

	xa = [a location].x;
	xb = [b location].x;

	if (xa < xb)
		return NSOrderedAscending;
	else if (xa > xb)
		return NSOrderedDescending;
	else
		return NSOrderedSame;
}

#pragma mark -

/** @brief Returns an offset indicating the distance sr needs to be moved to give the chosen alignment with mr
 @param mr>, <sr two bounding rectangles
 @param alignment the type of alignment being applied
 @return an x and y offset */
NSPoint calculateAlignmentOffset(NSRect mr, NSRect sr, NSInteger alignment)
{
	NSPoint p = { 0, 0 };

	if (alignment & kDKAlignmentAlignLeftEdge)
		p.x = NSMinX(mr) - NSMinX(sr);

	if (alignment & kDKAlignmentAlignTopEdge)
		p.y = NSMinY(mr) - NSMinY(sr);

	if (alignment & kDKAlignmentAlignRightEdge)
		p.x = NSMaxX(mr) - NSMaxX(sr);

	if (alignment & kDKAlignmentAlignBottomEdge)
		p.y = NSMaxY(mr) - NSMaxY(sr);

	if (alignment & kDKAlignmentAlignVerticalCentre)
		p.y = NSMidY(mr) - NSMidY(sr);

	if (alignment & kDKAlignmentAlignHorizontalCentre)
		p.x = NSMidX(mr) - NSMidX(sr);

	return p;
}
