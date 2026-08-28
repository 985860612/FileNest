#ifndef SEVENZIP_BRIDGE_H
#define SEVENZIP_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*SZProgressCallback)(uint64_t completed,
                                   uint64_t total,
                                   const char *current_path,
                                   void *context);
typedef int (*SZCancelCallback)(void *context);

const char *sz_version(void);
const char *sz_last_error(void);

int sz_extract(const char *library_path,
               const char *archive_path,
               const char *output_directory,
               const char *password,
               SZProgressCallback progress,
               SZCancelCallback should_cancel,
               void *context);

int sz_compress(const char *library_path,
                const char *archive_path,
                const char *format,
                const char *const *input_paths,
                size_t input_count,
                const char *password,
                int compression_level,
                uint64_t dictionary_size,
                int exclude_macos_metadata,
                SZProgressCallback progress,
                SZCancelCallback should_cancel,
                void *context);

char *sz_list_json(const char *library_path,
                   const char *archive_path,
                   const char *password);
void sz_free_string(char *value);

#ifdef __cplusplus
}
#endif

#endif
