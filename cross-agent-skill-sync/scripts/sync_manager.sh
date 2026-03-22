#!/usr/bin/env bash

set -euo pipefail

HOME_DIR="${HOME:-}"
if [ -z "$HOME_DIR" ]; then
  HOME_DIR="$(cd ~ >/dev/null 2>&1 && pwd -P || pwd -P)"
fi

FIELD_SEP=$'\x1f'
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
DEFAULT_BUNDLED_CONFIG="${SKILL_ROOT}/config.conf"
DEFAULT_CONFIG_USER="${HOME_DIR}/.config/cross-agent-skill-sync/config.conf"
DEFAULT_CONFIG_PROJECT=".cross-agent-skill-sync.conf"

CONFIG_SOURCES_FILE=""
CONFIG_USER_FILE=""
CONFIG_PROJECT_FILE=""

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

var_name_to_key() {
  printf '%s\n' "$1" | tr '[:upper:]' '[:lower:]' | tr '_' '-'
}

key_to_var_name() {
  printf '%s\n' "$1" | tr '[:upper:]-' '[:lower:]_'
}

expand_path() {
  local raw="$1"
  case "$raw" in
    "~") printf '%s\n' "$HOME_DIR" ;;
    "~/"*) printf '%s/%s\n' "$HOME_DIR" "${raw#~/}" ;;
    *) printf '%s\n' "$raw" ;;
  esac
}

list_source_keys() {
  local var key
  while IFS= read -r var; do
    key="${var#SOURCE_}"
    [ -n "$key" ] || continue
    var_name_to_key "$key"
  done < <(compgen -A variable | grep '^SOURCE_[A-Za-z0-9_][A-Za-z0-9_]*$' | grep -v '^SOURCE_CHOICES$' | sort)
}

list_tool_keys() {
  local var key
  while IFS= read -r var; do
    key="${var#AGENT_}"
    key="${key%_USER}"
    [ -n "$key" ] || continue
    var_name_to_key "$key"
  done < <(compgen -A variable | grep '^AGENT_[A-Za-z0-9_][A-Za-z0-9_]*_USER$' | sort)
}

source_root_for_key() {
  local key="$1"
  local var_name="SOURCE_$(key_to_var_name "$key")"
  local value="${!var_name:-}"
  [ -n "$value" ] || die "Unsupported source: $key"
  expand_path "$value"
}

user_dir_for_tool() {
  local key="$1"
  local var_name="AGENT_$(key_to_var_name "$key")_USER"
  local value="${!var_name:-}"
  [ -n "$value" ] || die "Unsupported tool: $key"
  expand_path "$value"
}

project_dir_name_for_tool() {
  local key="$1"
  local var_name="AGENT_$(key_to_var_name "$key")_PROJECT"
  local value="${!var_name:-}"
  [ -n "$value" ] || die "Unsupported tool: $key"
  printf '%s\n' "$value"
}

external_sources_csv_for_tool() {
  local key="$1"
  local var_name="AGENT_$(key_to_var_name "$key")_EXTERNAL_SOURCES"
  printf '%s\n' "${!var_name:-}"
}

load_config_file_if_present() {
  local file="$1"
  [ -n "$file" ] || return 0
  [ -f "$file" ] || return 0
  # shellcheck disable=SC1090
  . "$file"
  CONFIG_SOURCES_FILE="${CONFIG_SOURCES_FILE}${CONFIG_SOURCES_FILE:+,}${file}"
}

load_config() {
  local project_root_for_config
  project_root_for_config="${PROJECT_ROOT:-$PWD}"
  CONFIG_USER_FILE="${SKILL_SYNC_CONFIG_USER:-$DEFAULT_CONFIG_USER}"
  if [ -n "${SKILL_SYNC_CONFIG_PROJECT:-}" ]; then
    CONFIG_PROJECT_FILE="${SKILL_SYNC_CONFIG_PROJECT}"
  elif [ -n "$project_root_for_config" ]; then
    CONFIG_PROJECT_FILE="${project_root_for_config%/}/${DEFAULT_CONFIG_PROJECT}"
  else
    CONFIG_PROJECT_FILE=""
  fi

  load_config_file_if_present "$DEFAULT_BUNDLED_CONFIG"
  load_config_file_if_present "$CONFIG_USER_FILE"
  load_config_file_if_present "$CONFIG_PROJECT_FILE"
  if [ -n "${SKILL_SYNC_CONFIG:-}" ]; then
    load_config_file_if_present "$SKILL_SYNC_CONFIG"
  fi
}

now_utc() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

json_string() {
  awk -v s="$1" '
    BEGIN {
      gsub(/\\/,"\\\\",s)
      gsub(/"/,"\\\"",s)
      gsub(/\t/,"\\t",s)
      gsub(/\r/,"\\r",s)
      gsub(/\n/,"\\n",s)
      printf "\"%s\"", s
      exit
    }
  '
}

json_file_array() {
  local file="$1"
  printf '['
  if [ -f "$file" ] && [ -s "$file" ]; then
    awk 'NR > 1 { printf "," } { printf "%s", $0 }' "$file"
  fi
  printf ']'
}

json_string_file_array() {
  local file="$1"
  local temp_json
  temp_json="$(mktemp)"
  if [ -f "$file" ] && [ -s "$file" ]; then
    while IFS= read -r line; do
      printf '%s\n' "$(json_string "$line")" >> "$temp_json"
    done < "$file"
  fi
  json_file_array "$temp_json"
  rm -f "$temp_json"
}

canonical_dir() {
  local dir="$1"
  (
    cd "$dir" >/dev/null 2>&1 && pwd -P
  )
}

normalize_tool() {
  local raw
  raw="$(printf '%s' "$1" | tr '[:upper:]_' '[:lower:]-')"
  case "$raw" in
    claude) raw="claude-code" ;;
    "claude code") raw="claude-code" ;;
    "open code") raw="opencode" ;;
    "open claw") raw="openclaw" ;;
    "github copilot") raw="copilot" ;;
  esac

  local tool
  while IFS= read -r tool; do
    if [ "$raw" = "$tool" ]; then
      printf '%s\n' "$tool"
      return
    fi
  done < <(list_tool_keys)

  die "Unsupported tool: $1"
}

normalize_source() {
  local raw
  raw="$(printf '%s' "$1" | tr '[:upper:]_' '[:lower:]-' | tr ' ' '-')"
  case "$raw" in
    source|sources|all|全部|两者都看) printf 'all\n' ; return ;;
    skills) raw="agents" ;;
  esac

  local source
  while IFS= read -r source; do
    if [ "$raw" = "$source" ]; then
      printf '%s\n' "$source"
      return
    fi
  done < <(list_source_keys)

  die "Unsupported source: $1"
}

parse_sources_to_file() {
  local raw="$1"
  local temp_file="$2"
  split_csv_to_file "$raw" "$temp_file"
  if [ ! -s "$temp_file" ] || grep -Eqx 'all|全部|两者都看|sources?' "$temp_file"; then
    list_source_keys > "$temp_file"
    return
  fi
  local normalized_file
  normalized_file="$(mktemp)"
  while IFS= read -r source; do
    normalize_source "$source" >> "$normalized_file"
  done < "$temp_file"
  sort -u "$normalized_file" > "$temp_file"
  rm -f "$normalized_file"
}

