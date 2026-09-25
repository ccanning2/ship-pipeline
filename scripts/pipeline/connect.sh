#!/usr/bin/env bash
# Connects this machine to the code host and the tracker through their CLIs: finds them, installs what is missing,
# and signs in. /pipeline-init runs `status` and `install` itself; `login` needs the owner at a terminal, once,
# because every sign-in is a browser flow or a token only they may type.
# Usage: connect.sh status          one line per tool: "TOOL <name> installed=<yes|no> signed-in=<yes|no|n/a> <note>";
#                                   exits 0 when everything is ready, 4 when a sign-in is missing, 5 when a tool is
#        connect.sh install         installs every missing tool with the OS package manager (winget, brew, apt, dnf)
#                                   or the vendor's download; prints the manual command for anything it cannot
#        connect.sh login           signs in to every tool that is not signed in (interactive: run it in a terminal)
#        connect.sh cloud-id <URL>  prints a Jira site's cloudId
# Tokens are stored in ~/.config/ship-pipeline/<name>.env (mode 600), never in the repository and never echoed.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
[ -f "$here/pipeline.env" ] && source "$here/pipeline.env"
host="$(printf '%s' "${GIT_HOST:-github}" | tr '[:upper:]' '[:lower:]')"
tracker="$(printf '%s' "${TRACKER:-linear}" | tr '[:upper:]' '[:lower:]')"
host_url="${GIT_HOST_URL:-}"; host_url="${host_url%/}"; hostname="$(printf '%s' "$host_url" | sed -E 's#^[a-z]+://##; s#/.*$##')"
site="${TRACKER_URL:-}"; site="${site%/}"
cfg="${PIPELINE_TRACKER_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/ship-pipeline}"
have() { command -v "$1" >/dev/null 2>&1; }

# the tools this project needs, from GIT_HOST and TRACKER
tools=(git jq)
case "$host" in github) tools+=(gh);; gitlab) tools+=(glab);; bitbucket) tools+=(curl bitbucket);; esac
case "$tracker" in
  jira) tools+=(acli curl jira);; linear) tools+=(curl linear);;
  github) printf '%s\n' "${tools[@]}" | grep -qx gh || tools+=(gh);;
  gitlab) printf '%s\n' "${tools[@]}" | grep -qx glab || tools+=(glab);;
esac
tools=($(printf '%s\n' "${tools[@]}" | awk '!seen[$0]++'))

os() { case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) echo windows;; Darwin) echo mac;; *) echo linux;; esac; }
bin_of() { case "$1" in bitbucket|jira|linear) echo "";; *) echo "$1";; esac; }   # token-only "tools" have no binary
installed() { local b; b="$(bin_of "$1")"; [ -z "$b" ] || have "$b" || { [ "$b" = acli ] && have acli.exe; }; }
token_file() { echo "$cfg/$1.env"; }
has_token() { [ -f "$(token_file "$1")" ] && grep -q "=" "$(token_file "$1")"; }
signed_in() { # yes | no | n/a
  case "$1" in
    gh) gh auth status ${hostname:+--hostname "$hostname"} >/dev/null 2>&1 && echo yes || echo no;;
    glab) glab auth status ${hostname:+--hostname "$hostname"} >/dev/null 2>&1 && echo yes || echo no;;
    acli) acli jira auth status >/dev/null 2>&1 && echo yes || echo no;;
    jira) has_token jira || [ -n "${JIRA_API_TOKEN:-}" ] && echo yes || echo no;;
    linear) has_token linear || [ -n "${LINEAR_API_KEY:-}" ] && echo yes || echo no;;
    bitbucket) has_token bitbucket || [ -n "${BITBUCKET_API_TOKEN:-}" ] && echo yes || echo no;;
    *) echo n/a;;
  esac
}
install_cmd() { # the one command that installs <tool> on this OS (empty when there is none)
  local o; o="$(os)"
  case "$1:$o" in
    gh:windows) echo "winget install --id GitHub.cli -e --accept-source-agreements --accept-package-agreements";;
    glab:windows) echo "winget install --id glab.glab -e --accept-source-agreements --accept-package-agreements";;
    jq:windows) echo "winget install --id jqlang.jq -e --accept-source-agreements --accept-package-agreements";;
    acli:windows) echo "mkdir -p \"\$HOME/bin\" && curl -fsSL -o \"\$HOME/bin/acli.exe\" https://acli.atlassian.com/windows/latest/acli_windows_amd64/acli.exe";;
    curl:windows|git:windows) echo "";;
    acli:mac) echo "brew tap atlassian/homebrew-acli && brew install acli";;
    *:mac) echo "brew install $1";;
    acli:linux) have brew && echo "brew tap atlassian/homebrew-acli && brew install acli" \
      || echo "mkdir -p \"\$HOME/.local/bin\" && curl -fsSL -o \"\$HOME/.local/bin/acli\" https://acli.atlassian.com/linux/latest/acli_linux_$( [ "$(uname -m)" = aarch64 ] && echo arm64 || echo amd64)/acli && chmod +x \"\$HOME/.local/bin/acli\"";;
    *:linux)
      if have brew; then echo "brew install $1"
      elif [ "$1" = glab ]; then have snap && echo "sudo snap install glab" || echo ""
      elif have apt-get; then echo "sudo apt-get install -y $1"
      elif have dnf; then echo "sudo dnf install -y $1"; fi;;
  esac
}
login_hint() {
  case "$1" in
    gh) echo "gh auth login ${hostname:+--hostname $hostname }--web --git-protocol https";;
    glab) echo "glab auth login ${hostname:+--hostname $hostname }--web";;
    *) echo "bash scripts/pipeline/connect.sh login";;
  esac
}

