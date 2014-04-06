extern "C" {
#import "YapDatabaseSearchResultsViewTransaction.h"
#import "YapDatabaseSearchResultsViewPrivate.h"
#import "YapDatabaseViewChangePrivate.h"
#import "YapDatabaseFullTextSearchPrivate.h"
#import "YapDatabaseExtensionPrivate.h"
#import "YapDatabasePrivate.h"
#import "YapCollectionKey.h"
#import "YapDatabaseLogging.h"
}

#include <unordered_set>

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

/**
 * Define log level for this file: OFF, ERROR, WARN, INFO, VERBOSE
 * See YapDatabaseLogging.h for more information.
**/
#if DEBUG
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#else
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#endif


@implementation YapDatabaseSearchResultsViewTransaction
{
	std::unordered_set<int64_t> *ftsRowids;
}

- (id)initWithViewConnection:(YapDatabaseViewConnection *)inViewConnection
         databaseTransaction:(YapDatabaseReadTransaction *)inDatabaseTransaction
{
	if ((self = [super initWithViewConnection:inViewConnection databaseTransaction:inDatabaseTransaction]))
	{
		ftsRowids = new std::unordered_set<int64_t>();
	}
	return self;
}

- (void)dealloc
{
	if (ftsRowids) {
		delete ftsRowids;
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Extension Lifecycle
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Required override method from YapDatabaseExtensionTransaction.
 *
 * This method is called to create any necessary tables (if needed),
 * as well as populate the view (if needed) by enumerating over the existing rows in the database.
**/
- (BOOL)createIfNeeded
{
	YDBLogAutoTrace();

	// Todo...
	return YES;
}

/**
 * This method is called to prepare the transaction for use.
 *
 * Remember, an extension transaction is a very short lived object.
 * Thus it stores the majority of its state within the extension connection (the parent).
 *
 * Return YES if completed successfully, or if already prepared.
 * Return NO if some kind of error occured.
**/
- (BOOL)prepareIfNeeded
{
	YDBLogAutoTrace();
	
	BOOL result = [super prepareIfNeeded];
	if (result)
	{
		__unsafe_unretained YapDatabaseSearchResultsViewConnection *searchResultsConnection =
		  (YapDatabaseSearchResultsViewConnection *)viewConnection;
		
		searchResultsConnection->query = [self stringValueForExtensionKey:@"query"];
	}
	
	return result;
	
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark YapDatabaseExtensionTransaction_Hooks
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
 * This method overrides the version in YapDatabaseViewTransaction.
**/
- (void)handleInsertObject:(id)object
          forCollectionKey:(YapCollectionKey *)collectionKey
              withMetadata:(id)metadata
                     rowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	  (YapDatabaseSearchResultsView *)viewConnection->view;
	
	NSString *group = nil;
	
	if (searchResultsView->parentViewName)
	{
		// Instead of going to the groupingBlock,
		// just ask the parentViewTransaction what the last group was.
		
		__unsafe_unretained YapDatabaseViewTransaction *parentViewTransaction =
		  [databaseTransaction ext:searchResultsView->parentViewName];
		
		group = parentViewTransaction->lastHandledGroup;
	}
	else
	{
		// Invoke the grouping block to find out if the object should be included in the view.
		
		__unsafe_unretained NSString *collection = collectionKey.collection;
		__unsafe_unretained NSString *key = collectionKey.key;
		
		NSSet *allowedCollections = searchResultsView->options.allowedCollections;
		
		if (!allowedCollections || [allowedCollections containsObject:collection])
		{
			if (searchResultsView->groupingBlockType == YapDatabaseViewBlockTypeWithKey)
			{
				__unsafe_unretained YapDatabaseViewGroupingWithKeyBlock groupingBlock =
			      (YapDatabaseViewGroupingWithKeyBlock)searchResultsView->groupingBlock;
				
				group = groupingBlock(collection, key);
			}
			else if (searchResultsView->groupingBlockType == YapDatabaseViewBlockTypeWithObject)
			{
				__unsafe_unretained YapDatabaseViewGroupingWithObjectBlock groupingBlock =
			      (YapDatabaseViewGroupingWithObjectBlock)searchResultsView->groupingBlock;
				
				group = groupingBlock(collection, key, object);
			}
			else if (searchResultsView->groupingBlockType == YapDatabaseViewBlockTypeWithMetadata)
			{
				__unsafe_unretained YapDatabaseViewGroupingWithMetadataBlock groupingBlock =
			      (YapDatabaseViewGroupingWithMetadataBlock)searchResultsView->groupingBlock;
				
				group = groupingBlock(collection, key, metadata);
			}
			else
			{
				__unsafe_unretained YapDatabaseViewGroupingWithRowBlock groupingBlock =
			      (YapDatabaseViewGroupingWithRowBlock)searchResultsView->groupingBlock;
				
				group = groupingBlock(collection, key, object, metadata);
			}
		}
	}
	
	BOOL matchesQuery = NO;
	
	if (group)
	{
		__unsafe_unretained YapDatabaseFullTextSearchTransaction *ftsTransaction =
		  [databaseTransaction ext:searchResultsView->fullTextSearchName];
		
		matchesQuery = [ftsTransaction rowid:rowid matches:[self query]];
	}
	
	if (matchesQuery)
	{
		// Add to view.
		// This was an insert operation, so we know it wasn't already in the view.
		
		int flags = (YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata);
		
		[self insertRowid:rowid
		    collectionKey:collectionKey
		           object:object
		         metadata:metadata
		          inGroup:group withChanges:flags isNew:YES];
		
		lastHandledGroup = group;
	}
	else
	{
		// Not in view (not in parentView, or groupingBlock said NO, or doesn't match query).
		// This was an insert operation, so we know it wasn't already in the view.
		
		lastHandledGroup = nil;
	}
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
 * This method overrides the version in YapDatabaseViewTransaction.
**/
- (void)handleUpdateObject:(id)object
          forCollectionKey:(YapCollectionKey *)collectionKey
              withMetadata:(id)metadata
                     rowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	  (YapDatabaseSearchResultsView *)viewConnection->view;
	
	NSString *group = nil;
	
	if (searchResultsView->parentViewName)
	{
		// Instead of going to the groupingBlock,
		// just ask the parentViewTransaction what the last group was.
		
		__unsafe_unretained YapDatabaseViewTransaction *parentViewTransaction =
		  [databaseTransaction ext:searchResultsView->parentViewName];
		
		group = parentViewTransaction->lastHandledGroup;
	}
	else
	{
		// Invoke the grouping block to find out if the object should be included in the view.
		
		__unsafe_unretained NSString *collection = collectionKey.collection;
		__unsafe_unretained NSString *key = collectionKey.key;
		
		NSSet *allowedCollections = searchResultsView->options.allowedCollections;
		
		if (!allowedCollections || [allowedCollections containsObject:collection])
		{
			if (searchResultsView->groupingBlockType == YapDatabaseViewBlockTypeWithKey)
			{
				__unsafe_unretained YapDatabaseViewGroupingWithKeyBlock groupingBlock =
			      (YapDatabaseViewGroupingWithKeyBlock)searchResultsView->groupingBlock;
				
				group = groupingBlock(collection, key);
			}
			else if (searchResultsView->groupingBlockType == YapDatabaseViewBlockTypeWithObject)
			{
				__unsafe_unretained YapDatabaseViewGroupingWithObjectBlock groupingBlock =
			      (YapDatabaseViewGroupingWithObjectBlock)searchResultsView->groupingBlock;
				
				group = groupingBlock(collection, key, object);
			}
			else if (searchResultsView->groupingBlockType == YapDatabaseViewBlockTypeWithMetadata)
			{
				__unsafe_unretained YapDatabaseViewGroupingWithMetadataBlock groupingBlock =
			      (YapDatabaseViewGroupingWithMetadataBlock)searchResultsView->groupingBlock;
				
				group = groupingBlock(collection, key, metadata);
			}
			else
			{
				__unsafe_unretained YapDatabaseViewGroupingWithRowBlock groupingBlock =
			      (YapDatabaseViewGroupingWithRowBlock)searchResultsView->groupingBlock;
				
				group = groupingBlock(collection, key, object, metadata);
			}
		}
	}
	
	BOOL matchesQuery = NO;
	
	if (group)
	{
		__unsafe_unretained YapDatabaseFullTextSearchTransaction *ftsTransaction =
		  [databaseTransaction ext:searchResultsView->fullTextSearchName];
		
		matchesQuery = [ftsTransaction rowid:rowid matches:[self query]];
	}
	
	if (matchesQuery)
	{
		// Add key to view (or update position).
		// This was an update operation, so the key may have previously been in the view.
		
		int flags = (YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata);
		
		[self insertRowid:rowid
		    collectionKey:collectionKey
		           object:object
		         metadata:metadata
		          inGroup:group
		      withChanges:flags
		            isNew:NO];
		
		lastHandledGroup = group;
	}
	else
	{
		// Not in view (not in parentView, or groupingBlock said NO, or doesn't match query).
		// Remove from view (if needed).
		// This was an update operation, so it may have previously been in the view.
		
		[self removeRowid:rowid collectionKey:collectionKey];
		lastHandledGroup = nil;
	}
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
 * This method overrides the version in YapDatabaseViewTransaction.
**/
- (void)handleReplaceObject:(id)object forCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	  (YapDatabaseSearchResultsView *)viewConnection->view;
	
	if (searchResultsView->parentViewName)
	{
		// Implementation Note:
		// This code is modeled after that in YapDatabaseFilteredViewTransaction.
		
		BOOL groupMayHaveChanged = searchResultsView->groupingBlockType == YapDatabaseViewBlockTypeWithRow ||
		                           searchResultsView->groupingBlockType == YapDatabaseViewBlockTypeWithObject;
		
		BOOL sortMayHaveChanged = searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithRow ||
		                          searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithObject;
		
		// Instead of going to the groupingBlock,
		// just ask the parentViewTransaction what the last group was.
		
		__unsafe_unretained YapDatabaseViewTransaction *parentViewTransaction =
		  [databaseTransaction ext:searchResultsView->parentViewName];
		
		NSString *group = parentViewTransaction->lastHandledGroup;
		
		if (group == nil)
		{
			// Not included in parentView.
			
			if (groupMayHaveChanged)
			{
				// Remove from view (if needed).
				// This was an update operation, so it may have previously been in the view.
				
				[self removeRowid:rowid collectionKey:collectionKey];
			}
			else
			{
				// The group hasn't changed.
				// Thus it wasn't previously in view, and still isn't in the view.
			}
			
			lastHandledGroup = nil;
			return;
		}
		
		__unsafe_unretained YapDatabaseFullTextSearchTransaction *ftsTransaction =
		  [databaseTransaction ext:searchResultsView->fullTextSearchName];
		
		__unsafe_unretained YapDatabaseFullTextSearch *fts =
		  (YapDatabaseFullTextSearch *)[[ftsTransaction extensionConnection] extension];
		
		BOOL searchMayHaveChanged = fts->blockType == YapDatabaseFullTextSearchBlockTypeWithRow ||
		                            fts->blockType == YapDatabaseFullTextSearchBlockTypeWithObject;
		
		if (!groupMayHaveChanged && !sortMayHaveChanged && !searchMayHaveChanged)
		{
			// Nothing has changed that could possibly affect the view.
			// Just note the touch.
			
			int flags = YapDatabaseViewChangedObject;
			
			NSString *pageKey = [self pageKeyForRowid:rowid];
			NSUInteger existingIndex = [self indexForRowid:rowid inGroup:group withPageKey:pageKey];
			
			[viewConnection->changes addObject:
			 [YapDatabaseViewRowChange updateKey:collectionKey changes:flags inGroup:group atIndex:existingIndex]];
			
			lastHandledGroup = group;
			return;
		}
		
		BOOL matchesQuery = [ftsTransaction rowid:rowid matches:[self query]];
		
		if (matchesQuery)
		{
			// Add to view (or update position).
			// This was an update operation, so it may have previously been in the view.
			
			int flags = (YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata);
			
			id metadata = nil;
			if (searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithRow ||
			    searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithMetadata)
			{
				metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
			}
			
			[self insertRowid:rowid
			    collectionKey:collectionKey
			           object:object
			         metadata:metadata
			          inGroup:group
			      withChanges:flags
			            isNew:NO];
			
			lastHandledGroup = group;
		}
		else
		{
			// Filtered from this view.
			// Remove key from view (if needed).
			// This was an update operation, so it may have previously been in the view.
			
			[self removeRowid:rowid collectionKey:collectionKey];
			lastHandledGroup = nil;
		}
	}
	else
	{
		// Implementation Note:
		// This code is modeled after that in YapDatabaseViewTransaction.
		
		id metadata = nil;
		NSString *group = nil;
		
		if (searchResultsView->groupingBlockType == YapDatabaseViewBlockTypeWithKey ||
			searchResultsView->groupingBlockType == YapDatabaseViewBlockTypeWithMetadata)
		{
			// Grouping is based on the key or metadata.
			// Neither have changed, and thus the group hasn't changed.
			
			NSString *pageKey = [self pageKeyForRowid:rowid];
			group = [self groupForPageKey:pageKey];
			
			if (group == nil)
			{
				// Nothing to do.
				// It wasn't previously in the view, and still isn't in the view.
			}
			else if (searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithKey ||
			         searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithMetadata)
			{
				// Nothing has moved because the group hasn't changed and
				// nothing has changed that relates to sorting.
				
				int flags = YapDatabaseViewChangedObject;
				NSUInteger existingIndex = [self indexForRowid:rowid inGroup:group withPageKey:pageKey];
				
				[viewConnection->changes addObject:
				  [YapDatabaseViewRowChange updateKey:collectionKey changes:flags inGroup:group atIndex:existingIndex]];
			}
			else
			{
				// Sorting is based on the object, which has changed.
				// So the sort order may possibly have changed.
				
				// From previous if statement (above) we know:
				// sortingBlockType is object or row (object+metadata)
				
				if (searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithRow)
				{
					// Need the metadata for the sorting block
					metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
				}
				
				int flags = YapDatabaseViewChangedObject;
				
				[self insertRowid:rowid
					collectionKey:collectionKey
						   object:object
						 metadata:metadata
						  inGroup:group withChanges:flags isNew:NO];
			}
		}
		else
		{
			// Grouping is based on object or row (object+metadata).
			// Invoke groupingBlock to see what the new group is.
			
			__unsafe_unretained NSString *collection = collectionKey.collection;
			__unsafe_unretained NSString *key = collectionKey.key;
			
			NSSet *allowedCollections = searchResultsView->options.allowedCollections;
			
			if (!allowedCollections || [allowedCollections containsObject:collection])
			{
				if (searchResultsView->groupingBlockType == YapDatabaseViewBlockTypeWithObject)
				{
					__unsafe_unretained YapDatabaseViewGroupingWithObjectBlock groupingBlock =
			          (YapDatabaseViewGroupingWithObjectBlock)searchResultsView->groupingBlock;
					
					group = groupingBlock(collection, key, object);
				}
				else
				{
					__unsafe_unretained YapDatabaseViewGroupingWithRowBlock groupingBlock =
			          (YapDatabaseViewGroupingWithRowBlock)searchResultsView->groupingBlock;
					
					metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
					group = groupingBlock(collection, key, object, metadata);
				}
			}
			
			if (group == nil)
			{
				// The key is not included in the view.
				// Remove key from view (if needed).
				
				[self removeRowid:rowid collectionKey:collectionKey];
			}
			else
			{
				if (searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithKey ||
				    searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithMetadata)
				{
					// Sorting is based on the key or metadata, neither of which has changed.
					// So if the group hasn't changed, then the sort order hasn't changed.
					
					NSString *existingPageKey = [self pageKeyForRowid:rowid];
					NSString *existingGroup = [self groupForPageKey:existingPageKey];
					
					if ([group isEqualToString:existingGroup])
					{
						// Nothing left to do.
						// The group didn't change, and the sort order cannot change (because the object didn't change).
						
						int flags = YapDatabaseViewChangedObject;
						NSUInteger existingIndex = [self indexForRowid:rowid inGroup:group withPageKey:existingPageKey];
						
						[viewConnection->changes addObject:
						  [YapDatabaseViewRowChange updateKey:collectionKey
						                              changes:flags
						                              inGroup:group
						                              atIndex:existingIndex]];
						
						lastHandledGroup = group;
						return;
					}
				}
				
				if (metadata == nil && (searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithRow ||
				                        searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithMetadata))
				{
					// Need the metadata for the sorting block
					metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
				}
				
				int flags = YapDatabaseViewChangedObject;
				
				[self insertRowid:rowid
				    collectionKey:collectionKey
				           object:object
				         metadata:metadata
				          inGroup:group withChanges:flags isNew:NO];
			}
		}
		
		lastHandledGroup = group;
	}
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleReplaceMetadata:(id)metadata forCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	  (YapDatabaseSearchResultsView *)viewConnection->view;
	
	if (searchResultsView->parentViewName)
	{
		// Implementation Note:
		// This code is modeled after that in YapDatabaseFilteredViewTransaction.
		
		BOOL groupMayHaveChanged = searchResultsView->groupingBlockType == YapDatabaseViewBlockTypeWithRow ||
		                           searchResultsView->groupingBlockType == YapDatabaseViewBlockTypeWithMetadata;
		
		BOOL sortMayHaveChanged = searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithRow ||
		                          searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithMetadata;
		
		// Instead of going to the groupingBlock,
		// just ask the parentViewTransaction what the last group was.
		
		__unsafe_unretained YapDatabaseViewTransaction *parentViewTransaction =
		  [databaseTransaction ext:searchResultsView->parentViewName];
		
		NSString *group = parentViewTransaction->lastHandledGroup;
		
		if (group == nil)
		{
			// Not included in parentView.
			
			if (groupMayHaveChanged)
			{
				// Remove key from view (if needed).
				// This was an update operation, so the key may have previously been in the view.
				
				[self removeRowid:rowid collectionKey:collectionKey];
			}
			else
			{
				// The group hasn't changed.
				// Thus it wasn't previously in view, and still isn't in the view.
			}
			
			lastHandledGroup = nil;
			return;
		}
		
		__unsafe_unretained YapDatabaseFullTextSearchTransaction *ftsTransaction =
		  [databaseTransaction ext:searchResultsView->fullTextSearchName];
		
		__unsafe_unretained YapDatabaseFullTextSearch *fts =
		  (YapDatabaseFullTextSearch *)[[ftsTransaction extensionConnection] extension];
		
		BOOL searchMayHaveChanged = fts->blockType == YapDatabaseFullTextSearchBlockTypeWithRow ||
		                            fts->blockType == YapDatabaseFullTextSearchBlockTypeWithObject;
		
		if (!groupMayHaveChanged && !sortMayHaveChanged && !searchMayHaveChanged)
		{
			// Nothing has changed that could possibly affect the view.
			// Just note the touch.
			
			int flags = YapDatabaseViewChangedMetadata;
			
			NSString *pageKey = [self pageKeyForRowid:rowid];
			NSUInteger existingIndex = [self indexForRowid:rowid inGroup:group withPageKey:pageKey];
			
			[viewConnection->changes addObject:
			  [YapDatabaseViewRowChange updateKey:collectionKey changes:flags inGroup:group atIndex:existingIndex]];
			
			lastHandledGroup = group;
			return;
		}
		
		BOOL matchesQuery = [ftsTransaction rowid:rowid matches:[self query]];
		
		if (matchesQuery)
		{
			// Add key to view (or update position).
			// This was an update operation, so the key may have previously been in the view.
			
			int flags = (YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata);
			
			id object= nil;
			if (searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithRow ||
			    searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithObject)
			{
				object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
			}
			
			[self insertRowid:rowid
			    collectionKey:collectionKey
			           object:object
			         metadata:metadata
			          inGroup:group
			      withChanges:flags
			            isNew:NO];
			
			lastHandledGroup = group;
		}
		else
		{
			// Filtered from this view.
			// Remove key from view (if needed).
			// This was an update operation, so the key may have previously been in the view.
			
			[self removeRowid:rowid collectionKey:collectionKey];
			lastHandledGroup = nil;
		}
	}
	else
	{
		// Implementation Note:
		// This code is modeled after that in YapDatabaseViewTransaction.
		
		id object = nil;
		NSString *group = nil;
		
		if (searchResultsView->groupingBlockType == YapDatabaseViewBlockTypeWithKey ||
		    searchResultsView->groupingBlockType == YapDatabaseViewBlockTypeWithObject)
		{
			// Grouping is based on the key or object.
			// Neither have changed, and thus the group hasn't changed.
			
			NSString *pageKey = [self pageKeyForRowid:rowid];
			group = [self groupForPageKey:pageKey];
			
			if (group == nil)
			{
				// Nothing to do.
				// The key wasn't previously in the view, and still isn't in the view.
			}
			else if (searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithKey ||
			         searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithObject)
			{
				// Nothing has moved because the group hasn't changed and
				// nothing has changed that relates to sorting.
				
				int flags = YapDatabaseViewChangedMetadata;
				NSUInteger existingIndex = [self indexForRowid:rowid inGroup:group withPageKey:pageKey];
				
				[viewConnection->changes addObject:
				  [YapDatabaseViewRowChange updateKey:collectionKey changes:flags inGroup:group atIndex:existingIndex]];
			}
			else
			{
				// Sorting is based on the metadata, which has changed.
				// So the sort order may possibly have changed.
				
				// From previous if statement (above) we know:
				// sortingBlockType is metadata or objectAndMetadata
				
				if (searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithRow)
				{
					// Need the object for the sorting block
					object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
				}
				
				int flags = YapDatabaseViewChangedMetadata;
				
				[self insertRowid:rowid
				    collectionKey:collectionKey
				           object:object
				         metadata:metadata
				          inGroup:group withChanges:flags isNew:NO];
			}
		}
		else
		{
			// Grouping is based on metadata or objectAndMetadata.
			// Invoke groupingBlock to see what the new group is.
			
			__unsafe_unretained NSString *collection = collectionKey.collection;
			__unsafe_unretained NSString *key = collectionKey.key;
			
			NSSet *allowedCollections = searchResultsView->options.allowedCollections;
			
			if (!allowedCollections || [allowedCollections containsObject:collection])
			{
				if (searchResultsView->groupingBlockType == YapDatabaseViewBlockTypeWithMetadata)
				{
					__unsafe_unretained YapDatabaseViewGroupingWithMetadataBlock groupingBlock =
			          (YapDatabaseViewGroupingWithMetadataBlock)searchResultsView->groupingBlock;
					
					group = groupingBlock(collection, key, metadata);
				}
				else
				{
					__unsafe_unretained YapDatabaseViewGroupingWithRowBlock groupingBlock =
			          (YapDatabaseViewGroupingWithRowBlock)searchResultsView->groupingBlock;
					
					object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
					group = groupingBlock(collection, key, object, metadata);
				}
			}
			
			if (group == nil)
			{
				// The key is not included in the view.
				// Remove key from view (if needed).
				
				[self removeRowid:rowid collectionKey:collectionKey];
			}
			else
			{
				if (searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithKey ||
				    searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithObject)
				{
					// Sorting is based on the key or object, neither of which has changed.
					// So if the group hasn't changed, then the sort order hasn't changed.
					
					NSString *existingPageKey = [self pageKeyForRowid:rowid];
					NSString *existingGroup = [self groupForPageKey:existingPageKey];
					
					if ([group isEqualToString:existingGroup])
					{
						// Nothing left to do.
						// The group didn't change, and the sort order cannot change (because the object didn't change).
						
						int flags = YapDatabaseViewChangedMetadata;
						NSUInteger existingIndex = [self indexForRowid:rowid inGroup:group withPageKey:existingPageKey];
						
						[viewConnection->changes addObject:
						  [YapDatabaseViewRowChange updateKey:collectionKey
						                              changes:flags
						                              inGroup:group
						                              atIndex:existingIndex]];
						
						lastHandledGroup = group;
						return;
					}
				}
				
				if (object == nil && (searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithRow ||
				                      searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithObject))
				{
					// Need the object for the sorting block
					object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
				}
				
				int flags = YapDatabaseViewChangedMetadata;
				
				[self insertRowid:rowid
					collectionKey:collectionKey
						   object:object
						 metadata:metadata
						  inGroup:group withChanges:flags isNew:NO];
			}
		}
		
		lastHandledGroup = group;
	}
}

///
/// All other hook methods are handled by superclass (YapDatabaseViewTransaction).
///

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark YapDatabaseViewDependency Protocol
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method is invoked if our parentView repopulates.
 * For example:
 *
 * - The parentView is a YapDatabaseView, and the groupingBlock and/or sortingBlock was changed.
 * - The parentView is a YapDatabaseFilteredView, and the filterBlock was changed.
 * - The parentView of the parentView was changed...
 * 
 * When this happens, there has likely been a significant change in the content of the parentView,
 * and a full repopulate is required on our part.
**/
- (void)view:(NSString *)parentViewName didRepopulateWithFlags:(int)flags
{
	YDBLogAutoTrace();
	
	if (!databaseTransaction->isReadWriteTransaction)
	{
	//	YDBLogWarn(@"%@ - Method only allowed in readWrite transaction", THIS_METHOD);
		return;
	}
	
	// Todo...
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Searching
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)query
{
	__unsafe_unretained YapDatabaseSearchResultsViewConnection *searchResultsViewConnection =
	  (YapDatabaseSearchResultsViewConnection *)viewConnection;
	
	return searchResultsViewConnection->query;
}

/**
 * This method updates the view by using the updated ftsRowids set.
 * Only use this method if parentViewName is non-nil.
**/
- (void)updateViewFromParent
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	  (YapDatabaseSearchResultsView *)viewConnection->view;
	
	__unsafe_unretained YapDatabaseViewTransaction *parentViewTransaction =
	  (YapDatabaseViewTransaction *)[databaseTransaction ext:searchResultsView->parentViewName];
	
	for (NSString *group in [parentViewTransaction allGroups])
	{
		__block BOOL existing = NO;
		__block int64_t existingRowid = 0;
		
		existing = [self getRowid:&existingRowid atIndex:0 inGroup:group];
		
		__block NSUInteger index = 0;
		
		[parentViewTransaction enumerateRowidsInGroup:group
		                                   usingBlock:^(int64_t rowid, NSUInteger parentIndex, BOOL *stop)
		{
			if (ftsRowids->find(rowid) != ftsRowids->end())
			{
				if (existing && (existingRowid == rowid))
				{
					// The row was previously in the view (in old search results),
					// and is still in the view (in new search results).
					
					index++;
					existing = [self getRowid:&existingRowid atIndex:index inGroup:group];
				}
				else
				{
					// The row was not previously in the view (not in old search results),
					// but is now in the view (in new search results).
					
					YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:rowid];
					
					if (index == 0 && ([viewConnection->group_pagesMetadata_dict objectForKey:group] == nil))
						[self insertRowid:rowid collectionKey:ck inNewGroup:group];
					else
						[self insertRowid:rowid collectionKey:ck inGroup:group
						                                         atIndex:index withExistingPageKey:nil];
					index++;
				}
			}
			else
			{
				if (existing && (existingRowid == rowid))
				{
					// The row was previously in the view (in old search results),
					// but is no longer in the view (not in new search results).
					
					YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:rowid];
					
					[self removeRowid:rowid collectionKey:ck atIndex:index inGroup:group];
					existing = [self getRowid:&existingRowid atIndex:index inGroup:group];
				}
				else
				{
					// The row was not previously in the view (not in old search results),
					// and is still not in the view (not in new search results).
				}
			}
		}];
	}
}