parse_external_sources_for_tool_to_file() {
  local tool="$1"
  local output_file="$2"
  local raw normalized_file source
  raw="$(external_sources_csv_for_tool "$tool")"
  : > "$output_file"
  [ -n "$raw" ] || return
  split_csv_to_file "$raw" "$output_file"
  normalized_file="$(mktemp)"
  while IFS= read -r source; do
    normalize_source "$source" >> "$normalized_file"
  done < "$output_file"
  sort -u "$normalized_file" > "$output_file"
  rm -f "$normalized_file"
}

tool_loads_source_externally() {
  local tool="$1"
  local source="$2"
  local external_sources_file
  external_sources_file="$(mktemp)"
  parse_external_sources_for_tool_to_file "$tool" "$external_sources_file"
  if grep -Fqx "$source" "$external_sources_file" 2>/dev/null; then
    rm -f "$external_sources_file"
    return 0
  fi
  rm -f "$external_sources_file"
  return 1
}

source_allowed() {
  local key="$1"
  local allowed_file="$2"
  grep -Fqx "$key" "$allowed_file"
}

render_string_map_json() {
  local keys_file="$1"
  local value_fn="$2"
  local emitted=0 key value
  printf '{'
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    value="$($value_fn "$key")"
    [ "$emitted" -eq 1 ] && printf ','
    printf '\n    %s: %s' "$(json_string "$key")" "$(json_string "$value")"
    emitted=1
  done < "$keys_file"
  if [ "$emitted" -eq 1 ]; then
    printf '\n  }'
  else
    printf '}'
  fi
}

split_csv_to_file() {
  local raw="$1"
  local output_file="$2"
  : > "$output_file"
  if [ -z "$raw" ]; then
    return
  fi
  awk -v raw="$raw" '
    BEGIN {
      n = split(raw, parts, ",")
      for (i = 1; i <= n; i++) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", parts[i])
        if (parts[i] != "") print parts[i]
      }
    }
  ' >> "$output_file"
}

parse_tools_to_file() {
  local raw="$1"
  local temp_file="$2"
  split_csv_to_file "$raw" "$temp_file"
  if [ ! -s "$temp_file" ] || grep -Fqx 'all' "$temp_file" || grep -Fqx '全部' "$temp_file"; then
    list_tool_keys > "$temp_file"
    return
  fi
  local normalized_file
  normalized_file="$(mktemp)"
  while IFS= read -r tool; do
    normalize_tool "$tool" >> "$normalized_file"
  done < "$temp_file"
  sort -u "$normalized_file" > "$temp_file"
  rm -f "$normalized_file"
}

resolve_skills_to_file() {
  local raw="$1"
  local inventory_file="$2"
  local output_file="$3"
  split_csv_to_file "$raw" "$output_file"
  if [ ! -s "$output_file" ] || grep -Fqx 'all' "$output_file" || grep -Fqx '全部' "$output_file"; then
    if [ -f "$inventory_file" ] && [ -s "$inventory_file" ]; then
      cut -f1 "$inventory_file" | sort -u > "$output_file"
    else
      : > "$output_file"
    fi
  else
    sort -u "$output_file" -o "$output_file"
  fi
}

parse_source_choices_to_file() {
  local output_file="$1"
  shift
  : > "$output_file"
  local entry skill source
  for entry in "$@"; do
    case "$entry" in
      *=*)
        skill="${entry%%=*}"
        source="${entry#*=}"
        ;;
      *)
        die "Invalid source choice: $entry"
        ;;
    esac
    source="$(normalize_source "$source")"
    [ "$source" != "all" ] || die "A source choice for $skill must point to one concrete source"
    printf '%s\t%s\n' "$skill" "$source" >> "$output_file"
  done
}

selected_source_for_skill() {
  local skill="$1"
  local source_choice_file="$2"
  awk -F '\t' -v skill="$skill" '$1 == skill { print $2; exit }' "$source_choice_file"
}

options_json_for_skill() {
  local skill="$1"
  local inventory_file="$2"
  local temp_json
  temp_json="$(mktemp)"
  while IFS=$'\t' read -r _skill source path; do
    printf '{"source":%s,"path":%s}\n' \
      "$(json_string "$source")" \
      "$(json_string "$path")" >> "$temp_json"
  done < <(awk -F '\t' -v skill="$skill" '$1 == skill { print $1 "\t" $2 "\t" $3 }' "$inventory_file")
  json_file_array "$temp_json"
  rm -f "$temp_json"
}

build_source_inventory() {
  local allowed_sources_file="$1"
  local output_file="$2"
  : > "$output_file"
  local source_name root entry resolved_root
  while IFS= read -r source_name; do
    [ -n "$source_name" ] || continue
    root="$(source_root_for_key "$source_name")"
    [ -d "$root" ] || continue
    while IFS= read -r entry; do
      resolved_root="$(canonical_dir "$entry")" || continue
      printf '%s\t%s\t%s\n' "$(basename "$entry")" "$source_name" "$resolved_root" >> "$output_file"
    done < <(find "$root" -mindepth 1 -maxdepth 1 -type d | sort)
  done < "$allowed_sources_file"
}

build_target_roots() {
  local scope="$1"
  local tools_file="$2"
  local project_root="${3:-}"
  local output_file="$4"
  : > "$output_file"

  case "$scope" in
    user|project|both) ;;
    *) die "Unsupported scope: $scope" ;;
  esac

  if [ "$scope" = 'project' ] || [ "$scope" = 'both' ]; then
    [ -n "$project_root" ] || die "--project-root is required for project or both scope"
  fi

  while IFS= read -r tool; do
    [ -n "$tool" ] || continue
    if [ "$scope" = 'user' ] || [ "$scope" = 'both' ]; then
      printf '%s\t%s\t%s\n' "$tool" "user" "$(user_dir_for_tool "$tool")" >> "$output_file"
    fi
    if [ "$scope" = 'project' ] || [ "$scope" = 'both' ]; then
      printf '%s\t%s\t%s/%s\n' \
        "$tool" \
        "project" \
        "$project_root" \
        "$(project_dir_name_for_tool "$tool")" >> "$output_file"
    fi
  done < "$tools_file"
}

render_source_roots_json() {
  local sources_file="$1"
  render_string_map_json "$sources_file" source_root_for_key
}

render_source_counts_json() {
  local sources_file="$1"
  local inventory_file="$2"
  local emitted=0 source count
  printf '{'
  while IFS= read -r source; do
    [ -n "$source" ] || continue
    count="$(awk -F '\t' -v source="$source" '$2 == source { seen[$1] = 1 } END { total = 0; for (k in seen) total++; print total + 0 }' "$inventory_file" 2>/dev/null || printf '0')"
    [ "$emitted" -eq 1 ] && printf ','
    printf '\n    %s: %s' "$(json_string "$source")" "$count"
    emitted=1
  done < "$sources_file"
  if [ "$emitted" -eq 1 ]; then
    printf '\n  }'
  else
    printf '}'
  fi
}