status() {
  local t ins sig rc=0
  for t in "${tools[@]}"; do
    [ -n "$(bin_of "$t")" ] || { sig="$(signed_in "$t")"; printf 'TOOL %s installed=n/a signed-in=%s%s\n' "$t" "$sig" "$( [ "$sig" = no ] && echo " (API token needed)")"; [ "$sig" = no ] && [ $rc -eq 0 ] && rc=4; continue; }
    if installed "$t"; then ins=yes; else ins=no; rc=5; fi
    sig="$( [ "$ins" = yes ] && signed_in "$t" || echo no)"; case "$t" in git|jq|curl) sig=n/a;; esac
    printf 'TOOL %s installed=%s signed-in=%s' "$t" "$ins" "$sig"
    [ "$ins" = no ] && printf ' install: %s' "$(install_cmd "$t")"
    [ "$ins" = yes ] && [ "$sig" = no ] && { printf ' login: %s' "$(login_hint "$t")"; [ $rc -eq 0 ] && rc=4; }
    echo
  done
  return $rc
}

install_all() {
  local t c failed=0
  for t in "${tools[@]}"; do
    [ -n "$(bin_of "$t")" ] || continue
    installed "$t" && continue
    c="$(install_cmd "$t")"
    if [ -z "$c" ]; then echo "INSTALL $t: no package manager found; install it by hand"; failed=1; continue; fi
    echo "INSTALL $t: $c"
    # winget exits non-zero when the package is already installed but not on PATH, so the result is judged by
    # whether the tool can be found afterwards, not by the installer's exit code
    bash -c "$c" </dev/null >/dev/null 2>&1 || true
    [ "$(os)" = windows ] && link_winget "$t"
    if installed "$t"; then echo "INSTALLED $t ($(command -v "$(bin_of "$t")"))"
    else echo "FAILED $t (run it yourself: $c)"; failed=1; fi
  done
  return $failed
}
# winget's portable packages (jq, glab, ...) land in %LOCALAPPDATA%\Microsoft\WinGet\Packages and are reachable only
# through a Links shim that is not always on PATH, and never in an already-running shell. Put the exe in ~/bin,
# which Git Bash puts on PATH, and on this shell's PATH now.
link_winget() {
  local t="$1" exe root="${LOCALAPPDATA:-$HOME/AppData/Local}/Microsoft/WinGet"
  installed "$t" && return 0
  exe="$(ls "$root/Links/$t.exe" 2>/dev/null || ls "$root"/Packages/*/"$t.exe" "$root"/Packages/*/*/"$t.exe" 2>/dev/null | head -n 1)"
  [ -n "$exe" ] || return 0
  mkdir -p "$HOME/bin" && cp "$exe" "$HOME/bin/$t.exe" && echo "LINKED $t: $HOME/bin/$t.exe"
  case ":$PATH:" in *":$HOME/bin:"*) ;; *) PATH="$HOME/bin:$PATH";; esac
}

