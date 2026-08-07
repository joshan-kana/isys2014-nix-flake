#!/usr/bin/env bash
set -euo pipefail

find_project_root() {
  local dir
  dir="$(pwd -P)"

  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/flake.nix" ]]; then
      printf '%s\n' "$dir"
      return
    fi
    dir="$(dirname "$dir")"
  done

  pwd -P
}

project_root="$(find_project_root)"
state_dir="$project_root/.mysql"
data_dir="$state_dir/data"
log_file="$state_dir/mysql.log"
stdout_log="$state_dir/mysqld.stdout.log"
project_id="$(printf '%s' "$project_root" | sha256sum | cut -c1-12)"
run_dir="/tmp/isys2014-mysql-$project_id"
socket_file="$run_dir/mysql.sock"
pid_file="$run_dir/mysql.pid"

mysql_args=(
  --protocol=socket
  --socket="$socket_file"
  --user=root
)

say() {
  if [[ "${quiet:-false}" != true ]]; then
    printf '%s\n' "$*"
  fi
}

server_running() {
  mysqladmin "${mysql_args[@]}" ping --silent >/dev/null 2>&1
}

initialise_database() {
  mkdir -p "$state_dir" "$run_dir"

  if [[ -d "$data_dir/mysql" ]]; then
    return
  fi

  say "Initialising MySQL data in $data_dir"
  rm -rf -- "$data_dir"
  mkdir -p "$data_dir"

  mysqld \
    --no-defaults \
    --initialize-insecure \
    --datadir="$data_dir" \
    --log-error="$log_file"
}

start_server() {
  quiet=false
  if [[ "${1:-}" == "--quiet" ]]; then
    quiet=true
    shift
  fi

  if (($# != 0)); then
    echo "Usage: db-start [--quiet]" >&2
    return 2
  fi

  if server_running; then
    say "MySQL is already running."
    return
  fi

  initialise_database
  rm -f -- "$socket_file" "$pid_file"

  nohup mysqld \
    --no-defaults \
    --datadir="$data_dir" \
    --socket="$socket_file" \
    --pid-file="$pid_file" \
    --log-error="$log_file" \
    --skip-networking \
    --skip-log-bin \
    --mysqlx=OFF \
    --innodb-buffer-pool-size=64M \
    >"$stdout_log" 2>&1 &

  for _ in {1..100}; do
    if server_running; then
      mysql "${mysql_args[@]}" \
        --execute='CREATE DATABASE IF NOT EXISTS dswork;'
      say "MySQL started."
      say "  data:   $data_dir"
      say "  socket: $socket_file"
      return
    fi

    if [[ -f "$pid_file" ]]; then
      local pid
      pid="$(cat "$pid_file")"
      if ! kill -0 "$pid" 2>/dev/null; then
        break
      fi
    fi

    sleep 0.1
  done

  echo "ERROR: MySQL failed to start." >&2
  if [[ -f "$log_file" ]]; then
    tail -n 50 "$log_file" >&2
  elif [[ -f "$stdout_log" ]]; then
    tail -n 50 "$stdout_log" >&2
  fi
  return 1
}

stop_server() {
  quiet=false
  if [[ "${1:-}" == "--quiet" ]]; then
    quiet=true
    shift
  fi

  if (($# != 0)); then
    echo "Usage: db-stop [--quiet]" >&2
    return 2
  fi

  if ! server_running; then
    rm -f -- "$socket_file" "$pid_file"
    say "MySQL is not running."
    return
  fi

  mysqladmin "${mysql_args[@]}" shutdown

  for _ in {1..100}; do
    if ! server_running; then
      rm -f -- "$socket_file" "$pid_file"
      say "MySQL stopped."
      return
    fi
    sleep 0.1
  done

  echo "ERROR: MySQL did not stop cleanly." >&2
  return 1
}

show_status() {
  if (($# != 0)); then
    echo "Usage: db-status" >&2
    return 2
  fi

  if server_running; then
    echo "MySQL is running."
    if [[ -f "$pid_file" ]]; then
      echo "  pid:    $(cat "$pid_file")"
    fi
    echo "  data:   $data_dir"
    echo "  socket: $socket_file"
  else
    echo "MySQL is stopped."
    echo "  data:   $data_dir"
    return 1
  fi
}

reset_server() {
  if (($# != 0)); then
    echo "Usage: db-reset" >&2
    return 2
  fi

  stop_server --quiet || true

  if [[ -f "$pid_file" ]]; then
    local pid
    pid="$(cat "$pid_file")"
    if kill -0 "$pid" 2>/dev/null; then
      echo "ERROR: refusing to reset while MySQL process $pid is running." >&2
      return 1
    fi
  fi

  rm -rf -- "$state_dir" "$run_dir"
  start_server
}

open_shell() {
  start_server --quiet
  exec mysql "${mysql_args[@]}" "$@"
}

run_file() {
  if (($# < 1 || $# > 2)); then
    echo "Usage: db-run FILE.sql [DATABASE]" >&2
    return 2
  fi

  local file database
  file="$1"
  database="${2:-dswork}"

  if [[ ! -f "$file" ]]; then
    printf 'ERROR: SQL file not found: %s\n' "$file" >&2
    return 1
  fi

  start_server --quiet
  mysql "${mysql_args[@]}" "$database" <"$file"
}

show_log() {
  if (($# != 0)); then
    echo "Usage: db-log" >&2
    return 2
  fi

  mkdir -p "$state_dir"
  touch "$log_file"
  exec tail -n 100 -f "$log_file"
}

print_env() {
  if (($# != 0)); then
    echo "Usage: dbctl env" >&2
    return 2
  fi

  mkdir -p "$state_dir" "$run_dir"
  printf 'export MYSQL_UNIX_PORT=%q\n' "$socket_file"
  printf 'export MYSQL_HISTFILE=%q\n' "$state_dir/mysql_history"
}

show_help() {
  cat <<'HELP'
Usage: dbctl COMMAND [ARGS]

Commands:
  start [--quiet]        Initialise and start this folder's MySQL server
  stop [--quiet]         Stop this folder's MySQL server
  status                 Show server state and paths
  reset                  Delete this folder's database and start fresh
  shell [MYSQL_ARGS...]  Open the MySQL client as root
  run FILE.sql [DB]      Run a SQL file; DB defaults to dswork
  log                    Follow the MySQL error log
  env                    Print shell exports used by the dev shell
  help                   Show this help

The server listens only on its Unix socket; TCP networking is disabled.
Data is stored in .mysql/ under the current practical folder.
HELP
}

command="${1:-shell}"
if (($# > 0)); then
  shift
fi

case "$command" in
  start) start_server "$@" ;;
  stop) stop_server "$@" ;;
  status) show_status "$@" ;;
  reset) reset_server "$@" ;;
  shell) open_shell "$@" ;;
  run) run_file "$@" ;;
  log) show_log "$@" ;;
  env) print_env "$@" ;;
  help | --help | -h) show_help ;;
  *)
    printf 'ERROR: unknown command: %s\n\n' "$command" >&2
    show_help >&2
    exit 2
    ;;
esac
