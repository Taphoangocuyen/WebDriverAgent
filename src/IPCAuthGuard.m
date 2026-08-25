// IPCAuthGuard.m — DrakoCtrl WDA Auth Guard
//
// Dylib tự động hook vào WDA HTTP server qua +load.
// Swizzle RoutingConnection.httpResponseForMethod:URI:
//
// Hai lớp bảo vệ:
//   1. Route prefix: /ipc_XXXXXXXX/session thay vì /session
//      → Phần mềm chuẩn dùng path /session → 403
//      → PC app dùng path /ipc_XXXXXXXX/session → strip prefix → WDA xử lý /session
//   2. Auth header: X-IPC-Auth phải khớp key
//      → Dù biết prefix nhưng thiếu header → 403
//
// __IPC_AUTH_KEY__ và __IPC_ROUTE_PREFIX__ được thay thế lúc build.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ═══════════════════════════════════════════════════════
// Config — placeholders replaced at build time
// ═══════════════════════════════════════════════════════
static NSString *const kIPCAuthKey      = @"__IPC_AUTH_KEY__";
static NSString *const kIPCAuthHeader   = @"X-IPC-Auth";
static NSString *const kIPCRoutePrefix  = @"__IPC_ROUTE_PREFIX__";

// Store original IMP
static IMP _orig_httpResponse = NULL;

// Cached prefix path (e.g., "/ipc_badc5fb0/")
static NSString *_prefixSlash = nil;
static BOOL _usePrefixRoutes = NO;

// ═══════════════════════════════════════════════════════
// Runtime 403 response class
// ═══════════════════════════════════════════════════════
static Class _forbiddenResponseClass = Nil;

static void createForbiddenResponseClass(void) {
    Class superCls = NSClassFromString(@"HTTPDataResponse");
    if (!superCls) return;

    _forbiddenResponseClass = objc_allocateClassPair(superCls, "IPCForbiddenResponse", 0);
    if (!_forbiddenResponseClass) {
        _forbiddenResponseClass = NSClassFromString(@"IPCForbiddenResponse");
        return;
    }

    SEL statusSel = @selector(status);
    IMP statusImp = imp_implementationWithBlock(^NSInteger(id self) {
        return 403;
    });
    class_addMethod(_forbiddenResponseClass, statusSel, statusImp, "q@:");

    objc_registerClassPair(_forbiddenResponseClass);
}

static id createForbiddenResponse(void) {
    if (!_forbiddenResponseClass) return nil;

    NSData *body = [@"{\"value\":{\"error\":\"unauthorized\",\"message\":\"Invalid route or auth\"}}"
                    dataUsingEncoding:NSUTF8StringEncoding];

    id resp = ((id(*)(id, SEL))objc_msgSend)(
        _forbiddenResponseClass, @selector(alloc)
    );
    resp = ((id(*)(id, SEL, id))objc_msgSend)(
        resp, NSSelectorFromString(@"initWithData:"), body
    );
    return resp;
}

// ═══════════════════════════════════════════════════════
// Check auth header helper
// ═══════════════════════════════════════════════════════
static BOOL checkAuthHeader(id connectionSelf) {
    id request = ((id(*)(id, SEL))objc_msgSend)(connectionSelf, NSSelectorFromString(@"request"));
    if (!request) return NO;

    NSString *authValue = ((id(*)(id, SEL, id))objc_msgSend)(
        request, NSSelectorFromString(@"headerField:"), kIPCAuthHeader
    );
    return authValue != nil && [kIPCAuthKey isEqualToString:authValue];
}