save_token() { # name KEY=value...
  local n="$1"; shift; mkdir -p "$cfg"; chmod 700 "$cfg" 2>/dev/null || true
  local f; f="$(token_file "$n")"; ( umask 077; : > "$f"; for kv in "$@"; do printf '%s=%q\n' "${kv%%=*}" "${kv#*=}" >> "$f"; done )
  echo "saved $f"
}
ask() { local v; read -r -p "$1" v </dev/tty; printf '%s' "$v"; }
ask_secret() { local v; read -r -s -p "$1" v </dev/tty; echo >/dev/tty; printf '%s' "$v"; }
login_all() {
  [ -r /dev/tty ] && { : </dev/tty; } 2>/dev/null || { echo "connect.sh login is interactive: run it in your own terminal:"; echo "  bash scripts/pipeline/connect.sh login"; exit 4; }
  local t e k
  for t in "${tools[@]}"; do
    [ "$(signed_in "$t")" = no ] || continue
    case "$t" in
      gh) echo "== GitHub${hostname:+ ($hostname)}"; gh auth login ${hostname:+--hostname "$hostname"} --web --git-protocol https </dev/tty;;
      glab) echo "== GitLab${hostname:+ ($hostname)}"; glab auth login ${hostname:+--hostname "$hostname"} </dev/tty;;
      jira|acli)
        [ "$t" = acli ] && [ "$(signed_in jira)" = yes ] && { # the saved token signs acli in too
          # shellcheck disable=SC1090
          source "$(token_file jira)"; printf '%s' "$JIRA_API_TOKEN" | acli jira auth login --site "$(printf '%s' "$site" | sed -E 's#^[a-z]+://##')" --email "$JIRA_EMAIL" --token >/dev/null && echo "acli signed in"; continue; }
        [ "$t" = jira ] || continue
        echo "== Jira ($site). Create an API token at https://id.atlassian.com/manage-profile/security/api-tokens"
        e="$(ask "Atlassian account email [$(git config user.email)]: ")"; e="${e:-$(git config user.email)}"
        k="$(ask_secret "API token (hidden): ")"
        save_token jira "JIRA_EMAIL=$e" "JIRA_API_TOKEN=$k"
        if have acli; then printf '%s' "$k" | acli jira auth login --site "$(printf '%s' "$site" | sed -E 's#^[a-z]+://##')" --email "$e" --token >/dev/null && echo "acli signed in"; fi;;
      linear)
        echo "== Linear. Create a personal API key at https://linear.app/settings/account/security"
        k="$(ask_secret "API key (hidden): ")"; save_token linear "LINEAR_API_KEY=$k";;
      bitbucket)
        echo "== Bitbucket. Create an API token with Bitbucket scopes (repositories, pull requests, pipelines) at https://id.atlassian.com/manage-profile/security/api-tokens"
        e="$(ask "Atlassian account email [$(git config user.email)]: ")"; e="${e:-$(git config user.email)}"
        k="$(ask_secret "API token (hidden): ")"; save_token bitbucket "BITBUCKET_EMAIL=$e" "BITBUCKET_API_TOKEN=$k";;
    esac
  done
  echo; status
}

case "${1:-status}" in
  status) status;;
  install) install_all;;
  login) login_all;;
  cloud-id) u="${2:-$site}"; [ -n "$u" ] || { echo "usage: connect.sh cloud-id <https://site.atlassian.net>" >&2; exit 1; }
    curl -fsS "${u%/}/_edge/tenant_info" | jq -r '.cloudId // empty';;
  *) echo "usage: connect.sh <status|install|login|cloud-id URL>" >&2; exit 1;;
esac