command_for_action() {
  local kind="$1" path="$2" source_path="$3"
  case "$kind" in
    mkdir) printf 'mkdir -p %s' "$(shell_quote "$path")" ;;
    link) printf 'ln -s %s %s' "$(shell_quote "$source_path")" "$(shell_quote "$path")" ;;
    relink) printf 'unlink %s && ln -s %s %s' "$(shell_quote "$path")" "$(shell_quote "$source_path")" "$(shell_quote "$path")" ;;
    unlink) printf 'unlink %s' "$(shell_quote "$path")" ;;
    covered-by-external-source) printf '' ;;
    *) printf '' ;;
  esac
}

shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\"'\"'/g")"
}

append_meta_record() {
  local file="$1" key="$2" value="$3"
  printf 'META%s%s%s%s\n' "$FIELD_SEP" "$key" "$FIELD_SEP" "$value" >> "$file"
}

created_dir_recorded() {
  local dir="$1" file="$2"
  grep -Fqx "$dir" "$file" 2>/dev/null
}

resolved_symlink_dir() {
  local path="$1"
  if [ -L "$path" ] && [ -d "$path" ]; then
    canonical_dir "$path"
  fi
}

render_inventory_json() {
  local sources_file="$1"
  local inventory_file="$2"
  local skills_json conflicts_json temp_skill_json
  skills_json="$(mktemp)"
  conflicts_json="$(mktemp)"
  if [ -f "$inventory_file" ] && [ -s "$inventory_file" ]; then
    while IFS= read -r skill; do
      temp_skill_json="$(mktemp)"
      local source_count=0
      while IFS=$'\t' read -r _skill source path; do
        printf '{"source":%s,"path":%s}\n' \
          "$(json_string "$source")" \
          "$(json_string "$path")" >> "$temp_skill_json"
        source_count=$((source_count + 1))
      done < <(awk -F '\t' -v skill="$skill" '$1 == skill { print $1 "\t" $2 "\t" $3 }' "$inventory_file")
      printf '{"skill":%s,"sources":%s}\n' \
        "$(json_string "$skill")" \
        "$(json_file_array "$temp_skill_json")" >> "$skills_json"
      if [ "$source_count" -gt 1 ]; then
        printf '{"skill":%s,"sources":%s}\n' \
          "$(json_string "$skill")" \
          "$(json_file_array "$temp_skill_json")" >> "$conflicts_json"
      fi
      rm -f "$temp_skill_json"
    done < <(cut -f1 "$inventory_file" | sort -u)
  fi

  printf '{\n'
  printf '  "action": "inventory",\n'
  printf '  "generated_at": %s,\n' "$(json_string "$GENERATED_AT")"
  printf '  "source_roots": %s,\n' "$(render_source_roots_json "$sources_file")"
  printf '  "skill_count": %s,\n' "$(wc -l < "$skills_json" | awk '{print $1}')"
  printf '  "skills": %s,\n' "$(json_file_array "$skills_json")"
  printf '  "conflicts": %s,\n' "$(json_file_array "$conflicts_json")"
  printf '  "source_counts": %s\n' "$(render_source_counts_json "$sources_file" "$inventory_file")"
  printf '}\n'

  rm -f "$skills_json" "$conflicts_json"
}

render_plan_json() {
  local action_name="$1"
  local scope="$2"
  local tools_file="$3"
  local skills_file="$4"
  local sources_file="$5"
  local inventory_file="$6"
  local conflicts_json="$7"
  local actions_tsv="$8"
  local summary_json="$9"

  local actions_json source_selection_json
  actions_json="$(mktemp)"
  source_selection_json="$(mktemp)"

  if [ -f "$actions_tsv" ] && [ -s "$actions_tsv" ]; then
    while IFS="$FIELD_SEP" read -r kind tool scope_name skill source source_path path current_target reason; do
      printf '{"kind":%s,"tool":%s,"scope":%s' \
        "$(json_string "$kind")" \
        "$(json_string "$tool")" \
        "$(json_string "$scope_name")" >> "$actions_json"
      if [ -n "$skill" ]; then
        printf ',"skill":%s' "$(json_string "$skill")" >> "$actions_json"
      fi
      if [ -n "$source" ]; then
        printf ',"source":%s' "$(json_string "$source")" >> "$actions_json"
      fi
      if [ -n "$source_path" ]; then
        printf ',"source_path":%s' "$(json_string "$source_path")" >> "$actions_json"
      fi
      printf ',"path":%s' "$(json_string "$path")" >> "$actions_json"
      if [ -n "$current_target" ]; then
        printf ',"current_target":%s' "$(json_string "$current_target")" >> "$actions_json"
      fi
      if [ -n "$reason" ]; then
        printf ',"reason":%s' "$(json_string "$reason")" >> "$actions_json"
      fi
      local command
      command="$(command_for_action "$kind" "$path" "$source_path")"
      if [ -n "$command" ]; then
        printf ',"command":%s' "$(json_string "$command")" >> "$actions_json"
      else
        printf ',"command":null' >> "$actions_json"
      fi
      printf '}\n' >> "$actions_json"
    done < "$actions_tsv"
  fi

  if [ -f "$actions_tsv" ] && [ -s "$actions_tsv" ]; then
    awk -v FS="$FIELD_SEP" -v sep="$FIELD_SEP" '
      $4 != "" && $5 != "" && !seen[$4]++ {
        printf "%s%s%s\n", $4, sep, $5
      }
    ' "$actions_tsv" | while IFS="$FIELD_SEP" read -r skill source; do
      printf '%s%s%s\n' "$skill" "$FIELD_SEP" "$source" >> "$source_selection_json"
    done
  fi

  printf '{\n'
  printf '  "action": %s,\n' "$(json_string "$action_name")"
  printf '  "generated_at": %s,\n' "$(json_string "$GENERATED_AT")"
  printf '  "source_roots": %s,\n' "$(render_source_roots_json "$sources_file")"
  printf '  "scope": %s,\n' "$(json_string "$scope")"
  printf '  "tools": %s,\n' "$(json_string_file_array "$tools_file")"
  printf '  "skills": %s' "$(json_string_file_array "$skills_file")"
  if [ "$action_name" != 'remove' ]; then
    printf ',\n'
    printf '  "inventory_size": %s,\n' "$(cut -f1 "$inventory_file" 2>/dev/null | sort -u | awk 'NF { count++ } END { print count + 0 }')"
    printf '  "conflicts": %s,\n' "$(json_file_array "$conflicts_json")"
  else
    printf ',\n'
  fi
  printf '  "actions": %s,\n' "$(json_file_array "$actions_json")"
  printf '  "summary": %s' "$(cat "$summary_json")"
  if [ "$action_name" = 'sync' ]; then
    printf ',\n'
    printf '  "source_selection": {\n'
    if [ -f "$source_selection_json" ] && [ -s "$source_selection_json" ]; then
      awk -v FS="$FIELD_SEP" '
        NR > 1 { printf ",\n" }
        {
          skill = $1
          source = $2
          gsub(/\\/,"\\\\",skill); gsub(/"/,"\\\"",skill)
          gsub(/\\/,"\\\\",source); gsub(/"/,"\\\"",source)
          printf "    \"%s\": \"%s\"", skill, source
        }
      ' "$source_selection_json"
      printf '\n'
    fi
    printf '  }\n'
  else
    printf '\n'
  fi
  printf '}\n'

  rm -f "$actions_json" "$source_selection_json"
}

