#include "moonbit.h"

#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/statvfs.h>

static int64_t bounded_product(uint64_t count, uint64_t size) {
  if (size != 0 && count > (uint64_t)INT64_MAX / size) return INT64_MAX;
  return (int64_t)(count * size);
}

/* Both arrays are call-scoped. Never retain the deployment-owned mount path. */
MOONBIT_FFI_EXPORT
moonbit_bytes_t lunanexa_storage_statvfs(moonbit_bytes_t path) {
  struct statvfs status;
  if (statvfs((const char *)path, &status) != 0) {
    return moonbit_make_bytes(0, 0);
  }
  const uint64_t block_size = status.f_frsize ? status.f_frsize : status.f_bsize;
  char line[160];
  int count = snprintf(
      line, sizeof(line), "%lld,%lld,%lld,%lld,%lld",
      (long long)bounded_product(status.f_blocks, block_size),
      (long long)bounded_product(status.f_bfree, block_size),
      (long long)bounded_product(status.f_bavail, block_size),
      (long long)status.f_files,
      (long long)status.f_favail);
  if (count <= 0 || (size_t)count >= sizeof(line)) {
    return moonbit_make_bytes(0, 0);
  }
  moonbit_bytes_t output = moonbit_make_bytes(count, 0);
  memcpy(output, line, (size_t)count);
  return output;
}
