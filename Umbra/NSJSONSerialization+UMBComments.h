//
//  NSJSONSerialization+UMBComments.h
//  ABCodeEditor
//
//  Created by Alexander Blach on 22.07.14.
//  Copyright (c) 2014 Alexander Blach. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSJSONSerialization (UMBComments)

+ (NSData *)umb_dataByStrippingJSONCommentsAndWhiteSpaceOfUTF8Data:(NSData *)data skipBytes:(NSUInteger)bytesToSkip;

// preferred method, since it doesn't need to convert an NSString if the data is  encoded with UTF-8
+ (id)umb_JSONObjectWithCommentedData:(NSData *)data options:(NSJSONReadingOptions)opt error:(NSError **)error;

+ (id)umb_JSONObjectWithCommentedContentsOfURL:(NSURL *)url options:(NSJSONReadingOptions)opt error:(NSError **)error;

+ (id)umb_JSONObjectWithCommentedContentsOfFile:(NSString *)path
                                        options:(NSJSONReadingOptions)opt
                                          error:(NSError **)error;

+ (id)umb_JSONObjectWithCommentedString:(NSString *)string options:(NSJSONReadingOptions)opt error:(NSError **)error;

// convenience method if you need an NSString instead of NSData
+ (NSString *)umb_stringWithJSONObject:(id)obj options:(NSJSONWritingOptions)opt error:(NSError **)error;

@end