render_status_json() {
  local scope="$1"
  local tools_file="$2"
  local skills_file="$3"
  local sources_file="$4"
  local inventory_file="$5"
  local conflicts_json="$6"
  local rows_tsv="$7"
  local summary_json="$8"

  local rows_json
  rows_json="$(mktemp)"
  while IFS="$FIELD_SEP" read -r tool scope_name skill state path source source_path current_target; do
    printf '{"tool":%s,"scope":%s,"skill":%s,"state":%s,"path":%s' \
      "$(json_string "$tool")" \
      "$(json_string "$scope_name")" \
      "$(json_string "$skill")" \
      "$(json_string "$state")" \
      "$(json_string "$path")" >> "$rows_json"
    if [ -n "$source" ]; then
      printf ',"source":%s' "$(json_string "$source")" >> "$rows_json"
    else
      printf ',"source":null' >> "$rows_json"
    fi
    if [ -n "$source_path" ]; then
      printf ',"source_path":%s' "$(json_string "$source_path")" >> "$rows_json"
    else
      printf ',"source_path":null' >> "$rows_json"
    fi
    if [ -n "$current_target" ]; then
      printf ',"current_target":%s' "$(json_string "$current_target")" >> "$rows_json"
    else
      printf ',"current_target":null' >> "$rows_json"
    fi
    printf '}\n' >> "$rows_json"
  done < "$rows_tsv"

  printf '{\n'
  printf '  "action": "status",\n'
  printf '  "generated_at": %s,\n' "$(json_string "$GENERATED_AT")"
  printf '  "source_roots": %s,\n' "$(render_source_roots_json "$sources_file")"
  printf '  "scope": %s,\n' "$(json_string "$scope")"
  printf '  "tools": %s,\n' "$(json_string_file_array "$tools_file")"
  printf '  "skills": %s,\n' "$(json_string_file_array "$skills_file")"
  printf '  "inventory_size": %s,\n' "$(cut -f1 "$inventory_file" 2>/dev/null | sort -u | awk 'NF { count++ } END { print count + 0 }')"
  printf '  "conflicts": %s,\n' "$(json_file_array "$conflicts_json")"
  printf '  "rows": %s,\n' "$(json_file_array "$rows_json")"
  printf '  "summary": %s,\n' "$(cat "$summary_json")"
  render_missing_by_tool "$rows_tsv"
  printf ',\n'
  render_stale_by_tool "$rows_tsv"
  printf ',\n'
  render_rows_by_tool "$rows_tsv"
  printf '\n}\n'

  rm -f "$rows_json"
}

render_missing_by_tool() {
  local rows_tsv="$1"
  printf '  "missing_by_tool": {'
  local emitted=0 key skills_json
  while IFS= read -r key; do
    skills_json="$(mktemp)"
    awk -v FS="$FIELD_SEP" -v key="$key" '
      ($1 ":" $2) == key && $4 == "missing" { print $3 }
    ' "$rows_tsv" | sort -u | while IFS= read -r skill; do
      printf '%s\n' "$(json_string "$skill")" >> "$skills_json"
    done
    [ "$emitted" -eq 1 ] && printf ','
    printf '\n    %s: %s' "$(json_string "$key")" "$(json_file_array "$skills_json")"
    emitted=1
    rm -f "$skills_json"
  done < <(awk -v FS="$FIELD_SEP" '$4 == "missing" { print $1 ":" $2 }' "$rows_tsv" | sort -u)
  if [ "$emitted" -eq 1 ]; then
    printf '\n  }'
  else
    printf '}'
  fi
}

render_stale_by_tool() {
  local rows_tsv="$1"
  printf '  "stale_by_tool": {'
  local emitted=0 key skills_json
  while IFS= read -r key; do
    skills_json="$(mktemp)"
    awk -v FS="$FIELD_SEP" -v key="$key" '
      ($1 ":" $2) == key && $4 == "stale" { print $3 }
    ' "$rows_tsv" | sort -u | while IFS= read -r skill; do
      printf '%s\n' "$(json_string "$skill")" >> "$skills_json"
    done
    [ "$emitted" -eq 1 ] && printf ','
    printf '\n    %s: %s' "$(json_string "$key")" "$(json_file_array "$skills_json")"
    emitted=1
    rm -f "$skills_json"
  done < <(awk -v FS="$FIELD_SEP" '$4 == "stale" { print $1 ":" $2 }' "$rows_tsv" | sort -u)
  if [ "$emitted" -eq 1 ]; then
    printf '\n  }'
  else
    printf '}'
  fi
}

render_rows_by_tool() {
  local rows_tsv="$1"
  printf '  "rows_by_tool": {'
  local emitted=0 key rows_json
  while IFS= read -r key; do
    rows_json="$(mktemp)"
    awk -v FS="$FIELD_SEP" -v key="$key" '
      ($1 ":" $2) == key {
        print $0
      }
    ' "$rows_tsv" | sort -t "$FIELD_SEP" -k3,3 | while IFS="$FIELD_SEP" read -r tool scope_name skill state path source source_path current_target; do
      printf '{"tool":%s,"scope":%s,"skill":%s,"state":%s,"path":%s' \
        "$(json_string "$tool")" \
        "$(json_string "$scope_name")" \
        "$(json_string "$skill")" \
        "$(json_string "$state")" \
        "$(json_string "$path")" >> "$rows_json"
      if [ -n "$source" ]; then
        printf ',"source":%s' "$(json_string "$source")" >> "$rows_json"
      else
        printf ',"source":null' >> "$rows_json"
      fi
      if [ -n "$source_path" ]; then
        printf ',"source_path":%s' "$(json_string "$source_path")" >> "$rows_json"
      else
        printf ',"source_path":null' >> "$rows_json"
      fi
      if [ -n "$current_target" ]; then
        printf ',"current_target":%s' "$(json_string "$current_target")" >> "$rows_json"
      else
        printf ',"current_target":null' >> "$rows_json"
      fi
      printf '}\n' >> "$rows_json"
    done
    [ "$emitted" -eq 1 ] && printf ','
    printf '\n    %s: %s' "$(json_string "$key")" "$(json_file_array "$rows_json")"
    emitted=1
    rm -f "$rows_json"
  done < <(awk -v FS="$FIELD_SEP" '{ print $1 ":" $2 }' "$rows_tsv" | sort -u)
  if [ "$emitted" -eq 1 ]; then
    printf '\n  }'
  else
    printf '}'
  fi
}

build_summary_json() {
  local output_file="$1"
  shift
  printf '{' > "$output_file"
  local first=1 item key value
  for item in "$@"; do
    key="${item%%=*}"
    value="${item#*=}"
    [ "$first" -eq 0 ] && printf ',' >> "$output_file"
    printf '"%s":%s' "$key" "$value" >> "$output_file"
    first=0
  done
  printf '}' >> "$output_file"
}

run_inventory() {
  local sources_file inventory_file
  sources_file="$(mktemp)"
  inventory_file="$(mktemp)"
  parse_sources_to_file "${SOURCES_RAW:-}" "$sources_file"
  build_source_inventory "$sources_file" "$inventory_file"
  render_inventory_json "$sources_file" "$inventory_file" | if [ -n "${OUTPUT_FILE:-}" ]; then tee "$OUTPUT_FILE"; else cat; fi
  rm -f "$sources_file" "$inventory_file"
}

