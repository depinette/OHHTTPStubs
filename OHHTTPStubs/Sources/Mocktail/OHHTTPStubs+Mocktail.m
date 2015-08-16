//
//  OHHTTPStubs+Mocktail.m
//  CardCompanion
//
//  Created by Wang, Sunny on 7/30/15.
//

#import "OHHTTPStubs+Mocktail.h"

NSString* const MocktailErrorDomain = @"Mocktail";

@implementation OHHTTPStubs (Mocktail)


+(NSArray *)stubRequestsUsingMocktailsAtPath:(NSString *)path inBundle:(nullable NSBundle*)bundleOrNil error:(NSError **)error
{
    NSURL *dirURL = [bundleOrNil?:[NSBundle bundleForClass:self.class] URLForResource:path withExtension:nil];
    if (!dirURL)
    {
        if (error)
        {
            *error = [NSError errorWithDomain:MocktailErrorDomain code:OHHTTPStubsMocktailErrorPathDoesNotExist userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Path '%@' does not exist.", path]}];
        }
        return nil;
    }
    
    // Make sure path points to a directory
    NSNumber *isDirectory;
    BOOL success = [dirURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
    BOOL isDir = (success && [isDirectory boolValue]);
    
    if (!isDir)
    {
        if (error)
        {
            *error = [NSError errorWithDomain:MocktailErrorDomain code:OHHTTPStubsMocktailErrorPathIsNotFolder userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Path '%@' is not a folder.", path]}];
        }
        return nil;
    }
    
    // Read the content of the directory
    NSError *bError = nil;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *fileURLs = [fileManager contentsOfDirectoryAtURL:dirURL includingPropertiesForKeys:nil options:0 error:&bError];

    if (bError)
    {
        if (error)
        {
            *error = [NSError errorWithDomain:MocktailErrorDomain code:OHHTTPStubsMocktailErrorPathFailedToRead userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Error reading path '%@'.", dirURL.absoluteString]}];
        }
        return nil;
    }
    
    //stub the Mocktail-formatted requests
    NSMutableArray *descriptorArray = [[NSMutableArray alloc] initWithCapacity:fileURLs.count];
    for (NSURL *fileURL in fileURLs)
    {
        if (![fileURL.absoluteString hasSuffix:@".tail"])
        {
            continue;
        }
        id<OHHTTPStubsDescriptor> descriptor = [[self class] stubRequestsUsingMocktail:fileURL error: &bError];
        if (descriptor && !bError)
        {
            [descriptorArray addObject:descriptor];
        }
    }
    
    return descriptorArray;
}

+(id<OHHTTPStubsDescriptor>)stubRequestsUsingMocktailNamed:(NSString *)fileName inBundle:(nullable NSBundle*)bundleOrNil error:(NSError **)error
{
    NSURL *responseURL = [bundleOrNil?:[NSBundle bundleForClass:self.class] URLForResource:fileName withExtension:@"tail"];
    
    if (!responseURL)
    {
        if (error)
        {
            *error = [NSError errorWithDomain:MocktailErrorDomain code:OHHTTPStubsMocktailErrorPathDoesNotExist userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"File '%@' does not exist.", fileName]}];
        }
        return nil;
    }
    else
    {
        return [[self class] stubRequestsUsingMocktail:responseURL error:error];
    }
}

+(id<OHHTTPStubsDescriptor>)stubRequestsUsingMocktail:(NSURL *)fileURL error:(NSError **)error
{
    NSError *bError = nil;
    NSStringEncoding originalEncoding;
    NSString *contentsOfFile = [NSString stringWithContentsOfURL:fileURL usedEncoding:&originalEncoding error:&bError];
    
    if (!contentsOfFile || bError)
    {
        if (error)
        {
            *error = [NSError errorWithDomain:MocktailErrorDomain code:OHHTTPStubsMocktailErrorPathFailedToRead userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"File '%@' does not read.", fileURL.absoluteString]}];
        }
        return nil;
    }
    
    NSScanner *scanner = [NSScanner scannerWithString:contentsOfFile];
    NSString *headerMatter = nil;
    [scanner scanUpToString:@"\n\n" intoString:&headerMatter];
    NSArray *lines = [headerMatter componentsSeparatedByString:@"\n"];
    if (lines.count < 4)
    {
        if (error)
        {
            *error = [NSError errorWithDomain:MocktailErrorDomain code:OHHTTPStubsMocktailErrorInvalidFileFormat userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"File '%@' has invalid amount of lines:%u.", fileURL.absoluteString, (unsigned)lines.count]}];
        }
        return nil;
    }
    
    /* Handle Mocktail format, adapted from Mocktail implementation
       For more details on the file format, check out: https://github.com/square/objc-Mocktail */
    NSRegularExpression *methodRegex = [NSRegularExpression regularExpressionWithPattern:lines[0] options:NSRegularExpressionCaseInsensitive error:&bError];
    
    if (bError)
    {
        if (error)
        {
            *error = [NSError errorWithDomain:MocktailErrorDomain code:OHHTTPStubsMocktailErrorInvalidFileFormat userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"File '%@' has invalid method regular expression pattern: %@.", fileURL.absoluteString,  lines[0]]}];
        }
        return nil;
    }
    
    NSRegularExpression *absoluteURLRegex = [NSRegularExpression regularExpressionWithPattern:lines[1] options:NSRegularExpressionCaseInsensitive error:&bError];
    
    if (bError)
    {
        if (error)
        {
            *error = [NSError errorWithDomain:MocktailErrorDomain code:OHHTTPStubsMocktailErrorInvalidFileFormat userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"File '%@' has invalid URL regular expression pattern: %@.", fileURL.absoluteString,  lines[1]]}];
        }
        return nil;
    }
    
    NSInteger statusCode = [lines[2] integerValue];
    
    NSMutableDictionary *headers = @{@"Content-Type":lines[3]}.mutableCopy;
    
    // From line 5 to '\n\n', expect HTTP response headers.
    NSRegularExpression *headerPattern = [NSRegularExpression regularExpressionWithPattern:@"^([^:]+):\\s+(.*)" options:0 error:&bError];
    if (bError)
    {
        if (error)
        {
            *error = [NSError errorWithDomain:MocktailErrorDomain code:OHHTTPStubsMocktailErrorInternalError userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Internal error while stubbing file '%@'.", fileURL.absoluteString]}];
        }
        return nil;
    }
    
    for (NSUInteger line = 4; line < lines.count; line ++) {
        NSString *headerLine = lines[line];
        NSTextCheckingResult *match = [headerPattern firstMatchInString:headerLine options:0 range:NSMakeRange(0, headerLine.length)];
        
        if (match)
        {
            NSString *key = [headerLine substringWithRange:[match rangeAtIndex:1]];
            NSString *value = [headerLine substringWithRange:[match rangeAtIndex:2]];
            headers[key] = value;
        }
        else
        {
            if (error)
            {
                *error = [NSError errorWithDomain:MocktailErrorDomain code:OHHTTPStubsMocktailErrorInvalidFileHeader userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"File '%@' has invalid header: %@.", fileURL.absoluteString, headerLine]}];
            }
            return nil;
        }
    }
    
    // Handle binary which is base64 encoded
    unsigned long long bodyOffset = [headerMatter dataUsingEncoding:NSUTF8StringEncoding].length + 2;
    
    return [OHHTTPStubs stubRequestsPassingTest:^BOOL(NSURLRequest *request) {
        NSString *absoluteURL = (request.URL).absoluteString;
        NSString *method = request.HTTPMethod;
        
        if ([absoluteURLRegex numberOfMatchesInString:absoluteURL options:0 range:NSMakeRange(0, absoluteURL.length)] > 0)
        {
            if ([methodRegex numberOfMatchesInString:method options:0 range:NSMakeRange(0, method.length)] > 0)
            {
                return YES;
            }
        }
        
        return NO;
    } withStubResponse:^OHHTTPStubsResponse*(NSURLRequest *request) {
        if([headers[@"Content-Type"] hasSuffix:@";base64"])
        {
            NSString *type = headers[@"Content-Type"];
            NSString *newType = [type substringWithRange:NSMakeRange(0, type.length - 7)];
            headers[@"Content-Type"] = newType;
            
            NSData *body = [NSData dataWithContentsOfURL:fileURL];
            body = [body subdataWithRange:NSMakeRange(bodyOffset, body.length - bodyOffset)];
            body = [[NSData alloc] initWithBase64EncodedData:body options:NSDataBase64DecodingIgnoreUnknownCharacters];
            
            OHHTTPStubsResponse *response = [OHHTTPStubsResponse responseWithData:body statusCode:(int)statusCode headers:headers];
            return response;
        }
        else
        {
            OHHTTPStubsResponse *response = [OHHTTPStubsResponse responseWithFileAtPath:fileURL.path
                                                                             statusCode:(int)statusCode headers:headers];
            [response.inputStream setProperty:@(bodyOffset) forKey:NSStreamFileCurrentOffsetKey];
            return response;
        }
    }];
}

@end
