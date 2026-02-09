#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <getopt.h>
#include <errno.h>
#include <sys/stat.h>
#include <signal.h>
#include <sys/wait.h>
#include <limits.h>

#include "nk.h"
#include "nk_oci.h"
#include "nk_container.h"
#include "nk_log.h"
#include "common/state.h"

#define NS_STATE_DIR_ROOT "/run/nano-sandbox"
#define NS_STATE_DIR_USER_SUFFIX "/.local/share/nano-sandbox/run"

static int mkdir_p(const char *path, mode_t mode) {
    char tmp[PATH_MAX];
    size_t len;

    if (!path || path[0] == '\0') {
        errno = EINVAL;
        return -1;
    }

    len = strnlen(path, sizeof(tmp));
    if (len == 0 || len >= sizeof(tmp)) {
        errno = ENAMETOOLONG;
        return -1;
    }

    memcpy(tmp, path, len + 1);
    if (tmp[len - 1] == '/') {
        tmp[len - 1] = '\0';
    }

    for (char *p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = '\0';
            if (mkdir(tmp, mode) == -1 && errno != EEXIST) {
                return -1;
            }
            *p = '/';
        }
    }

    if (mkdir(tmp, mode) == -1 && errno != EEXIST) {
        return -1;
    }

    return 0;
}

/* Get state directory from environment or use robust defaults */
static const char *get_state_dir(void) {
    const char *dir = getenv("NS_RUN_DIR");
    static char user_dir[PATH_MAX];
    const char *home;
    int n;

    if (dir && dir[0] != '\0') {
        nk_stderr( "[GET_STATE_DIR] NS_RUN_DIR=%s\n", dir);
        fflush(stderr);
        return dir;
    }

    /* Backward compatibility for older scripts */
    dir = getenv("NK_RUN_DIR");
    if (dir && dir[0] != '\0') {
        nk_stderr( "[GET_STATE_DIR] NK_RUN_DIR=%s (compat)\n", dir);
        fflush(stderr);
        return dir;
    }

    if (geteuid() == 0) {
        nk_stderr( "[GET_STATE_DIR] default (root): %s\n", NS_STATE_DIR_ROOT);
        fflush(stderr);
        return NS_STATE_DIR_ROOT;
    }

    home = getenv("HOME");
    if (home && home[0] != '\0') {
        n = snprintf(user_dir, sizeof(user_dir), "%s%s", home, NS_STATE_DIR_USER_SUFFIX);
        if (n > 0 && (size_t)n < sizeof(user_dir)) {
            nk_stderr( "[GET_STATE_DIR] default (user): %s\n", user_dir);
            fflush(stderr);
            return user_dir;
        }
    }

    nk_stderr( "[GET_STATE_DIR] fallback: run\n");
    fflush(stderr);
    return "run";
}

static void print_usage(const char *prog_name) {
    nk_stderr( "Usage: %s <command> [options]\n\n", prog_name);
    nk_stderr( "Commands:\n");
    nk_stderr( "  create [options] <container-id>  Create a new container\n");
    nk_stderr( "  start [options] <container-id>    Start an existing container\n");
    nk_stderr( "  run [options] <container-id>      Create + start (Docker-style)\n");
    nk_stderr( "  delete <container-id>             Delete a container\n");
    nk_stderr( "  state <container-id>              Query container state\n\n");
    nk_stderr( "Options:\n");
    nk_stderr( "  -b, --bundle=<path>    Path to container bundle directory (default: .)\n");
    nk_stderr( "                         Bundle must contain: config.json and rootfs/\n");
    nk_stderr( "  -r, --runtime=<mode>   Execution mode: container|vm (default: container)\n");
    nk_stderr( "  -p, --pid-file=<file>  File to write container PID\n");
    nk_stderr( "  -a, --attach           Attach: wait for container process (start/run)\n");
    nk_stderr( "  -d, --detach           Detached mode: return after start (start/run)\n");
    nk_stderr( "      --rm               Remove container when attached run exits\n");
    nk_stderr( "  -V, --verbose          Enable verbose logging\n");
    nk_stderr( "  -E, --educational      Enable educational mode (explains operations)\n");
    nk_stderr( "  -h, --help            Show this help message\n");
    nk_stderr( "  -v, --version         Show version information\n");
    nk_stderr( "\n");
    nk_stderr( "Behavior:\n");
    nk_stderr( "  start (default)       Detached, like 'docker start'\n");
    nk_stderr( "  run (default)         Attached, like 'docker run'\n");
    nk_stderr( "  run -d                Detached create+start, like 'docker run -d'\n");
    nk_stderr( "\n");
    nk_stderr( "Examples:\n");
    nk_stderr( "  %s create --bundle=/usr/local/share/nano-sandbox/bundle my-container\n", prog_name);
    nk_stderr( "  %s start my-container\n", prog_name);
    nk_stderr( "  %s start -a my-container\n", prog_name);
    nk_stderr( "  %s run --bundle=/usr/local/share/nano-sandbox/bundle my-container\n", prog_name);
    nk_stderr( "  %s run -d --bundle=/usr/local/share/nano-sandbox/bundle my-container\n", prog_name);
    nk_stderr( "  %s delete my-container\n", prog_name);
    nk_stderr( "\n");
    nk_stderr( "Setup test bundle:\n");
    nk_stderr( "  ./scripts/setup-rootfs.sh\n");
}

