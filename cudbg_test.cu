#include "cuda.h"
#include "cudadebugger.h"

#include <iostream>
#include <pthread.h>
#include <signal.h>

// helpers

CUDBGAPI cudbgAPI;

void exit_safely(int code) {
  cudbgAPI->finalize();
  exit(code);
}

#define cudbgCheck(ans)                                                        \
  { __cudbgCheck((ans), __FILE__, __LINE__); }
inline void __cudbgCheck(CUDBGResult res, const char *file, int line) {
  if (res != CUDBG_SUCCESS) {
    std::cerr << "ERROR: " << cudbgGetErrorString(res) << " at " << file << ":"
              << line << std::endl;
    exit_safely(EXIT_FAILURE);
  }
}

// event handling

pthread_cond_t event_cond = PTHREAD_COND_INITIALIZER;
pthread_mutex_t event_lock = PTHREAD_MUTEX_INITIALIZER;

void event_callback(CUDBGEventCallbackData *data) {
  std::cout << "Event notification" << std::endl;
  pthread_cond_signal(&event_cond);
}

void handle_events() {
  while (true) {
    CUDBGEvent event;
    CUDBGResult res = cudbgAPI->getNextEvent(CUDBG_EVENT_QUEUE_TYPE_SYNC, &event);
    if (res == CUDBG_ERROR_NO_EVENT_AVAILABLE) {
      break;
    } else if (res != CUDBG_SUCCESS) {
      std::cerr << "HANDLER ERROR: " << cudbgGetErrorString(res) << std::endl;
      break;
    }

    std::cout << "Event: ";
    switch (event.kind) {
    case CUDBG_EVENT_INVALID:
      std::cout << "CUDBG_EVENT_INVALID";
      break;
    case CUDBG_EVENT_ELF_IMAGE_LOADED:
      std::cout << "CUDBG_EVENT_ELF_IMAGE_LOADED";
      break;
    case CUDBG_EVENT_KERNEL_READY:
      std::cout << "CUDBG_EVENT_KERNEL_READY";
      break;
    case CUDBG_EVENT_KERNEL_FINISHED:
      std::cout << "CUDBG_EVENT_KERNEL_FINISHED";
      break;
    case CUDBG_EVENT_INTERNAL_ERROR:
      std::cout << "CUDBG_EVENT_INTERNAL_ERROR ("
                << cudbgGetErrorString(event.cases.internalError.errorType)
                << ")";
      break;
    case CUDBG_EVENT_CTX_PUSH:
      std::cout << "CUDBG_EVENT_CTX_PUSH";
      break;
    case CUDBG_EVENT_CTX_POP:
      std::cout << "CUDBG_EVENT_CTX_POP";
      break;
    case CUDBG_EVENT_CTX_CREATE:
      std::cout << "CUDBG_EVENT_CTX_CREATE";
      break;
    case CUDBG_EVENT_CTX_DESTROY:
      std::cout << "CUDBG_EVENT_CTX_DESTROY";
      break;
    case CUDBG_EVENT_TIMEOUT:
      std::cout << "CUDBG_EVENT_TIMEOUT";
      break;
    case CUDBG_EVENT_ATTACH_COMPLETE:
      std::cout << "CUDBG_EVENT_ATTACH_COMPLETE";
      break;
    case CUDBG_EVENT_DETACH_COMPLETE:
      std::cout << "CUDBG_EVENT_DETACH_COMPLETE";
      break;
    case CUDBG_EVENT_ELF_IMAGE_UNLOADED:
      std::cout << "CUDBG_EVENT_ELF_IMAGE_UNLOADED";
      break;
    default:
      std::cout << "unknown event";
      break;
    }
    std::cout << std::endl;
  }

  // TODO: we should probably acknowledge the sync events here;
  //       I think that's why I'm getting the timeout events.
}

void *event_handler(void *null) {
  while (true) {
    pthread_mutex_lock(&event_lock);
    pthread_cond_wait(&event_cond, &event_lock);
    handle_events();
    pthread_mutex_unlock(&event_lock);
  }
}

// main

__global__ void kernel() { printf("Hello, World!\n"); }

int main(int argc, char const *argv[]) {
  signal(SIGINT, exit_safely);

  // gets the api
  std::cout << "Initializing debug API" << std::endl;
  uint32_t major, minor, rev;
  cudbgCheck(cudbgGetAPIVersion(&major, &minor, &rev));
  cudbgCheck(cudbgGetAPI(major, minor, rev, &cudbgAPI));
  cudbgCheck(cudbgAPI->initialize());

  // starts thread to print out events
  std::cout << "Starting event handler" << std::endl;
  pthread_t mannage_event_thread;
  pthread_create(&mannage_event_thread, NULL, event_handler, NULL);
  cudbgCheck(cudbgAPI->setNotifyNewEventCallback(event_callback));

  // Causes the program to freeze
  std::cout << "Launching kernel" << std::endl;
  kernel<<<1, 1>>>();

  exit_safely(0);

  return 0;
}

// this example does not work for unknown reasons, resulting in an "internal error (invalid
// context)" event that really does not make any sense.
//
// the subsequent timeouts are due to not acknowledging the sync events.