run_plan_sync() {
  local sources_file inventory_file tools_file skills_file source_choice_file roots_file conflicts_json actions_tsv summary_json created_dirs_file
  sources_file="$(mktemp)"
  inventory_file="$(mktemp)"
  tools_file="$(mktemp)"
  skills_file="$(mktemp)"
  source_choice_file="$(mktemp)"
  roots_file="$(mktemp)"
  conflicts_json="$(mktemp)"
  actions_tsv="$(mktemp)"
  summary_json="$(mktemp)"
  created_dirs_file="$(mktemp)"
  : > "$conflicts_json"
  : > "$actions_tsv"
  : > "$created_dirs_file"

  parse_sources_to_file "${SOURCES_RAW:-}" "$sources_file"
  build_source_inventory "$sources_file" "$inventory_file"
  parse_tools_to_file "$TOOLS_RAW" "$tools_file"
  resolve_skills_to_file "${SKILLS_RAW:-}" "$inventory_file" "$skills_file"
  if [ "${#SOURCE_CHOICES[@]}" -gt 0 ]; then
    parse_source_choices_to_file "$source_choice_file" "${SOURCE_CHOICES[@]}"
  else
    parse_source_choices_to_file "$source_choice_file"
  fi
  build_target_roots "$SCOPE" "$tools_file" "${PROJECT_ROOT:-}" "$roots_file"

  local mkdir_count=0 link_count=0 relink_count=0 already_correct_count=0 skipped_count=0 covered_external_count=0 unlink_redundant_count=0
  local skill candidate_count selected_source chosen_source chosen_path chosen_resolved
  while IFS= read -r skill; do
    [ -n "$skill" ] || continue
    candidate_count="$(awk -F '\t' -v skill="$skill" '$1 == skill { count++ } END { print count + 0 }' "$inventory_file")"
    if [ "$candidate_count" -eq 0 ]; then
      printf '{"skill":%s,"reason":"missing-from-source-inventory"}\n' "$(json_string "$skill")" >> "$conflicts_json"
      continue
    fi

    selected_source="$(selected_source_for_skill "$skill" "$source_choice_file")"
    if [ "$candidate_count" -gt 1 ] && [ -z "$selected_source" ]; then
      printf '{"skill":%s,"reason":"source-choice-required","options":%s}\n' \
        "$(json_string "$skill")" \
        "$(options_json_for_skill "$skill" "$inventory_file")" >> "$conflicts_json"
      continue
    fi

    if [ "$candidate_count" -eq 1 ]; then
      chosen_source="$(awk -F '\t' -v skill="$skill" '$1 == skill { print $2; exit }' "$inventory_file")"
      chosen_path="$(awk -F '\t' -v skill="$skill" '$1 == skill { print $3; exit }' "$inventory_file")"
    else
      chosen_source="$selected_source"
      chosen_path="$(awk -F '\t' -v skill="$skill" -v source="$chosen_source" '$1 == skill && $2 == source { print $3; exit }' "$inventory_file")"
      if [ -z "$chosen_path" ]; then
        printf '{"skill":%s,"reason":"invalid-source-choice","selected":%s,"options":%s}\n' \
          "$(json_string "$skill")" \
          "$(json_string "$chosen_source")" \
          "$(options_json_for_skill "$skill" "$inventory_file")" >> "$conflicts_json"
        continue
      fi
    fi

    if [ ! -d "$chosen_path" ]; then
      printf '{"skill":%s,"reason":"selected-source-path-is-invalid","source":%s,"path":%s}\n' \
        "$(json_string "$skill")" \
        "$(json_string "$chosen_source")" \
        "$(json_string "$chosen_path")" >> "$conflicts_json"
      continue
    fi
    chosen_resolved="$(canonical_dir "$chosen_path")"

    while IFS=$'\t' read -r tool scope_name skills_dir; do
      local target current_target resolved_target
      target="${skills_dir%/}/$skill"
      if [ ! -d "$skills_dir" ] && ! created_dir_recorded "$skills_dir" "$created_dirs_file"; then
        printf '%s\n' "$skills_dir" >> "$created_dirs_file"
        printf '%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n' \
          "mkdir" "$FIELD_SEP" "$tool" "$FIELD_SEP" "$scope_name" "$FIELD_SEP" "" "$FIELD_SEP" "" "$FIELD_SEP" "" "$FIELD_SEP" "$skills_dir" "$FIELD_SEP" "" "$FIELD_SEP" "" >> "$actions_tsv"
        mkdir_count=$((mkdir_count + 1))
      fi
      if tool_loads_source_externally "$tool" "$chosen_source"; then
        if [ -L "$target" ]; then
          resolved_target="$(resolved_symlink_dir "$target")"
          current_target="${resolved_target:-}"
          printf '%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n' \
            "unlink" "$FIELD_SEP" "$tool" "$FIELD_SEP" "$scope_name" "$FIELD_SEP" "$skill" "$FIELD_SEP" "$chosen_source" "$FIELD_SEP" "$chosen_resolved" "$FIELD_SEP" "$target" "$FIELD_SEP" "$current_target" "$FIELD_SEP" "redundant-because-source-is-loaded-externally" >> "$actions_tsv"
          unlink_redundant_count=$((unlink_redundant_count + 1))
        elif [ -e "$target" ]; then
          printf '%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n' \
            "skip-non-symlink" "$FIELD_SEP" "$tool" "$FIELD_SEP" "$scope_name" "$FIELD_SEP" "$skill" "$FIELD_SEP" "" "$FIELD_SEP" "" "$FIELD_SEP" "$target" "$FIELD_SEP" "" "$FIELD_SEP" "target-exists-and-is-not-a-symlink" >> "$actions_tsv"
          skipped_count=$((skipped_count + 1))
        else
          printf '%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n' \
            "covered-by-external-source" "$FIELD_SEP" "$tool" "$FIELD_SEP" "$scope_name" "$FIELD_SEP" "$skill" "$FIELD_SEP" "$chosen_source" "$FIELD_SEP" "$chosen_resolved" "$FIELD_SEP" "$target" "$FIELD_SEP" "" "$FIELD_SEP" "source-is-loaded-externally-by-tool" >> "$actions_tsv"
          covered_external_count=$((covered_external_count + 1))
        fi
      elif [ -L "$target" ]; then
        resolved_target="$(resolved_symlink_dir "$target")"
        if [ "$resolved_target" = "$chosen_resolved" ]; then
          printf '%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n' \
            "already-correct" "$FIELD_SEP" "$tool" "$FIELD_SEP" "$scope_name" "$FIELD_SEP" "$skill" "$FIELD_SEP" "$chosen_source" "$FIELD_SEP" "$chosen_resolved" "$FIELD_SEP" "$target" "$FIELD_SEP" "" "$FIELD_SEP" "" >> "$actions_tsv"
          already_correct_count=$((already_correct_count + 1))
        else
          current_target="${resolved_target:-}"
          printf '%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n' \
            "relink" "$FIELD_SEP" "$tool" "$FIELD_SEP" "$scope_name" "$FIELD_SEP" "$skill" "$FIELD_SEP" "$chosen_source" "$FIELD_SEP" "$chosen_resolved" "$FIELD_SEP" "$target" "$FIELD_SEP" "$current_target" "$FIELD_SEP" "" >> "$actions_tsv"
          relink_count=$((relink_count + 1))
        fi
      elif [ -e "$target" ]; then
        printf '%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n' \
          "skip-non-symlink" "$FIELD_SEP" "$tool" "$FIELD_SEP" "$scope_name" "$FIELD_SEP" "$skill" "$FIELD_SEP" "" "$FIELD_SEP" "" "$FIELD_SEP" "$target" "$FIELD_SEP" "" "$FIELD_SEP" "target-exists-and-is-not-a-symlink" >> "$actions_tsv"
        skipped_count=$((skipped_count + 1))
      else
        printf '%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n' \
          "link" "$FIELD_SEP" "$tool" "$FIELD_SEP" "$scope_name" "$FIELD_SEP" "$skill" "$FIELD_SEP" "$chosen_source" "$FIELD_SEP" "$chosen_resolved" "$FIELD_SEP" "$target" "$FIELD_SEP" "" "$FIELD_SEP" "" >> "$actions_tsv"
        link_count=$((link_count + 1))
      fi
    done < "$roots_file"
  done < "$skills_file"

  # Detect stale/orphaned symlinks (source skill was removed)
  local stale_count=0
  while IFS=$'\t' read -r tool scope_name skills_dir; do
    [ -d "$skills_dir" ] || continue
    while IFS= read -r symlink_path; do
      [ -L "$symlink_path" ] || continue
      local skill_name original_target
      skill_name="$(basename "$symlink_path")"
      if grep -Fqx "$skill_name" "$skills_file" 2>/dev/null; then
        continue
      fi
      if [ ! -e "$symlink_path" ]; then
        original_target="$(readlink "$symlink_path" 2>/dev/null || true)"
        printf '%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n' \
          "unlink" "$FIELD_SEP" "$tool" "$FIELD_SEP" "$scope_name" "$FIELD_SEP" "$skill_name" "$FIELD_SEP" "" "$FIELD_SEP" "" "$FIELD_SEP" "$symlink_path" "$FIELD_SEP" "$original_target" "$FIELD_SEP" "stale-source-skill-removed" >> "$actions_tsv"
        stale_count=$((stale_count + 1))
      fi
    done < <(find "$skills_dir" -mindepth 1 -maxdepth 1 -type l 2>/dev/null | sort)
  done < "$roots_file"

  build_summary_json "$summary_json" \
    "mkdir=$mkdir_count" \
    "link=$link_count" \
    "relink=$relink_count" \
    "already_correct=$already_correct_count" \
    "covered_by_external_source=$covered_external_count" \
    "unlink_redundant_external=$unlink_redundant_count" \
    "skipped=$skipped_count" \
    "stale_unlink=$stale_count"

  if [ -n "${OUTPUT_FILE:-}" ]; then
    : > "$OUTPUT_FILE"
    append_meta_record "$OUTPUT_FILE" "planned_action" "sync"
    append_meta_record "$OUTPUT_FILE" "generated_at" "$GENERATED_AT"
    awk -v sep="$FIELD_SEP" '{ print "ACTION" sep $0 }' "$actions_tsv" >> "$OUTPUT_FILE"
  fi

  render_plan_json "sync" "$SCOPE" "$tools_file" "$skills_file" "$sources_file" "$inventory_file" "$conflicts_json" "$actions_tsv" "$summary_json"

  rm -f "$sources_file" "$inventory_file" "$tools_file" "$skills_file" "$source_choice_file" "$roots_file" "$conflicts_json" "$actions_tsv" "$summary_json" "$created_dirs_file"
}