static void print_version(void) {
    printf("nano-sandbox version %d.%d.%d\n",
           NK_VERSION_MAJOR, NK_VERSION_MINOR, NK_VERSION_PATCH);
    printf("Educational OCI Container Runtime with VM Isolation\n");
}

int nk_parse_args(int argc, char *argv[], nk_options_t *opts) {
    if (argc < 2) {
        return -1;
    }

    /* Initialize options with defaults */
    memset(opts, 0, sizeof(*opts));
    opts->bundle_path = strdup(".");
    opts->mode = NK_MODE_CONTAINER;
    opts->attach = false;
    opts->detach = false;
    opts->rm = false;

    /* Check for help/version flags first */
    if (strcmp(argv[1], "-h") == 0 || strcmp(argv[1], "--help") == 0) {
        opts->command = "help";
        return 0;
    }
    if (strcmp(argv[1], "-v") == 0 || strcmp(argv[1], "--version") == 0) {
        opts->command = "version";
        return 0;
    }

    /* First argument is the command */
    opts->command = argv[1];

    /* Parse remaining options */
    static struct option long_options[] = {
        {"bundle",      required_argument, 0, 'b'},
        {"runtime",     required_argument, 0, 'r'},
        {"pid-file",    required_argument, 0, 'p'},
        {"attach",      no_argument,       0, 'a'},
        {"detach",      no_argument,       0, 'd'},
        {"rm",          no_argument,       0,  1 },
        {"verbose",     no_argument,       0, 'V'},
        {"educational", no_argument,       0, 'E'},
        {"help",        no_argument,       0, 'h'},
        {"version",     no_argument,       0, 'v'},
        {0, 0, 0, 0}
    };

    int opt;
    int opt_index = 0;
    bool attach_set = false;
    bool detach_set = false;
    optind = 2; /* Start parsing from argv[2] */

    while ((opt = getopt_long(argc, argv, "b:r:p:adVEhv", long_options, &opt_index)) != -1) {
        switch (opt) {
        case 'b':
            free(opts->bundle_path);
            opts->bundle_path = strdup(optarg);
            break;
        case 'r':
            if (strcmp(optarg, "container") == 0) {
                opts->mode = NK_MODE_CONTAINER;
            } else if (strcmp(optarg, "vm") == 0) {
                opts->mode = NK_MODE_VM;
            } else {
                nk_stderr( "Error: Invalid runtime mode '%s'\n", optarg);
                return -1;
            }
            break;
        case 'p':
            opts->pid_file = strdup(optarg);
            break;
        case 'a':
            opts->attach = true;
            attach_set = true;
            break;
        case 'd':
            opts->detach = true;
            detach_set = true;
            break;
        case 1:
            opts->rm = true;
            break;
        case 'V':
            nk_log_set_level(NK_LOG_DEBUG);
            break;
        case 'E':
            nk_log_set_educational(true);
            nk_log_set_level(NK_LOG_INFO);
            break;
        case 'h':
            print_usage(argv[0]);
            exit(0);
        case 'v':
            print_version();
            exit(0);
        default:
            return -1;
        }
    }

    /* Container ID is the last non-option argument */
    if (optind < argc) {
        opts->container_id = argv[optind];
    }

    if (attach_set && detach_set) {
        nk_stderr("Error: --attach and --detach are mutually exclusive\n");
        return -1;
    }

    /* Validate command */
    if (strcmp(opts->command, "create") == 0) {
        if (attach_set || detach_set || opts->rm) {
            nk_stderr("Error: create does not support --attach/--detach/--rm\n");
            return -1;
        }
        if (!opts->container_id) {
            nk_stderr( "Error: create command requires container-id\n");
            return -1;
        }
    } else if (strcmp(opts->command, "start") == 0 ||
               strcmp(opts->command, "run") == 0 ||
               strcmp(opts->command, "delete") == 0 ||
               strcmp(opts->command, "state") == 0) {
        if (!opts->container_id) {
            nk_stderr( "Error: %s command requires container-id\n", opts->command);
            return -1;
        }
        if ((strcmp(opts->command, "delete") == 0 || strcmp(opts->command, "state") == 0) &&
            (attach_set || detach_set || opts->rm)) {
            nk_stderr("Error: %s does not support --attach/--detach/--rm\n", opts->command);
            return -1;
        }
    } else {
        nk_stderr( "Error: Unknown command '%s'\n", opts->command);
        return -1;
    }

    if (strcmp(opts->command, "start") == 0) {
        if (opts->rm) {
            nk_stderr("Error: start does not support --rm\n");
            return -1;
        }
        if (!attach_set && !detach_set) {
            opts->detach = true;  /* docker start behavior */
        }
    } else if (strcmp(opts->command, "run") == 0) {
        if (!attach_set && !detach_set) {
            opts->attach = true;  /* docker run behavior */
        }
        if (opts->rm && opts->detach) {
            nk_stderr("Error: --rm requires attached mode for run\n");
            return -1;
        }
    } else {
        opts->attach = false;
        opts->detach = false;
        opts->rm = false;
    }

    return 0;
}

