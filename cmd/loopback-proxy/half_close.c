#include "moonbit.h"

#include <errno.h>
#include <stdint.h>
#include <sys/socket.h>

/*
 * `moonbitlang/async` owns socket file descriptors and only exposes `Tcp::close`,
 * which shuts a connection down in both directions. A relay needs to close one
 * direction at a time: forwarding the agent's FIN while the controller's reply
 * is still draining, and waking a sibling direction that is blocked on a socket
 * without invalidating a descriptor it is still polling (closing a descriptor
 * another task waits on never wakes that task).
 */

MOONBIT_FFI_EXPORT
int32_t lunanexa_shutdown_write(int32_t fd) {
  return shutdown((int)fd, SHUT_WR) == 0 ? 0 : errno;
}

MOONBIT_FFI_EXPORT
int32_t lunanexa_shutdown_both(int32_t fd) {
  return shutdown((int)fd, SHUT_RDWR) == 0 ? 0 : errno;
}
