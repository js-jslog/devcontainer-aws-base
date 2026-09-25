#!/usr/bin/env bash
#
# verify-toolchain.sh - smoke-test every tool baked into this devcontainer.
#
# Tier 1 (default): offline checks only. Free, fast, no AWS login required.
# Tier 2 (--live):   also exercises real AWS - requires `aws sso login` to
#                     already have been run. Bootstraps CDK if needed (a
#                     one-time, idempotent, persistent stack per
#                     account/region - see docs/aws-conventions.md), then
#                     deploys and destroys an empty scaffold stack, so no
#                     billable resources are created.
#
# Every check is independent and non-fatal: the full suite always runs and
# a pass/fail summary prints at the end, so a single run gives the whole
# picture instead of stopping at the first failure. Intended to be run both
# against the current container and, per the README, against a freshly
# built image after `runcontainer.ps1 purge` - a stale cache or an old
# running container can make a regressed image look healthy otherwise.

set -uo pipefail

LIVE=0
[[ "${1:-}" == "--live" ]] && LIVE=1

PASS=0
FAIL=0
FAILED=()

check() {
  local name="$1"; shift
  echo "=== $name ==="
  if "$@"; then
    echo "--- PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "--- FAIL: $name"
    FAIL=$((FAIL + 1))
    FAILED+=("$name")
  fi
  echo
}

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# ---------------------------------------------------------------- Tier 1 --

docker_check()   { docker version >/dev/null && docker run --rm hello-world >/dev/null; }
java_check()     { java -version && javac -version; }
node_check()     { [[ "$(node -v)" == "v24.20.0" ]]; }
pnpm_check()     { [[ "$(pnpm -v)" == "10.21.0" ]]; }
python_check()   { python3 --version; }
pipx_check()     { pipx --version; }
awscli_check()   { aws --version; }
ssm_check()      { session-manager-plugin --version; }
kubectl_check()  { kubectl version --client; }
helm_check()     { helm version; }
eksctl_check()   { eksctl version; }
lazygit_check()  { lazygit --version; }
gcm_check()      { git-credential-manager --version; }
claude_check()   { claude --version; }
apt_tools_check() { jq --version && less --version && tcc -v && rg --version && tmux -V; }

boto3_check() (
  source ~/.venvs/aws/bin/activate && python3 -c "import boto3; print(boto3.__version__)"
)

sam_check() (
  cd "$WORKDIR" &&
  sam --version &&
  sam init --name samtest --runtime python3.12 --dependency-manager pip \
    --app-template hello-world --no-tracing --no-application-insights >/dev/null &&
  cd samtest &&
  sam validate --lint &&
  sam build >/dev/null &&
  sam local invoke HelloWorldFunction --event events/event.json
)

cdk_check() (
  cd "$WORKDIR" && mkdir cdktest && cd cdktest &&
  cdk --version &&
  cdk init app --language typescript >/dev/null &&
  cdk synth >/dev/null
)

terraform_check() (
  cd "$WORKDIR" && mkdir tftest && cd tftest &&
  terraform version &&
  echo 'terraform { required_version = ">= 1.0" }' > main.tf &&
  terraform init >/dev/null &&
  terraform validate
)

nvim_treesitter_check() {
  rm -rf ~/.local/share/nvim/lazy/nvim-treesitter/parser
  nvim --headless "+TSInstallSync lua" "+qa!" >/dev/null 2>&1
  [[ -f ~/.local/share/nvim/lazy/nvim-treesitter/parser/lua.so ]]
}

check "Docker-in-Docker"                    docker_check
check "Java (JDK 21)"                       java_check
check "Node 24.20.0"                        node_check
check "pnpm 10.21.0"                        pnpm_check
check "Python 3.12"                         python_check
check "boto3 (awspy venv)"                  boto3_check
check "pipx"                                pipx_check
check "AWS CLI"                             awscli_check
check "Session Manager plugin"              ssm_check
check "SAM CLI (init/validate/build/local invoke)" sam_check
check "CDK (init/synth)"                    cdk_check
check "Terraform (init/validate)"           terraform_check
check "kubectl (client)"                    kubectl_check
check "helm"                                helm_check
check "eksctl"                              eksctl_check
check "neovim + treesitter (tcc/libc6-dev)" nvim_treesitter_check
check "lazygit"                             lazygit_check
check "Git Credential Manager"              gcm_check
check "Claude Code"                         claude_check
check "apt utilities (jq/less/tcc/rg/tmux)" apt_tools_check

# ---------------------------------------------------------------- Tier 2 --

if [[ "$LIVE" -eq 1 ]]; then
  aws_identity_check() { aws sts get-caller-identity; }
  check "AWS SSO identity (run 'aws sso login' first)" aws_identity_check

  cdk_live_check() (
    cd "$WORKDIR/cdktest" || exit 1
    cdk bootstrap || exit 1
    # Always attempt cleanup, even if deploy fails partway - an orphaned
    # stack left behind by a `&&` chain is exactly the kind of leak
    # docs/aws-conventions.md warns about.
    status=0
    cdk deploy --require-approval never || status=1
    cdk destroy --force || status=1
    exit "$status"
  )
  check "CDK live deploy/destroy round-trip" cdk_live_check
fi

# ---------------------------------------------------------------- Summary --

echo "================================"
echo "$PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
  printf 'Failed: %s\n' "${FAILED[@]}"
  exit 1
fi