/**
 * This method updates the view by using the updated ftsRowids set.
 * Only use this method if parentViewName is nil.
**/
- (void)updateViewUsingBlocks
{
	YDBLogAutoTrace();
	
	// Create a copy of the ftsRowids set.
	// As we enumerate the existing rowids in our view, we're going to
	std::unordered_set<int64_t> *ftsRowidsLeft = new std::unordered_set<int64_t>(*ftsRowids);
	
	for (NSString *group in [self allGroups])
	{
		__block NSUInteger groupCount = [self numberOfKeysInGroup:group];
		__block NSRange range = NSMakeRange(0, groupCount);
		__block BOOL done;
		do
		{
			done = YES;
			
			[self enumerateRowidsInGroup:group
			                 withOptions:0
			                       range:range
			                  usingBlock:^(int64_t rowid, NSUInteger index, BOOL *stop)
			{
				if (ftsRowidsLeft->find(rowid) != ftsRowidsLeft->end())
				{
					// The row was previously in the view (in old search results),
					// and is still in the view (in new search results).
					
					// Removes from ftsRowidsLeft set
					ftsRowidsLeft->erase(rowid);
				}
				else
				{
					// The row was previously in the view (in old search results),
					// but is no longer in the view (not in new search results).
					
					YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:rowid];
					
					[self removeRowid:rowid collectionKey:ck atIndex:index inGroup:group];
					
					groupCount--;
					
					range.location = index;
					range.length = groupCount - index;
					
					if (range.length > 0){
						done = NO;
					}
					
					*stop = YES;
				}
			}];
			
		} while (!done);
		
	} // end for (NSString *group in [self allGroups])
	
	
	// Now enumerate any items in ftsRowidsLeft
	
	std::unordered_set<int64_t>::iterator iterator = ftsRowidsLeft->begin();
	std::unordered_set<int64_t>::iterator end;
	
	__unsafe_unretained YapDatabaseView *view = viewConnection->view;
	
	while (iterator != end)
	{
		int64_t rowid = *iterator;
		
		YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:rowid];
		
		id object = nil;
		id metadata = nil;
		
		// Invoke the grouping block to find out if the object should be included in the view.
		
		NSString *group = nil;
		NSSet *allowedCollections = view->options.allowedCollections;
		
		if (!allowedCollections || [allowedCollections containsObject:ck.collection])
		{
			if (view->groupingBlockType == YapDatabaseViewBlockTypeWithKey)
			{
				__unsafe_unretained YapDatabaseViewGroupingWithKeyBlock groupingBlock =
			      (YapDatabaseViewGroupingWithKeyBlock)view->groupingBlock;
				
				group = groupingBlock(ck.collection, ck.key);
			}
			else if (view->groupingBlockType == YapDatabaseViewBlockTypeWithObject)
			{
				__unsafe_unretained YapDatabaseViewGroupingWithObjectBlock groupingBlock =
			      (YapDatabaseViewGroupingWithObjectBlock)view->groupingBlock;
				
				object = [databaseTransaction objectForCollectionKey:ck withRowid:rowid];
				
				group = groupingBlock(ck.collection, ck.key, object);
			}
			else if (view->groupingBlockType == YapDatabaseViewBlockTypeWithMetadata)
			{
				__unsafe_unretained YapDatabaseViewGroupingWithMetadataBlock groupingBlock =
			      (YapDatabaseViewGroupingWithMetadataBlock)view->groupingBlock;
				
				metadata = [databaseTransaction metadataForCollectionKey:ck withRowid:rowid];
				
				group = groupingBlock(ck.collection, ck.key, metadata);
			}
			else
			{
				__unsafe_unretained YapDatabaseViewGroupingWithRowBlock groupingBlock =
			      (YapDatabaseViewGroupingWithRowBlock)view->groupingBlock;
				
				[databaseTransaction getObject:&object metadata:&metadata forCollectionKey:ck withRowid:rowid];
				
				group = groupingBlock(ck.collection, ck.key, object, metadata);
			}
		}
		
		if (group)
		{
			// Add to view.
			
			int flags = (YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata);
			
			if (view->sortingBlockType == YapDatabaseViewBlockTypeWithObject)
			{
				if (object == nil)
					object = [databaseTransaction objectForCollectionKey:ck withRowid:rowid];
			}
			else if (view->sortingBlockType == YapDatabaseViewBlockTypeWithMetadata)
			{
				if (metadata == nil)
					metadata = [databaseTransaction metadataForCollectionKey:ck withRowid:rowid];
			}
			else if (view->sortingBlockType == YapDatabaseViewBlockTypeWithRow)
			{
				if (object == nil) {
					if (metadata == nil)
						[databaseTransaction getObject:&object metadata:&metadata forCollectionKey:ck withRowid:rowid];
					else
						object = [databaseTransaction objectForCollectionKey:ck withRowid:rowid];
				}
				else if (metadata == nil) {
					metadata = [databaseTransaction metadataForCollectionKey:ck withRowid:rowid];
				}
			}
			
			[self insertRowid:rowid
			    collectionKey:ck
			           object:object
			         metadata:metadata
			          inGroup:group withChanges:flags isNew:YES];
		}
		
		iterator++;
	}
	
	// Dealloc the temporary c++ set
	if (ftsRowidsLeft) {
		delete ftsRowidsLeft;
	}
}

- (void)performSearchFor:(NSString *)query
{
	YDBLogAutoTrace();
	
	if (!databaseTransaction->isReadWriteTransaction)
	{
		YDBLogWarn(@"%@ - Method only allowed in readWrite transaction", THIS_METHOD);
		return;
	}
	
	ftsRowids->clear();
	
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	  (YapDatabaseSearchResultsView *)viewConnection->view;
	
	__unsafe_unretained YapDatabaseFullTextSearchTransaction *ftsTransaction =
	  (YapDatabaseFullTextSearchTransaction *)[databaseTransaction ext:searchResultsView->fullTextSearchName];
	
	[ftsTransaction enumerateRowidsMatching:query usingBlock:^(int64_t rowid, BOOL *stop) {
		
		ftsRowids->insert(rowid);
	}];
	
	if (searchResultsView->parentViewName)
		[self updateViewFromParent];
	else
		[self updateViewUsingBlocks];
	
	__unsafe_unretained YapDatabaseSearchResultsViewConnection *searchResultsViewConnection =
	  (YapDatabaseSearchResultsViewConnection *)viewConnection;
	
	searchResultsViewConnection->query = [query copy];
}

@end