run_plan_remove() {
  local sources_file inventory_file tools_file skills_file roots_file actions_tsv summary_json
  sources_file="$(mktemp)"
  inventory_file="$(mktemp)"
  tools_file="$(mktemp)"
  skills_file="$(mktemp)"
  roots_file="$(mktemp)"
  actions_tsv="$(mktemp)"
  summary_json="$(mktemp)"
  : > "$actions_tsv"

  parse_sources_to_file "${SOURCES_RAW:-}" "$sources_file"
  build_source_inventory "$sources_file" "$inventory_file"
  parse_tools_to_file "$TOOLS_RAW" "$tools_file"
  resolve_skills_to_file "$SKILLS_RAW" "$inventory_file" "$skills_file"
  [ -s "$skills_file" ] || die "--skills must not be empty for plan-remove"
  build_target_roots "$SCOPE" "$tools_file" "${PROJECT_ROOT:-}" "$roots_file"

  local unlink_count=0 absent_count=0 skipped_count=0 skill
  while IFS= read -r skill; do
    [ -n "$skill" ] || continue
    while IFS=$'\t' read -r tool scope_name skills_dir; do
      local target
      target="${skills_dir%/}/$skill"
      if [ -L "$target" ]; then
        printf '%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n' \
          "unlink" "$FIELD_SEP" "$tool" "$FIELD_SEP" "$scope_name" "$FIELD_SEP" "$skill" "$FIELD_SEP" "" "$FIELD_SEP" "" "$FIELD_SEP" "$target" "$FIELD_SEP" "" "$FIELD_SEP" "" >> "$actions_tsv"
        unlink_count=$((unlink_count + 1))
      elif [ -e "$target" ]; then
        printf '%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n' \
          "skip-non-symlink" "$FIELD_SEP" "$tool" "$FIELD_SEP" "$scope_name" "$FIELD_SEP" "$skill" "$FIELD_SEP" "" "$FIELD_SEP" "" "$FIELD_SEP" "$target" "$FIELD_SEP" "" "$FIELD_SEP" "target-exists-and-is-not-a-symlink" >> "$actions_tsv"
        skipped_count=$((skipped_count + 1))
      else
        printf '%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n' \
          "absent" "$FIELD_SEP" "$tool" "$FIELD_SEP" "$scope_name" "$FIELD_SEP" "$skill" "$FIELD_SEP" "" "$FIELD_SEP" "" "$FIELD_SEP" "$target" "$FIELD_SEP" "" "$FIELD_SEP" "" >> "$actions_tsv"
        absent_count=$((absent_count + 1))
      fi
    done < "$roots_file"
  done < "$skills_file"

  build_summary_json "$summary_json" \
    "unlink=$unlink_count" \
    "absent=$absent_count" \
    "skipped=$skipped_count"

  if [ -n "${OUTPUT_FILE:-}" ]; then
    : > "$OUTPUT_FILE"
    append_meta_record "$OUTPUT_FILE" "planned_action" "remove"
    append_meta_record "$OUTPUT_FILE" "generated_at" "$GENERATED_AT"
    awk -v sep="$FIELD_SEP" '{ print "ACTION" sep $0 }' "$actions_tsv" >> "$OUTPUT_FILE"
  fi

  render_plan_json "remove" "$SCOPE" "$tools_file" "$skills_file" "$sources_file" /dev/null /dev/null "$actions_tsv" "$summary_json"

  rm -f "$sources_file" "$inventory_file" "$tools_file" "$skills_file" "$roots_file" "$actions_tsv" "$summary_json"
}

