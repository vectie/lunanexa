#include "moonbit.h"
#include <stdio.h>

/* Bytes are borrowed for this call only. No file is opened and no data retained. */
MOONBIT_FFI_EXPORT
void lunanexa_model_fleet_diagnostic(moonbit_bytes_t bytes) {
  (void)fwrite(bytes, 1, (size_t)Moonbit_array_length(bytes), stderr);
  (void)fflush(stderr);
}
