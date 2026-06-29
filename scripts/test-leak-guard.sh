#!/usr/bin/env bash
# Tests the pre-push leak guard's 3-class logic: private (skip), public (gitleaks +
# universal list), claude-phalanx (gitleaks + full project denylist). Requires
# gitleaks (the guard is fail-closed on it); SKIPs cleanly when it's absent.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/../githooks/pre-push"
if ! command -v gitleaks >/dev/null 2>&1; then echo "    SKIP leak-guard:* (gitleaks not installed)"; exit 0; fi
Z=0000000000000000000000000000000000000000
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
printf 'joeybuilt\nFonto\n' > "$T/full"
printf '192.168.0.50\nme@example.com\n' > "$T/uni"
printf 'owner/plexo\n' > "$T/pub"
export PHALANX_LEAKWORDS="$T/full" PHALANX_LEAKWORDS_PUBLIC="$T/uni" PHALANX_PUBLIC_REMOTES="$T/pub"
git config --global --add safe.directory '*' 2>/dev/null || true
FAIL=0
mkrepo() { local d; d="$(mktemp -d)"; ( cd "$d" && git init -q && git config user.email a@b.c && git config user.name a && printf '%s\n' "$1" > f.txt && git add f.txt && git commit -q -m c ); echo "$d"; }
run() { local d="$1" url="$2" h; h=$(git -C "$d" rev-parse HEAD); ( cd "$d" && echo "refs/heads/x $h refs/heads/x $Z" | bash "$HOOK" origin "$url" >/dev/null 2>&1 ); echo $?; }
ck() { if [ "$2" = "$3" ]; then echo "    PASS leak-guard:$1"; else echo "    FAIL leak-guard:$1 (exit $2 want $3)"; FAIL=1; fi; }

r=$(mkrepo "ip 192.168.0.50");      ck "private-skips"        "$(run "$r" https://github.com/owner/secret.git)" 0; rm -rf "$r"
r=$(mkrepo "ip 192.168.0.50");      ck "public-universal-block" "$(run "$r" https://github.com/owner/plexo.git)" 1; rm -rf "$r"
r=$(mkrepo "Plexo own name");        ck "public-ownname-allow"  "$(run "$r" https://github.com/owner/plexo.git)" 0; rm -rf "$r"
r=$(mkrepo "joeybuilt note");        ck "phalanx-project-block" "$(run "$r" https://github.com/owner/claude-phalanx.git)" 1; rm -rf "$r"
r=$(mkrepo "clean code");            ck "phalanx-clean-allow"   "$(run "$r" https://github.com/owner/claude-phalanx.git)" 0; rm -rf "$r"
[ "$FAIL" = 0 ] && echo "ok: leak-guard 3-class logic" || exit 1
