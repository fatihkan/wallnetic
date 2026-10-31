#include <stdint.h>

typedef struct {
    double cpu_seconds;
    uint64_t resident_bytes;
    uint64_t footprint_bytes;
    uint64_t package_idle_wakeups;
    uint64_t interrupt_wakeups;
    int process_usage_available;
} BenchmarkMetrics;

int benchmark_metrics(BenchmarkMetrics *result);
