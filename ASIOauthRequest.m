//
//  ASIOauthRequest.m
//  ASIOauthTest
//
//  Created by Michael Dales on 22/04/2010.
//  Copyright 2010 Michael Dales. All rights reserved.
//

#import "ASIOauthRequest.h"

#import <openssl/hmac.h>


@implementation ASIOauthRequest


#pragma mark -
#pragma mark Constructor/destructor

- (id)initWithURL: (NSURL*)desturl forConsumerWithKey: (NSString*)key andSecret: (NSString*)secret
{
	if ((self = [super initWithURL: desturl]) != nil)
	{
		self.consumerKey = key;
		self.consumerSecret = secret;
		self.signatureMethod = ASIPlaintextOAuthSignatureMethod;
	}
	
	return self;
}

- (void)setTokenWithKey: (NSString*)key andSecret: (NSString*)secret
{
	// properties for these values are read only, to stop people forgetting to set one or the other, so 
	// remember to retain here
	[tokenKey release];
	[tokenSecret release];
	
	tokenKey = key;
	tokenSecret = secret;
	
	[tokenKey retain];
	[tokenSecret retain];
}

- (void)dealloc
{
	[consumerKey release];
	[consumerSecret release];
	[tokenKey release];
	[tokenSecret release];
	[super dealloc];
}


#pragma mark -
#pragma mark OAuth utility methods

- (NSString*)createNonce
{
	NSString *res = @"";
	
	srandom(time(NULL));
	for (int i = 0; i < 10; i++)
	{
		res = [NSString stringWithFormat: @"%@%02x", res, random() % 16];
	}
	
	return res;
}


- (NSString*)rawHMAC_SHA1EncodeString: (NSString*)plaintext usingKey: (NSString*)keytext
{	
	size_t keyLen, msgLen; 
	unsigned char *key; 
	const unsigned char* msg; 
	unsigned int macLen;
	unsigned char *result;
	
	keyLen = [keytext length];
	msgLen = [plaintext length];
	key = (unsigned char*)[keytext cStringUsingEncoding: NSUTF8StringEncoding];
	msg = (unsigned char*)[plaintext cStringUsingEncoding: NSUTF8StringEncoding];
	
	result = HMAC(EVP_sha1(), key, keyLen, msg, msgLen, NULL, &macLen); 
	
	// finally we need to base64 encode the result
    BIO *context = BIO_new(BIO_s_mem());
	
    BIO *command = BIO_new(BIO_f_base64());
    context = BIO_push(command, context);
	
    BIO_write(context, result, macLen);
    BIO_flush(context);
	
    // Get the data into a string, but drop the last char (\n)
    char *outputBuffer;
    long outputLength = BIO_get_mem_data(context, &outputBuffer);
    NSString *encodedString = [NSString
							   stringWithCString:outputBuffer
							   length:outputLength - 1];
	
    BIO_free_all(context);
	
	return encodedString;
}


- (NSString*)generateHMAC_SHA1SignatureString
{
	
	NSString *portString;
	// we need to normalise the URL. We only include the port if it's non-standard.
	if ((([[url scheme] compare: @"http"] == NSOrderedSame) && ([[url port] integerValue] == 80)) ||
		(([[url scheme] compare: @"https"] == NSOrderedSame) && ([[url port] integerValue] == 443)))
	{
		portString = @"";
	}
	else
	{
		portString = [NSString stringWithFormat: @":%@", [url port]];
	}
	
	// NSURL path strips the trailing / of the URL. Hence this stupid bit of code
	NSString *urlstr = [url absoluteString];
	NSArray *parts = [urlstr componentsSeparatedByString: @"?"];
	urlstr = [parts objectAtIndex: 0];
	unichar lastchar = [urlstr characterAtIndex: urlstr.length - 1];
	NSString *trailingSlash = lastchar == '/' ? @"/" : @"";
	
	NSString *normalised_url = [NSString stringWithFormat: @"%@://%@%@%@%@", [url scheme], [url host], 
								portString, [url path], trailingSlash];
	
	NSDictionary *params = postData;
	NSMutableArray *keys = [NSMutableArray arrayWithArray: [params allKeys]];
	
	NSLog(@"keys before sorting: %@", keys);
	[keys sortUsingSelector: @selector(compare:)];
	NSLog(@"keys post sorting: %@", keys);
	
	// Build up the param string, before adding it, as it needs to be escaped
	NSString *paramstr = @"";
	for (NSString *key in keys)
	{
		paramstr = [NSString stringWithFormat: @"%@%@%@=%@", paramstr, 
			   paramstr.length == 0? @"" : @"&",
			   [self encodeURL: key], 
			   [self encodeURL: [postData objectForKey: key]]];
	}
	
	// first add normalized http method, then the normalised url
	NSString *raw = [NSString stringWithFormat: @"%@&%@&%@", 
					 [self encodeURL: requestMethod], 
					 [self encodeURL: normalised_url],
					 [self encodeURL: paramstr]];
	
	NSString *key = [NSString stringWithFormat: @"%@&%@", consumerSecret, tokenSecret != nil ? tokenSecret : @""];
	
	NSLog(@"raw: %@", raw);
	NSLog(@"key: %@", key);
	
	// we now have the raw text, and the key, so do the signing
	return [self rawHMAC_SHA1EncodeString: raw
								 usingKey: key];

}


- (void)generateOAuthSignature
{
	switch (signatureMethod)
	{
		case ASIPlaintextOAuthSignatureMethod:
		{			
			[self setPostValue: @"PLAINTEXT"
						forKey: @"oauth_signature_method"];
			[self setPostValue: [NSString stringWithFormat: @"%@&%@", consumerSecret, tokenSecret != nil ? tokenSecret : @""]
						forKey: @"oauth_signature"];
			break;
		}
			
		case ASIHMAC_SHA1OAuthSignatureMethod:
		{
			[self setPostValue: @"HMAC-SHA1"
						forKey: @"oauth_signature_method"];
			[self setPostValue: [self generateHMAC_SHA1SignatureString]
						forKey: @"oauth_signature"];
			break;
		}
	}
}



#pragma mark -
#pragma mark Override ASI methods

- (void)buildPostBody
{
	// we copy these checks from super, as they kinda need to be done before we build up our OAuth stuff
	if ([self haveBuiltPostBody]) 
	{
		return;
	}
	if (![[self requestMethod] isEqualToString:@"PUT"]) {
		[self setRequestMethod:@"POST"];
	}
	

	// before we call super, build the OAuth headers
	[self setPostValue: consumerKey
				forKey: @"oauth_consumer_key"];
	if (tokenKey != nil)
		[self setPostValue: tokenKey
					forKey: @"oauth_token"];
	
	[self setPostValue: [NSString stringWithFormat: @"%lld", (int)[[NSDate date] timeIntervalSince1970]]
				forKey: @"oauth_timestamp"];
	[self setPostValue: @"1.0"
				forKey: @"oauth_version"];
	[self setPostValue: [self createNonce]
				forKey: @"oauth_nonce"];
	
	// now we've built the request, sign it
	[self generateOAuthSignature];
	
	// done, now return to our regular scheduled programming
	[super buildPostBody];
}



#pragma mark -
#pragma mark Properties

@synthesize consumerKey;
@synthesize consumerSecret;
@synthesize tokenKey;
@synthesize tokenSecret;
@synthesize signatureMethod;

@end