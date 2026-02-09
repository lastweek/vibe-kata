#!/usr/bin/env bash
# Sync this repo to Ubuntu VM and run build+tests remotely.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
    cat <<USAGE
Usage: ./scripts/vm-sync-test.sh [smoke|integration|perf|all]

Defaults:
  suite=integration
  VM_USER=ys
  VM_HOST=127.0.0.1
  VM_PORT=2222
  VM_PASS=root
  VM_REMOTE_DIR=/home/ys/vibe-sandbox-vm
USAGE
}

suite="${1:-integration}"
case "$suite" in
    -h|--help)
        usage
        exit 0
        ;;
    smoke|integration|perf|all)
        ;;
    *)
        echo "Error: unknown suite '$suite'" >&2
        usage
        exit 2
        ;;
esac

if ! command -v expect >/dev/null 2>&1; then
    echo "Error: expect is required for password-based VM SSH automation" >&2
    exit 1
fi

: "${VM_USER:=ys}"
: "${VM_HOST:=127.0.0.1}"
: "${VM_PORT:=2222}"
: "${VM_PASS:=root}"
: "${VM_REMOTE_DIR:=/home/${VM_USER}/vibe-sandbox-vm}"

export VM_PROJECT_DIR="$PROJECT_DIR"
export VM_TEST_SUITE="$suite"
export VM_USER VM_HOST VM_PORT VM_PASS VM_REMOTE_DIR

exec expect <<'EXPECT'
set timeout -1

proc env_or_default {name default} {
    if {[info exists ::env($name)] && $::env($name) ne ""} {
        return $::env($name)
    }
    return $default
}

set project_dir [env_or_default "VM_PROJECT_DIR" ""]
set test_type [env_or_default "VM_TEST_SUITE" "integration"]
set vm_user [env_or_default "VM_USER" "ys"]
set vm_host [env_or_default "VM_HOST" "127.0.0.1"]
set vm_port [env_or_default "VM_PORT" "2222"]
set vm_pass [env_or_default "VM_PASS" "root"]
set vm_remote_dir [env_or_default "VM_REMOTE_DIR" "/home/$vm_user/vibe-sandbox-vm"]

if {$project_dir eq ""} {
    puts stderr "internal error: VM_PROJECT_DIR is empty"
    exit 2
}

if {$vm_pass eq ""} {
    stty -echo
    send_user "VM password for ${vm_user}@${vm_host}:${vm_port}: "
    expect_user -re "(.*)\n"
    stty echo
    send_user "\n"
    set vm_pass $expect_out(1,string)
}

set ssh_rsync_cmd [format "ssh -p %s -o StrictHostKeyChecking=accept-new -o PubkeyAuthentication=no" $vm_port]
set rsync_cmd [list rsync -rz --links --perms --delete \
    --exclude /.git \
    --exclude /.claude \
    --exclude /obj \
    --exclude /bin \
    --exclude /build \
    --exclude /run \
    --exclude "*.log" \
    -e $ssh_rsync_cmd \
    "$project_dir/" \
    "${vm_user}@${vm_host}:${vm_remote_dir}/"]

puts "==> Syncing source to VM"
puts "    local : $project_dir"
puts "    remote: ${vm_user}@${vm_host}:${vm_remote_dir}"
spawn {*}$rsync_cmd
expect {
    -re "(?i)password:" {
        send "$vm_pass\r"
        exp_continue
    }
    eof
}
set rsync_status [lindex [wait] 3]
if {$rsync_status != 0} {
    puts stderr "rsync failed with exit code $rsync_status"
    exit $rsync_status
}

set vm_pass_shell [string map {' '"'"'} $vm_pass]
set remote_cmd [format {set -euo pipefail; cd %s; mkdir -p "$HOME/.local/share/nano-sandbox/run"; printf '%%s\n' '%s' | sudo -S -v >/dev/null; sudo make install; ./scripts/test.sh %s} $vm_remote_dir $vm_pass_shell $test_type]
set ssh_cmd [list ssh -tt -p $vm_port -o StrictHostKeyChecking=accept-new -o PubkeyAuthentication=no "${vm_user}@${vm_host}" $remote_cmd]

puts "==> Running remote build + tests ($test_type)"
spawn {*}$ssh_cmd
expect {
    -re "(?i)(password for|password:)" {
        send "$vm_pass\r"
        exp_continue
    }
    eof
}
set ssh_status [lindex [wait] 3]
exit $ssh_status
EXPECT