static int ensure_state_dir(void) {
    const char *state_dir = get_state_dir();
    struct stat st;

    if (stat(state_dir, &st) == 0) {
        if (S_ISDIR(st.st_mode)) {
            return 0;
        }
        nk_stderr( "Error: %s exists but is not a directory\n", state_dir);
        return -1;
    }

    if (mkdir_p(state_dir, 0755) == -1) {
        nk_stderr( "Error: Failed to create %s: %s\n",
                state_dir, strerror(errno));
        return -1;
    }

    return 0;
}

static int write_pid_file(const char *pid_file, pid_t pid) {
    if (!pid_file || pid_file[0] == '\0') {
        return 0;
    }

    FILE *f = fopen(pid_file, "w");
    if (!f) {
        nk_log_error("Failed to open pid file %s: %s", pid_file, strerror(errno));
        return -1;
    }

    fprintf(f, "%d\n", (int)pid);
    fclose(f);
    nk_log_info("Wrote PID %d to %s", (int)pid, pid_file);
    return 0;
}

static int write_container_pid_file(const char *pid_file, const char *container_id) {
    nk_container_t *container;
    int ret;

    if (!pid_file) {
        return 0;
    }

    container = nk_state_load(container_id);
    if (!container) {
        nk_log_error("Failed to load container '%s' to write pid file", container_id);
        return -1;
    }
    if (container->init_pid <= 0) {
        nk_log_error("Container '%s' does not have a running PID", container_id);
        nk_container_free(container);
        return -1;
    }

    ret = write_pid_file(pid_file, container->init_pid);
    nk_container_free(container);
    return ret;
}

