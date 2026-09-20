#include "moonbit.h"
#include <errno.h>
#include <stdint.h>
#if defined(__linux__)
#include <sys/random.h>
#elif defined(__APPLE__)
#include <stdlib.h>
#else
#error "The node runtime supervisor needs Linux getentropy or Apple arc4random_buf"
#endif

/* Borrowed output is populated only during this call; never retained. */
MOONBIT_FFI_EXPORT
int32_t lunanexa_node_secure_random(moonbit_bytes_t output) {
  const int32_t length = Moonbit_array_length(output);
  if (length != 32) return EINVAL;
#if defined(__linux__)
  if (getentropy(output, (size_t)length) == 0) return 0;
  return errno == 0 ? EIO : errno;
#else
  arc4random_buf(output, (size_t)length);
  return 0;
#endif
}
