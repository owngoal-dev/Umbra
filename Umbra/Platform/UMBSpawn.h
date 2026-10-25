#pragma once
#include <TargetConditionals.h>
#include <spawn.h>

#if TARGET_OS_TV
// These libSystem symbols are private on tvOS. RootHide supplies the entitlement
// and execution environment required to use them for the existing root helper.
extern int umb_spawn(pid_t *pid,
                     const char *path,
                     const posix_spawn_file_actions_t *actions,
                     const posix_spawnattr_t *attributes,
                     char *const argv[],
                     char *const envp[]) __asm("_posix_spawn");
extern int umb_spawnattr_init(posix_spawnattr_t *attr) __asm("_posix_spawnattr_init");
extern int umb_spawnattr_destroy(posix_spawnattr_t *attr) __asm("_posix_spawnattr_destroy");
extern int umb_spawn_actions_init(posix_spawn_file_actions_t *actions) __asm("_posix_spawn_file_actions_init");
extern int umb_spawn_actions_destroy(posix_spawn_file_actions_t *actions) __asm("_posix_spawn_file_actions_destroy");
extern int umb_spawn_actions_close(posix_spawn_file_actions_t *actions,
                                   int fd) __asm("_posix_spawn_file_actions_addclose");
extern int umb_spawn_actions_dup2(posix_spawn_file_actions_t *actions,
                                  int fd,
                                  int newfd) __asm("_posix_spawn_file_actions_adddup2");
#define posix_spawn umb_spawn
#define posix_spawnattr_init umb_spawnattr_init
#define posix_spawnattr_destroy umb_spawnattr_destroy
#define posix_spawn_file_actions_init umb_spawn_actions_init
#define posix_spawn_file_actions_destroy umb_spawn_actions_destroy
#define posix_spawn_file_actions_addclose umb_spawn_actions_close
#define posix_spawn_file_actions_adddup2 umb_spawn_actions_dup2
#endif