int nk_container_create(const nk_options_t *opts) {
    nk_log_info("Creating container '%s' (mode: %s)",
            opts->container_id,
            opts->mode == NK_MODE_CONTAINER ? "container" : "vm");

    if (nk_log_educational) {
        nk_log_explain("Creating container",
            "Container creation validates the OCI spec and prepares metadata. "
            "The actual isolation happens during 'start' with clone() and namespaces.");
    }

    /* Ensure state directory exists */
    nk_log_debug("Step 0: Ensuring state directory exists");
    if (ensure_state_dir() == -1) {
        return -1;
    }
    nk_log_debug("Step 0 complete");

    /* Check if container already exists */
    nk_log_debug("Step 1: Checking if container already exists");
    if (nk_state_exists(opts->container_id)) {
        nk_log_error("Container '%s' already exists", opts->container_id);
        return -1;
    }
    nk_log_debug("Step 1 complete (container does not exist)");

    /* Load OCI spec from bundle */
    nk_log_debug("Step 2: Loading OCI spec from bundle: %s", opts->bundle_path);
    nk_log_step(1, "Loading OCI spec from bundle");
    nk_oci_spec_t *spec = nk_oci_spec_load(opts->bundle_path);
    if (!spec) {
        nk_log_error("Failed to load OCI spec from %s", opts->bundle_path);
        return -1;
    }
    nk_log_debug("Step 2 complete (spec loaded)");
    nk_log_debug("OCI spec loaded successfully");

    /* Validate OCI spec */
    nk_log_debug("Step 3: Validating OCI spec");
    nk_log_step(2, "Validating OCI spec");
    if (!nk_oci_spec_validate(spec)) {
        nk_log_error("Invalid OCI spec");
        nk_oci_spec_free(spec);
        return -1;
    }
    nk_log_debug("Step 3 complete (spec valid)");
    nk_log_debug("OCI spec validation passed");

    fprintf(stdout, "  Bundle: %s\n", opts->bundle_path);
    fprintf(stdout, "  Root: %s\n", spec->root ? spec->root->path : "none");
    fflush(stdout);

    /* Create container structure */
    nk_log_debug("Step 4: Creating container metadata structure");
    nk_log_step(3, "Creating container metadata");
    nk_container_t *container = calloc(1, sizeof(*container));
    if (!container) {
        nk_log_error("Step 4 failed (calloc returned NULL)");
        nk_oci_spec_free(spec);
        return -1;
    }
    nk_log_debug("Step 4a: Allocating container strings");

    container->id = strdup(opts->container_id);
    container->bundle_path = strdup(opts->bundle_path);
    container->state = NK_STATE_CREATED;
    container->mode = opts->mode;
    container->init_pid = 0;
    container->control_fd = -1;
    nk_log_debug("Step 4 complete (container structure created)");
    nk_log_debug("Container structure created: id=%s, state=%d", container->id, container->state);

    /* Save container state */
    nk_log_debug("Step 5: Saving container state to disk");
    nk_log_step(4, "Saving container state to disk");
    if (nk_state_save(container) == -1) {
        nk_log_error("Step 5 failed (nk_state_save returned -1)");
        nk_log_error("Failed to save container state");
        nk_container_free(container);
        nk_oci_spec_free(spec);
        return -1;
    }
    nk_log_debug("Step 5 complete (state saved)");

    nk_log_debug("Step 6: Cleaning up and returning");
    nk_oci_spec_free(spec);
    nk_container_free(container);

    fprintf(stdout, "  Status: created\n");
    fflush(stdout);
    nk_log_debug("Create complete");

    return 0;
}

