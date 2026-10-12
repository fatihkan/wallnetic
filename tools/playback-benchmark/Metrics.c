#include "Metrics.h"
#include <libproc.h>
#include <sys/resource.h>
#include <unistd.h>

// Only this process. No root access, private APIs, or unrelated process inspection.
int benchmark_metrics(BenchmarkMetrics *result) {
    *result = (BenchmarkMetrics){0};
    struct rusage usage;
    if (getrusage(RUSAGE_SELF, &usage) != 0) return -1;
    result->cpu_seconds = usage.ru_utime.tv_sec + usage.ru_stime.tv_sec
        + (usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1000000.0;
    struct rusage_info_v0 info = {0};
    if (proc_pid_rusage(getpid(), RUSAGE_INFO_V0, (rusage_info_t *)&info) == 0) {
        result->process_usage_available = 1;
        result->resident_bytes = info.ri_resident_size;
        result->footprint_bytes = info.ri_phys_footprint;
        result->package_idle_wakeups = info.ri_pkg_idle_wkups;
        result->interrupt_wakeups = info.ri_interrupt_wkups;
    }
    return 0;
}
