#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "SevenZipBridge.h"

typedef int (*CompressFunction)(const char *, const char *, const char *,
    const char *const *, size_t, const char *, int, uint64_t,
    SZProgressCallback, SZCancelCallback, void *);
typedef int (*ExtractFunction)(const char *, const char *, const char *, const char *,
    SZProgressCallback, SZCancelCallback, void *);
typedef char *(*ListFunction)(const char *, const char *, const char *);
typedef const char *(*ErrorFunction)(void);
typedef void (*FreeFunction)(char *);

int main(int argc, char **argv)
{
  if (argc != 7) {
    fprintf(stderr, "usage: bridge-smoke bridge engine input archive output format\n");
    return 64;
  }
  void *bridge = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  if (!bridge) {
    fprintf(stderr, "%s\n", dlerror());
    return 65;
  }
  CompressFunction compress = (CompressFunction)dlsym(bridge, "sz_compress");
  ExtractFunction extract = (ExtractFunction)dlsym(bridge, "sz_extract");
  ListFunction list = (ListFunction)dlsym(bridge, "sz_list_json");
  ErrorFunction lastError = (ErrorFunction)dlsym(bridge, "sz_last_error");
  FreeFunction freeString = (FreeFunction)dlsym(bridge, "sz_free_string");
  if (!compress || !extract || !list || !lastError || !freeString) {
    fprintf(stderr, "bridge exports are incomplete\n");
    return 66;
  }
  const char *password = getenv("SMOKE_PASSWORD");
  const char *inputs[] = { argv[3] };
  uint64_t dictionarySize = strcmp(argv[6], "7z") == 0 ? 16ULL * 1024 * 1024 : 0;
  int result = compress(argv[2], argv[4], argv[6], inputs, 1, password, 5,
      dictionarySize, NULL, NULL, NULL);
  if (result != 0) {
    fprintf(stderr, "compress: %s (%d)\n", lastError(), result);
    return 67;
  }
  char *items = list(argv[2], argv[4], password);
  if (!items || strstr(items, "fixture.txt") == NULL) {
    fprintf(stderr, "list: %s\n", lastError());
    return 68;
  }
  puts(items);
  freeString(items);
  result = extract(argv[2], argv[4], argv[5], password, NULL, NULL, NULL);
  if (result != 0) {
    fprintf(stderr, "extract: %s (%d)\n", lastError(), result);
    return 69;
  }
  if (password && password[0] != '\0') {
    size_t length = strlen(argv[5]) + 7;
    char *wrongOutput = (char *)malloc(length);
    snprintf(wrongOutput, length, "%s-wrong", argv[5]);
    result = extract(argv[2], argv[4], wrongOutput, "wrong-password", NULL, NULL, NULL);
    free(wrongOutput);
    if (result == 0) {
      fprintf(stderr, "encrypted archive unexpectedly accepted a wrong password\n");
      return 70;
    }
  }
  dlclose(bridge);
  return 0;
}