// ═══════════════════════════════════════════════════════
// Swizzled HTTP handler — route prefix + auth check
// ═══════════════════════════════════════════════════════
static id ipc_httpResponseForMethod(id self, SEL _cmd, NSString *method, NSString *path) {
    // Whitelist: /status và /health luôn cho phép (health check, không data nhạy cảm)
    if ([path isEqualToString:@"/status"] || [path hasPrefix:@"/status?"]
        || [path isEqualToString:@"/health"] || [path hasPrefix:@"/health?"]) {
        return ((id(*)(id, SEL, id, id))_orig_httpResponse)(self, _cmd, method, path);
    }

    // ── Route prefix mode ──
    if (_usePrefixRoutes) {
        // Path phải bắt đầu bằng /<prefix>/
        if ([path hasPrefix:_prefixSlash]) {
            // Strip prefix: /ipc_badc5fb0/session → /session
            NSString *realPath = [path substringFromIndex:_prefixSlash.length - 1];

            // Kiểm tra auth header
            if (checkAuthHeader(self)) {
                return ((id(*)(id, SEL, id, id))_orig_httpResponse)(self, _cmd, method, realPath);
            }
            NSLog(@"[IPC-Auth] REJECTED (bad auth): %@ %@", method, path);
            return createForbiddenResponse();
        }

        // Path không có prefix → reject
        NSLog(@"[IPC-Auth] REJECTED (no prefix): %@ %@", method, path);
        return createForbiddenResponse();
    }

    // ── Auth-only mode (no prefix) ──
    if (checkAuthHeader(self)) {
        return ((id(*)(id, SEL, id, id))_orig_httpResponse)(self, _cmd, method, path);
    }

    NSLog(@"[IPC-Auth] REJECTED (no auth): %@ %@", method, path);
    return createForbiddenResponse();
}

// ═══════════════════════════════════════════════════════
// IPCAuthGuard — auto-installs via +load
// ═══════════════════════════════════════════════════════
@interface IPCAuthGuard : NSObject
@end

@implementation IPCAuthGuard

+ (void)load {
    // Skip if placeholder not replaced (dev/test)
    if ([kIPCAuthKey isEqualToString:@"__IPC_AUTH_KEY__"]) {
        NSLog(@"[IPC-Auth] WARNING: Auth key is placeholder, auth DISABLED");
        return;
    }

    // Setup route prefix
    if (kIPCRoutePrefix.length > 0 && ![kIPCRoutePrefix isEqualToString:@"__IPC_ROUTE_PREFIX__"]) {
        _prefixSlash = [NSString stringWithFormat:@"/%@/", kIPCRoutePrefix];
        _usePrefixRoutes = YES;
        NSLog(@"[IPC-Auth] Route prefix: %@", kIPCRoutePrefix);
    }

    // Create the 403 response class at runtime
    createForbiddenResponseClass();

    // Install hook
    Class routingConn = NSClassFromString(@"RoutingConnection");

    if (routingConn) {
        [self installHookOnClass:routingConn];
    } else {
        // RoutingConnection chưa load — retry trên background queue
        // Main queue KHÔNG hoạt động trong xctest context (TrollStore)
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            for (int attempt = 0; attempt < 60; attempt++) {
                [NSThread sleepForTimeInterval:0.5];
                Class rc = NSClassFromString(@"RoutingConnection");
                if (rc) {
                    NSLog(@"[IPC-Auth] RoutingConnection found after %.1fs", (attempt + 1) * 0.5);
                    // HTTPDataResponse cũng cần sẵn sàng cho 403 response
                    createForbiddenResponseClass();
                    [self installHookOnClass:rc];
                    return;
                }
            }
            NSLog(@"[IPC-Auth] ERROR: RoutingConnection not found after 30s!");
        });
    }
}

+ (void)installHookOnClass:(Class)cls {
    SEL sel = @selector(httpResponseForMethod:URI:);
    Method m = class_getInstanceMethod(cls, sel);

    if (!m) {
        NSLog(@"[IPC-Auth] ERROR: httpResponseForMethod:URI: not found on %@", cls);
        return;
    }

    _orig_httpResponse = method_setImplementation(m, (IMP)ipc_httpResponseForMethod);
    NSLog(@"[IPC-Auth] Guard ACTIVE (prefix: %@, key: %.8s...)",
          _usePrefixRoutes ? kIPCRoutePrefix : @"none", kIPCAuthKey.UTF8String);
}

@end
