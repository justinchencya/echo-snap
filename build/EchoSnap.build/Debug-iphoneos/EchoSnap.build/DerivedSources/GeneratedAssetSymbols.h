#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The "button-accept" asset catalog image resource.
static NSString * const ACImageNameButtonAccept AC_SWIFT_PRIVATE = @"button-accept";

/// The "button-close" asset catalog image resource.
static NSString * const ACImageNameButtonClose AC_SWIFT_PRIVATE = @"button-close";

/// The "button-reset" asset catalog image resource.
static NSString * const ACImageNameButtonReset AC_SWIFT_PRIVATE = @"button-reset";

#undef AC_SWIFT_PRIVATE