int nk_container_start(const char *container_id, bool attach, int *container_exit_code) {
    int exit_code = 0;

    nk_log_info("Starting container '%s'%s",
            container_id, attach ? " (attach mode)" : " (detached mode)");

    if (nk_log_educational) {
        nk_log_explain("Starting container",
            "Container start creates isolated process(es) using clone() with namespaces. "
            "Parent process monitors, child process runs in isolated environment.");
    }

    /* Load container state */
    nk_log_step(1, "Loading container state");
    nk_container_t *container = nk_state_load(container_id);
    if (!container) {
        nk_log_error("Container '%s' not found", container_id);
        return -1;
    }
    nk_log_debug("Container state loaded: id=%s, state=%d", container->id, container->state);

    if (container->state != NK_STATE_CREATED) {
        nk_log_error("Container is in wrong state: %d (expected CREATED)", container->state);
        nk_container_free(container);
        return -1;
    }

    /* Only support container mode for now */
    if (container->mode == NK_MODE_VM) {
        nk_log_error("VM mode not yet implemented (Phase 3)");
        nk_container_free(container);
        return -1;
    }

    /* Load OCI spec */
    nk_log_step(2, "Loading OCI spec");
    nk_oci_spec_t *spec = nk_oci_spec_load(container->bundle_path);
    if (!spec) {
        nk_log_error("Failed to load OCI spec");
        nk_container_free(container);
        return -1;
    }

    if (!spec->process || !spec->root) {
        nk_log_error("Invalid OCI spec - missing process or root");
        nk_oci_spec_free(spec);
        nk_container_free(container);
        return -1;
    }

    /* Build container context from OCI spec */
    nk_log_step(3, "Building container execution context");
    nk_container_ctx_t ctx = {0};

    char rootfs_path[PATH_MAX];
    snprintf(rootfs_path, sizeof(rootfs_path), "%s/%s",
             container->bundle_path, spec->root->path);
    ctx.rootfs = rootfs_path;
    nk_log_debug("Root filesystem: %s", ctx.rootfs);

    if (spec->linux_config && spec->linux_config->namespaces) {
        size_t ns_count = spec->linux_config->namespaces_len;
        ctx.namespaces = calloc(ns_count, sizeof(nk_namespace_config_t));
        if (ctx.namespaces) {
            for (size_t i = 0; i < ns_count; i++) {
                const char *type = spec->linux_config->namespaces[i].type;
                if (strcmp(type, "pid") == 0) ctx.namespaces[i].type = NK_NS_PID;
                else if (strcmp(type, "network") == 0) ctx.namespaces[i].type = NK_NS_NETWORK;
                else if (strcmp(type, "ipc") == 0) ctx.namespaces[i].type = NK_NS_IPC;
                else if (strcmp(type, "uts") == 0) ctx.namespaces[i].type = NK_NS_UTS;
                else if (strcmp(type, "mount") == 0) ctx.namespaces[i].type = NK_NS_MOUNT;
                else if (strcmp(type, "user") == 0) ctx.namespaces[i].type = NK_NS_USER;
                else if (strcmp(type, "cgroup") == 0) ctx.namespaces[i].type = NK_NS_CGROUP;

                ctx.namespaces[i].path = spec->linux_config->namespaces[i].path;
                ctx.namespaces[i].enable = true;
                nk_log_debug("Namespace[%zu]: %s", i, type);
            }
            ctx.namespaces_len = ns_count;
            nk_log_info("Parsed %zu namespaces", ns_count);
        }
    }

    ctx.args = spec->process->args;
    ctx.args_len = spec->process->args_len;
    ctx.env = spec->process->env;
    ctx.env_len = spec->process->env_len;
    ctx.cwd = spec->process->cwd ? spec->process->cwd : "/";
    ctx.terminal = spec->process->terminal;
    ctx.mounts = NULL;
    ctx.mounts_len = 0;

    nk_cgroup_config_t cg_cfg = {0};
    ctx.cgroup = &cg_cfg;

    fprintf(stdout, "  Executing: %s\n", ctx.args[0]);

    nk_log_step(4, "Executing container process");
    if (nk_log_educational) {
        nk_log_explain("Calling clone()",
            "clone() system call creates new process with isolated namespaces. "
            "Returns in both parent (gets PID) and child (gets 0).");
    }

    pid_t pid = nk_container_exec(&ctx);
    if (pid == -1) {
        nk_log_error("Failed to execute container");
        free(ctx.namespaces);
        nk_oci_spec_free(spec);
        nk_container_free(container);
        return -1;
    }

    nk_log_info("Container process created with PID: %d", pid);

    container->state = NK_STATE_RUNNING;
    container->init_pid = pid;
    if (nk_state_save(container) == -1) {
        nk_stderr("Warning: Failed to save container state\n");
    }

    free(ctx.namespaces);
    nk_oci_spec_free(spec);

    fprintf(stdout, "  Status: running (PID: %d)\n", (int)pid);

    if (!attach) {
        fprintf(stdout, "  Mode: detached (like docker start)\n");
        nk_container_free(container);
        if (container_exit_code) {
            *container_exit_code = 0;
        }
        return 0;
    }

    fprintf(stdout, "  Mode: attached (waiting for container process)\n");
    int wait_status = 0;
    if (nk_container_wait(pid, &wait_status) == -1) {
        nk_container_free(container);
        return -1;
    }

    if (WIFEXITED(wait_status)) {
        exit_code = WEXITSTATUS(wait_status);
        nk_log_info("Container process exited with code %d", exit_code);
    } else if (WIFSIGNALED(wait_status)) {
        exit_code = 128 + WTERMSIG(wait_status);
        nk_log_warn("Container process killed by signal %d", WTERMSIG(wait_status));
    }

    container->state = NK_STATE_STOPPED;
    container->init_pid = 0;
    if (nk_state_save(container) == -1) {
        nk_stderr("Warning: Failed to persist stopped state\n");
    }
    nk_container_free(container);

    fprintf(stdout, "  Status: stopped (exit code: %d)\n", exit_code);
    if (container_exit_code) {
        *container_exit_code = exit_code;
    }
    return 0;
}

