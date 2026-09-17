#include <notify.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    const char *labels[] = {"portrait", "upside-down", "landscape", "lock-screen"};
    if (argc != 2) {
        fprintf(stderr, "Usage: systemflip-capture portrait|upside-down|landscape|lock-screen\n");
        return 2;
    }
    for (unsigned i = 0; i < sizeof(labels) / sizeof(labels[0]); ++i) {
        if (strcmp(argv[1], labels[i]) != 0) continue;
        char name[128];
        snprintf(name, sizeof(name), "com.chenxun.systemflipprobe.capture.%s", labels[i]);
        uint32_t status = notify_post(name);
        if (status != NOTIFY_STATUS_OK) {
            fprintf(stderr, "notify_post failed: %u\n", status);
            return 1;
        }
        printf("Capture requested: %s. Keep this state for 6 seconds.\n"
               "This confirms posting only; check BOTH log files for matching capture labels.\n", labels[i]);
        return 0;
    }
    fprintf(stderr, "Unknown label. Use portrait, upside-down, landscape, or lock-screen.\n");
    return 2;
}
