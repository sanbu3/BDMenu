#include <dlfcn.h>
#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef CGError (*CGSGetDisplayListFn)(uint32_t, CGDirectDisplayID *, uint32_t *);
typedef CGError (*CGSConfigureDisplayEnabledFn)(CGDisplayConfigRef, CGDirectDisplayID, bool);

extern CFUUIDRef CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID displayID);

static CGSGetDisplayListFn getList;
static CGSConfigureDisplayEnabledFn cfgFn;

static void printUUID(CGDirectDisplayID id) {
    CFUUIDRef u = CGDisplayCreateUUIDFromDisplayID(id);
    if (u) {
        CFStringRef s = CFUUIDCreateString(kCFAllocatorDefault, u);
        char buf[64];
        CFStringGetCString(s, buf, sizeof(buf), kCFStringEncodingUTF8);
        printf("%s", buf);
        CFRelease(s);
        CFRelease(u);
    }
}

int main(int argc, char **argv) {
    void *sl = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
    if (!sl) {
        fprintf(stderr, "cannot load SkyLight: %s\n", dlerror());
        return 1;
    }
    getList = (CGSGetDisplayListFn)dlsym(sl, "CGSGetDisplayList");
    cfgFn = (CGSConfigureDisplayEnabledFn)dlsym(sl, "CGSConfigureDisplayEnabled");
    if (!getList || !cfgFn) {
        fprintf(stderr, "missing SkyLight symbols: %s\n", dlerror());
        return 1;
    }

    CGDirectDisplayID ids[32];
    uint32_t count = 0;
    getList(32, ids, &count);

    if (argc < 2 || strcmp(argv[1], "list") == 0) {
        for (int i = 0; i < (int)count; i++) {
            bool shown = CGDisplayIsActive(ids[i]) || CGDisplayIsInMirrorSet(ids[i]);
            printf("%d\t%d\t%d\t", ids[i], CGDisplayIsBuiltin(ids[i]), shown ? 1 : 0);
            printUUID(ids[i]);
            printf("\n");
        }
        return 0;
    }

    if (argc >= 3 && (strcmp(argv[1], "off") == 0 || strcmp(argv[1], "on") == 0)) {
        int target = atoi(argv[2]);
        bool enabled = strcmp(argv[1], "on") == 0;
        for (int i = 0; i < (int)count; i++) {
            if (ids[i] == (CGDirectDisplayID)target) {
                CGDisplayConfigRef configRef;
                CGBeginDisplayConfiguration(&configRef);
                CGError r = cfgFn(configRef, ids[i], enabled);
                CGError complete = CGCompleteDisplayConfiguration(configRef, kCGConfigurePermanently);
                if (r != 0 || complete != 0) {
                    fprintf(stderr, "failed: setEnabled=%d complete=%d\n", r, complete);
                    return 1;
                }
                printf("ok\n");
                return 0;
            }
        }
        if (enabled && target > 0) {
            CGDisplayConfigRef configRef;
            CGBeginDisplayConfiguration(&configRef);
            CGError r = cfgFn(configRef, (CGDirectDisplayID)target, true);
            CGError complete = CGCompleteDisplayConfiguration(configRef, kCGConfigurePermanently);
            if (r != 0 || complete != 0) {
                fprintf(stderr, "failed: setEnabled=%d complete=%d\n", r, complete);
                return 1;
            }
            printf("ok\n");
            return 0;
        }
        fprintf(stderr, "display %d not found\n", target);
        return 1;
    }

    fprintf(stderr, "usage: displaypower [list|off <id>|on <id>]\n");
    return 1;
}
