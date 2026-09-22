#import <Cocoa/Cocoa.h>
#import <Security/Security.h>
#import <WebKit/WebKit.h>
#include <moonbit.h>
#include <string.h>

static NSString *str(const unsigned char *value) {
  return [[NSString alloc] initWithBytes:value length:Moonbit_array_length(value) encoding:NSUTF8StringEncoding];
}
static moonbit_bytes_t bytes(NSData *data) {
  moonbit_bytes_t result = moonbit_make_bytes((int32_t)data.length, 0);
  if (data.length) memcpy(result, data.bytes, data.length);
  return result;
}
static NSMutableDictionary *query(NSString *service, NSString *account) {
  return [@{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService: [@"dev.vectie.lunanexa.operator:" stringByAppendingString:service],
            (__bridge id)kSecAttrAccount: account} mutableCopy];
}
MOONBIT_FFI_EXPORT moonbit_bytes_t lnx_resource_manifest(void) {
  @autoreleasepool {
    NSString *path = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"lepusa/runtime.json"];
    return bytes([path dataUsingEncoding:NSUTF8StringEncoding]);
  }
}
static void app(void) {
  static BOOL launched = NO;
  [NSApplication sharedApplication];
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
  if (!launched) {
    [NSApp finishLaunching];
    launched = YES;
  }
  [NSApp activateIgnoringOtherApps:YES];
}
static int save(NSString *service, NSString *account, NSData *data) {
  NSMutableDictionary *q = query(service, account);
  OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)q,
    (__bridge CFDictionaryRef)@{(__bridge id)kSecValueData: data});
  if (status == errSecItemNotFound) {
    q[(__bridge id)kSecValueData] = data;
    q[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly;
    status = SecItemAdd((__bridge CFDictionaryRef)q, NULL);
  }
  return status == errSecSuccess ? 0 : 1;
}
MOONBIT_FFI_EXPORT int32_t lnx_configure(const unsigned char *service, const unsigned char *account) {
  @autoreleasepool {
    app();
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"保存 Operator 登录信息";
    alert.informativeText = [NSString stringWithFormat:@"服务器：%@\n用户名：%@\n密码仅保存在此 Mac 的钥匙串中。", str(service), str(account)];
    NSSecureTextField *field = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0,0,360,28)];
    field.placeholderString = @"平台登录密码";
    alert.accessoryView = field;
    [alert addButtonWithTitle:@"保存"];
    [alert addButtonWithTitle:@"取消"];
    [alert.window setInitialFirstResponder:field];
    if ([alert runModal] != NSAlertFirstButtonReturn || !field.stringValue.length) return 1;
    NSData *data = [field.stringValue dataUsingEncoding:NSUTF8StringEncoding];
    field.stringValue = @"";
    return save(str(service), str(account), data);
  }
}
MOONBIT_FFI_EXPORT moonbit_bytes_t lnx_password(const unsigned char *service, const unsigned char *account) {
  @autoreleasepool {
    NSMutableDictionary *q = query(str(service), str(account));
    q[(__bridge id)kSecReturnData] = @YES;
    q[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)q, &result);
    if (status == errSecSuccess) return bytes(CFBridgingRelease(result));
    return bytes([NSData data]);
  }
}
MOONBIT_FFI_EXPORT int32_t lnx_retry_dialog(const unsigned char *message) {
  @autoreleasepool {
    app();
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"LunaNexa Operator";
    alert.informativeText = str(message);
    [alert addButtonWithTitle:@"重试"];
    [alert addButtonWithTitle:@"退出"];
    [alert addButtonWithTitle:@"更新密码"];
    NSModalResponse result = [alert runModal];
    return result == NSAlertFirstButtonReturn ? 1 : result == NSAlertThirdButtonReturn ? 2 : 0;
  }
}
MOONBIT_FFI_EXPORT int32_t lnx_install_cookie(const unsigned char *value) {
  @autoreleasepool {
    if (![NSThread isMainThread]) return 1;
    app();
    NSDictionary *item = [NSJSONSerialization JSONObjectWithData:[str(value) dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
    if (![item isKindOfClass:NSDictionary.class] || ![item[@"http_only"] boolValue]) return 1;
    NSString *name = item[@"name"], *content = item[@"value"];
    if (![name isKindOfClass:NSString.class] || ![content isKindOfClass:NSString.class] || !name.length || !content.length) return 1;
    // The gateway cookie is host-only. Never accept a provider-chosen domain.
    id domain = item[@"domain"];
    if (domain && domain != NSNull.null && ![domain isEqual:@"192.168.2.175"]) return 1;
    NSHTTPCookie *cookie = [NSHTTPCookie cookieWithProperties:@{
      NSHTTPCookieName: name, NSHTTPCookieValue: content,
      NSHTTPCookieDomain: @"192.168.2.175", NSHTTPCookiePath: @"/",
      @"HttpOnly": @"TRUE", NSHTTPCookieDiscard: @"TRUE"
    }];
    if (!cookie) return 1;
    __block BOOL finished = NO;
    [WKWebsiteDataStore.defaultDataStore.httpCookieStore setCookie:cookie completionHandler:^{ finished = YES; }];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!finished && deadline.timeIntervalSinceNow > 0) {
      [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    return finished ? 0 : 1;
  }
}