int nk_container_run(const nk_options_t *opts) {
    if (!opts || !opts->container_id) {
        nk_log_error("Invalid run options");
        return -1;
    }

    nk_log_info("Running container '%s'%s",
            opts->container_id, opts->detach ? " (detached)" : " (attached)");

    if (nk_container_create(opts) == -1) {
        return -1;
    }

    int exit_code = 0;
    if (nk_container_start(opts->container_id, opts->attach, &exit_code) == -1) {
        if (opts->rm) {
            nk_log_warn("Run failed; cleaning up container '%s' (--rm)", opts->container_id);
            (void)nk_container_delete(opts->container_id);
        }
        return -1;
    }

    if (opts->rm) {
        nk_log_info("Auto-removing container '%s' (--rm)", opts->container_id);
        if (nk_container_delete(opts->container_id) == -1) {
            return -1;
        }
    }

    return opts->attach ? exit_code : 0;
}

int nk_container_delete(const char *container_id) {
    fprintf(stdout, "Deleting container '%s'\n", container_id);

    /* Load container state */
    nk_container_t *container = nk_state_load(container_id);
    if (!container) {
        nk_stderr( "Error: Container '%s' not found\n", container_id);
        return -1;
    }

    /* Stop container if running */
    if (container->state == NK_STATE_RUNNING && container->init_pid > 0) {
        fprintf(stdout, "  Stopping container (PID: %d)\n", container->init_pid);

        /* Send SIGTERM first */
        if (nk_container_signal(container->init_pid, SIGTERM) == 0) {
            /* Wait a bit for graceful shutdown */
            usleep(100000);  /* 100ms */

            /* Check if process still exists */
            if (kill(container->init_pid, 0) == 0) {
                /* Force kill if still running */
                fprintf(stdout, "  Force killing...\n");
                nk_container_signal(container->init_pid, SIGKILL);
            }
        }
    }

    /* Cleanup cgroups */
    nk_cgroup_cleanup(container_id);

    /* Delete state file */
    if (nk_state_delete(container_id) == -1) {
        nk_stderr( "Warning: Failed to delete state file\n");
    }

    nk_container_free(container);

    fprintf(stdout, "  Status: deleted\n");

    return 0;
}

nk_container_state_t nk_container_state(const char *container_id) {
    /* Load container state */
    nk_container_t *container = nk_state_load(container_id);
    if (!container) {
        nk_stderr( "Error: Container '%s' not found\n", container_id);
        return -1;
    }

    nk_container_state_t state = container->state;
    nk_container_free(container);

    return state;
}

void nk_container_free(nk_container_t *container) {
    if (!container) {
        return;
    }

    free(container->id);
    free(container->bundle_path);
    free(container->state_file);
    if (container->control_fd != -1) {
        close(container->control_fd);
    }
    free(container);
}

int main(int argc, char *argv[]) {
    nk_options_t opts;
    nk_log_set_role(NK_LOG_ROLE_PARENT);

    if (nk_parse_args(argc, argv, &opts) == -1) {
        print_usage(argv[0]);
        return 1;
    }

    int ret = 0;

    if (strcmp(opts.command, "help") == 0) {
        print_usage(argv[0]);
    } else if (strcmp(opts.command, "version") == 0) {
        print_version();
    } else if (strcmp(opts.command, "create") == 0) {
        ret = nk_container_create(&opts);
    } else if (strcmp(opts.command, "start") == 0) {
        int exit_code = 0;
        ret = nk_container_start(opts.container_id, opts.attach, &exit_code);
        if (ret == 0 && opts.pid_file && opts.detach) {
            ret = write_container_pid_file(opts.pid_file, opts.container_id);
        }
        if (ret == 0 && opts.attach) {
            ret = exit_code;
        }
    } else if (strcmp(opts.command, "run") == 0) {
        ret = nk_container_run(&opts);
        if (ret == 0 && opts.pid_file && opts.detach) {
            ret = write_container_pid_file(opts.pid_file, opts.container_id);
        }
    } else if (strcmp(opts.command, "delete") == 0) {
        ret = nk_container_delete(opts.container_id);
    } else if (strcmp(opts.command, "state") == 0) {
        nk_container_state_t state = nk_container_state(opts.container_id);
        const char *state_str;

        switch (state) {
        case NK_STATE_CREATED:
            state_str = "created";
            break;
        case NK_STATE_RUNNING:
            state_str = "running";
            break;
        case NK_STATE_STOPPED:
            state_str = "stopped";
            break;
        case NK_STATE_PAUSED:
            state_str = "paused";
            break;
        default:
            state_str = "unknown";
            break;
        }

        printf("%s\n", state_str);
    }

    /* Cleanup options */
    free(opts.bundle_path);
    free(opts.pid_file);

    return ret;
}