run_plan_status() {
  local sources_file inventory_file tools_file skills_file source_choice_file roots_file conflicts_json rows_tsv summary_json
  sources_file="$(mktemp)"
  inventory_file="$(mktemp)"
  tools_file="$(mktemp)"
  skills_file="$(mktemp)"
  source_choice_file="$(mktemp)"
  roots_file="$(mktemp)"
  conflicts_json="$(mktemp)"
  rows_tsv="$(mktemp)"
  summary_json="$(mktemp)"
  : > "$conflicts_json"
  : > "$rows_tsv"

  parse_sources_to_file "${SOURCES_RAW:-}" "$sources_file"
  build_source_inventory "$sources_file" "$inventory_file"
  parse_tools_to_file "$TOOLS_RAW" "$tools_file"
  resolve_skills_to_file "${SKILLS_RAW:-}" "$inventory_file" "$skills_file"
  if [ "${#SOURCE_CHOICES[@]}" -gt 0 ]; then
    parse_source_choices_to_file "$source_choice_file" "${SOURCE_CHOICES[@]}"
  else
    parse_source_choices_to_file "$source_choice_file"
  fi
  build_target_roots "$SCOPE" "$tools_file" "${PROJECT_ROOT:-}" "$roots_file"

  local missing_count=0 linked_correctly_count=0 linked_different_count=0 occupied_count=0 unknown_count=0 covered_external_count=0 linked_external_count=0
  local skill candidate_count selected_source chosen_source chosen_path chosen_resolved
  while IFS= read -r skill; do
    [ -n "$skill" ] || continue
    candidate_count="$(awk -F '\t' -v skill="$skill" '$1 == skill { count++ } END { print count + 0 }' "$inventory_file")"
    selected_source="$(selected_source_for_skill "$skill" "$source_choice_file")"
    chosen_source=""
    chosen_path=""
    if [ "$candidate_count" -eq 0 ]; then
      :
    elif [ "$candidate_count" -eq 1 ]; then
      chosen_source="$(awk -F '\t' -v skill="$skill" '$1 == skill { print $2; exit }' "$inventory_file")"
      chosen_path="$(awk -F '\t' -v skill="$skill" '$1 == skill { print $3; exit }' "$inventory_file")"
    elif [ -z "$selected_source" ]; then
      printf '{"skill":%s,"reason":"source-choice-required","options":%s}\n' \
        "$(json_string "$skill")" \
        "$(options_json_for_skill "$skill" "$inventory_file")" >> "$conflicts_json"
    else
      chosen_source="$selected_source"
      chosen_path="$(awk -F '\t' -v skill="$skill" -v source="$chosen_source" '$1 == skill && $2 == source { print $3; exit }' "$inventory_file")"
      if [ -z "$chosen_path" ]; then
        printf '{"skill":%s,"reason":"invalid-source-choice","selected":%s,"options":%s}\n' \
          "$(json_string "$skill")" \
          "$(json_string "$chosen_source")" \
          "$(options_json_for_skill "$skill" "$inventory_file")" >> "$conflicts_json"
        chosen_source=""
      fi
    fi
    chosen_resolved=""
    if [ -n "$chosen_path" ] && [ -d "$chosen_path" ]; then
      chosen_resolved="$(canonical_dir "$chosen_path")"
    fi

    while IFS=$'\t' read -r tool scope_name skills_dir; do
      local target state current_target
      target="${skills_dir%/}/$skill"
      current_target=""
      if [ -z "$chosen_resolved" ]; then
        state="unknown-source"
        unknown_count=$((unknown_count + 1))
      elif [ -L "$target" ]; then
        current_target="$(resolved_symlink_dir "$target")"
        if [ "$current_target" = "$chosen_resolved" ]; then
          if tool_loads_source_externally "$tool" "$chosen_source"; then
            state="linked-correctly-but-externally-covered"
            linked_external_count=$((linked_external_count + 1))
          else
            state="linked-correctly"
            linked_correctly_count=$((linked_correctly_count + 1))
          fi
        else
          state="linked-to-different-source"
          linked_different_count=$((linked_different_count + 1))
        fi
      elif [ -e "$target" ]; then
        state="occupied-by-real-path"
        occupied_count=$((occupied_count + 1))
      elif tool_loads_source_externally "$tool" "$chosen_source"; then
        state="covered-by-external-source"
        covered_external_count=$((covered_external_count + 1))
      else
        state="missing"
        missing_count=$((missing_count + 1))
      fi
      printf '%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n' \
        "$tool" "$FIELD_SEP" "$scope_name" "$FIELD_SEP" "$skill" "$FIELD_SEP" "$state" "$FIELD_SEP" "$target" "$FIELD_SEP" "$chosen_source" "$FIELD_SEP" "$chosen_resolved" "$FIELD_SEP" "$current_target" >> "$rows_tsv"
    done < "$roots_file"
  done < "$skills_file"

  # Detect stale/orphaned symlinks (source skill was removed)
  local stale_count=0
  while IFS=$'\t' read -r tool scope_name skills_dir; do
    [ -d "$skills_dir" ] || continue
    while IFS= read -r symlink_path; do
      [ -L "$symlink_path" ] || continue
      local skill_name original_target
      skill_name="$(basename "$symlink_path")"
      if grep -Fqx "$skill_name" "$skills_file" 2>/dev/null; then
        continue
      fi
      if [ ! -e "$symlink_path" ]; then
        original_target="$(readlink "$symlink_path" 2>/dev/null || true)"
        printf '%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n' \
          "$tool" "$FIELD_SEP" "$scope_name" "$FIELD_SEP" "$skill_name" "$FIELD_SEP" "stale" "$FIELD_SEP" "$symlink_path" "$FIELD_SEP" "" "$FIELD_SEP" "" "$FIELD_SEP" "$original_target" >> "$rows_tsv"
        stale_count=$((stale_count + 1))
      fi
    done < <(find "$skills_dir" -mindepth 1 -maxdepth 1 -type l 2>/dev/null | sort)
  done < "$roots_file"

  build_summary_json "$summary_json" \
    "missing=$missing_count" \
    "linked-correctly=$linked_correctly_count" \
    "linked-correctly-but-externally-covered=$linked_external_count" \
    "covered-by-external-source=$covered_external_count" \
    "linked-to-different-source=$linked_different_count" \
    "occupied-by-real-path=$occupied_count" \
    "unknown-source=$unknown_count" \
    "stale=$stale_count"

  if [ -n "${OUTPUT_FILE:-}" ]; then
    render_status_json "$SCOPE" "$tools_file" "$skills_file" "$sources_file" "$inventory_file" "$conflicts_json" "$rows_tsv" "$summary_json" | tee "$OUTPUT_FILE"
  else
    render_status_json "$SCOPE" "$tools_file" "$skills_file" "$sources_file" "$inventory_file" "$conflicts_json" "$rows_tsv" "$summary_json"
  fi

  rm -f "$sources_file" "$inventory_file" "$tools_file" "$skills_file" "$source_choice_file" "$roots_file" "$conflicts_json" "$rows_tsv" "$summary_json"
}

run_apply() {
  local plan_file="$PLAN_FILE"
  [ -f "$plan_file" ] || die "Plan file not found: $plan_file"

  local sources_file actions_tsv summary_json results_json planned_action
  sources_file="$(mktemp)"
  actions_tsv="$(mktemp)"
  summary_json="$(mktemp)"
  results_json="$(mktemp)"
  : > "$actions_tsv"
  : > "$results_json"
  list_source_keys > "$sources_file"

  planned_action="$(awk -v FS="$FIELD_SEP" '$1 == "META" && $2 == "planned_action" { print $3; exit }' "$plan_file")"
  awk -v FS="$FIELD_SEP" -v OFS="$FIELD_SEP" '
    $1 == "ACTION" {
      for (i = 2; i <= NF; i++) {
        if (i > 2) {
          printf "%s", OFS
        }
        printf "%s", $i
      }
      printf "\n"
    }
  ' "$plan_file" > "$actions_tsv"

  local ok_count=0 not_executed_count=0 failed_count=0 ignored_count=0
  while IFS="$FIELD_SEP" read -r kind tool scope_name skill source source_path path current_target reason; do
    local status reason_out command
    status=""
    reason_out="$reason"
    command="$(command_for_action "$kind" "$path" "$source_path")"
    case "$kind" in
      already-correct|absent|skip-non-symlink|covered-by-external-source)
        status="not-executed"
        not_executed_count=$((not_executed_count + 1))
        ;;
      mkdir)
        mkdir -p "$path"
        status="ok"
        ok_count=$((ok_count + 1))
        ;;
      link)
        if [ ! -d "$source_path" ]; then
          status="failed"
          reason_out="source-path-is-invalid"
          failed_count=$((failed_count + 1))
        elif [ -e "$path" ] || [ -L "$path" ]; then
          status="failed"
          reason_out="target-already-exists"
          failed_count=$((failed_count + 1))
        else
          mkdir -p "$(dirname "$path")"
          ln -s "$source_path" "$path"
          status="ok"
          ok_count=$((ok_count + 1))
        fi
        ;;
      relink)
        if [ ! -d "$source_path" ]; then
          status="failed"
          reason_out="source-path-is-invalid"
          failed_count=$((failed_count + 1))
        elif [ ! -L "$path" ]; then
          status="failed"
          reason_out="target-is-not-symlink"
          failed_count=$((failed_count + 1))
        else
          unlink "$path"
          ln -s "$source_path" "$path"
          status="ok"
          ok_count=$((ok_count + 1))
        fi
        ;;
      unlink)
        if [ ! -L "$path" ]; then
          status="failed"
          reason_out="target-is-not-symlink"
          failed_count=$((failed_count + 1))
        else
          unlink "$path"
          status="ok"
          ok_count=$((ok_count + 1))
        fi
        ;;
      *)
        status="ignored"
        reason_out="unknown-kind"
        ignored_count=$((ignored_count + 1))
        ;;
    esac

    printf '{"kind":%s,"tool":%s,"scope":%s' \
      "$(json_string "$kind")" \
      "$(json_string "$tool")" \
      "$(json_string "$scope_name")" >> "$results_json"
    if [ -n "$skill" ]; then
      printf ',"skill":%s' "$(json_string "$skill")" >> "$results_json"
    fi
    if [ -n "$source" ]; then
      printf ',"source":%s' "$(json_string "$source")" >> "$results_json"
    fi
    if [ -n "$source_path" ]; then
      printf ',"source_path":%s' "$(json_string "$source_path")" >> "$results_json"
    fi
    printf ',"path":%s' "$(json_string "$path")" >> "$results_json"
    if [ -n "$current_target" ]; then
      printf ',"current_target":%s' "$(json_string "$current_target")" >> "$results_json"
    fi
    if [ -n "$reason_out" ]; then
      printf ',"reason":%s' "$(json_string "$reason_out")" >> "$results_json"
    fi
    if [ -n "$command" ]; then
      printf ',"command":%s' "$(json_string "$command")" >> "$results_json"
    else
      printf ',"command":null' >> "$results_json"
    fi
    printf ',"status":%s}\n' "$(json_string "$status")" >> "$results_json"
  done < "$actions_tsv"

  build_summary_json "$summary_json" \
    "ok=$ok_count" \
    "not-executed=$not_executed_count" \
    "failed=$failed_count" \
    "ignored=$ignored_count"

  {
    printf '{\n'
    printf '  "action": "apply",\n'
    printf '  "generated_at": %s,\n' "$(json_string "$GENERATED_AT")"
    printf '  "source_roots": %s,\n' "$(render_source_roots_json "$sources_file")"
    printf '  "planned_action": %s,\n' "$(json_string "$planned_action")"
    printf '  "result_count": %s,\n' "$(wc -l < "$results_json" | awk '{print $1}')"
    printf '  "results": %s,\n' "$(json_file_array "$results_json")"
    printf '  "summary": %s\n' "$(cat "$summary_json")"
    printf '}\n'
  } | if [ -n "${OUTPUT_FILE:-}" ]; then tee "$OUTPUT_FILE"; else cat; fi

  rm -f "$sources_file" "$actions_tsv" "$summary_json" "$results_json"
}

COMMAND=""
SCOPE=""
TOOLS_RAW=""
SKILLS_RAW=""
SOURCES_RAW=""
PROJECT_ROOT=""
OUTPUT_FILE=""
PLAN_FILE=""
JSON_OUTPUT=0
SOURCE_CHOICES=()

parse_args() {
  [ $# -ge 1 ] || die "A command is required"
  COMMAND="$1"
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --scope) SCOPE="$2"; shift 2 ;;
      --tools) TOOLS_RAW="$2"; shift 2 ;;
      --skills) SKILLS_RAW="$2"; shift 2 ;;
      --sources) SOURCES_RAW="$2"; shift 2 ;;
      --project-root) PROJECT_ROOT="$2"; shift 2 ;;
      --source-choice) SOURCE_CHOICES+=("$2"); shift 2 ;;
      --output) OUTPUT_FILE="$2"; shift 2 ;;
      --plan) PLAN_FILE="$2"; shift 2 ;;
      --json) JSON_OUTPUT=1; shift ;;
      *) die "Unknown argument: $1" ;;
    esac
  done
}

validate_command_requirements() {
  case "$COMMAND" in
    inventory) ;;
    plan-sync|plan-status)
      [ -n "$SCOPE" ] || die "--scope is required"
      [ -n "$TOOLS_RAW" ] || die "--tools is required"
      ;;
    plan-remove)
      [ -n "$SCOPE" ] || die "--scope is required"
      [ -n "$TOOLS_RAW" ] || die "--tools is required"
      [ -n "$SKILLS_RAW" ] || die "--skills is required"
      ;;
    apply)
      [ -n "$PLAN_FILE" ] || die "--plan is required"
      ;;
    *)
      die "Unsupported command: $COMMAND"
      ;;
  esac
}

main() {
  parse_args "$@"
  load_config
  validate_command_requirements
  GENERATED_AT="$(now_utc)"

  case "$COMMAND" in
    inventory) run_inventory ;;
    plan-sync) run_plan_sync ;;
    plan-remove) run_plan_remove ;;
    plan-status) run_plan_status ;;
    apply) run_apply ;;
  esac
}

main "$@"
