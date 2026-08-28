# AWS conventions for this container

Rationale and habits that don't belong in the README. Written down because most of it is
the kind of thing that costs money or time when forgotten.

## First-run setup

1. **Authenticate with IAM Identity Center, not access keys.**

   ```
   aws configure sso
   aws sso login          # device-code flow; works headless
   ```

   Short-lived credentials, and nothing sensitive ends up in an image layer — which
   matters because **`jslog/*` on Docker Hub is public** (confirmed: `is_private=False`).
   `~/.aws` is a named volume, so config and cached tokens survive image rebuilds.

2. **Set an AWS Budgets alarm before your first deploy.** Not after.

3. **Bootstrap CDK** once per account/region: `cdk bootstrap`. This creates a `CDKToolkit`
   stack, an S3 asset bucket and an ECR repo.

## CDK is the primary IaC tool; Terraform is installed for exercises

- **CloudFormation is examinable; Terraform is not.** AWS certifications test
  CloudFormation and CDK, not third-party tools. CDK synthesises CloudFormation, so
  learning it teaches the thing that is actually on the exam.
- **CDK has no state file.** CloudFormation holds state server-side, so a destroyed
  container volume can never orphan infrastructure you are unable to clean up. That
  matters a great deal in a deliberately disposable devcontainer.
- **TypeScript is CDK's native language** — it is authored in TS and transpiled via jsii.

Terraform stays installed because it is what job adverts ask for, it is multi-cloud, and
its state model is worth understanding. Use it for deliberate exercises. Don't build the
same project twice.

CDK's own overheads, for balance: `cdk bootstrap` leaves a stack, a bucket and an ECR repo
per account/region, and CloudFormation stacks can wedge in `ROLLBACK` states that are more
awkward to unstick than a Terraform state fix.

## Terraform state

Use an S3 backend for anything long-lived. Native state locking arrived in Terraform 1.10,
so no DynamoDB table is needed.

Local state is acceptable *only* for a lab you destroy in the same session. Local state in
the workspace volume plus live infrastructure means `runcontainer.ps1 destructive` orphans
paid resources with no state left to destroy them.

## Where lab money actually leaks

Destroy at the end of every session, and tag everything.

- NAT Gateway — ~$32/month, the classic surprise bill
- EKS control plane — ~$73/month
- Idle RDS instances
- Unattached Elastic IPs

## Python packaging (PEP 668)

Ubuntu 24.04 refuses system-level `pip install`, failing with
`externally-managed-environment`. Three routes are provided:

- `awspy` — a bashrc alias activating a prebuilt venv at `~/.venvs/aws` with `boto3` ready
- `pipx install <tool>` — for Python CLI tools
- `python3 -m venv .venv` — per project, for anything real

## Neovim

The image carries Node, so `neovim-config` works unchanged: `ts_ls`, `eslint` and
`prettier` all install through Mason as normal.

Treesitter parsers compile against `tcc`, but only because `libc6-dev` is installed
alongside it — see the gotcha below. **`nvim --headless "+qa!"` cannot verify this**: it
exits 0 whether or not any parser builds, because nvim-treesitter compiles asynchronously
and quits before a compile finishes, and a failed compile is non-fatal regardless. The
check that actually proves it:

```
nvim --headless "+TSInstallSync lua" "+qa!"
ls ~/.local/share/nvim/lazy/nvim-treesitter/parser/   # expect lua.so
```

Language support for this container's actual work is still to be added, best done on a
branch from inside the container where you get real feedback. **Push that branch before
rebuilding.** `~/.config/nvim` is a git checkout baked into the image with no volume over
it, so a rebuild always lands the current `neovim-config` and always discards uncommitted
edits. Priority order:

1. `terraformls` — highest value, and covers HCL for both IaC tools
2. `pyright` — Python/boto3
3. `jdtls` — Java; the fiddliest by a wide margin
4. `yamlls`, `bashls` — CloudFormation, manifests, scripts
5. Treesitter parsers: `hcl`, `python`, `java`, `yaml`, `bash`, `json` — all six, plus
   `terraform`, are confirmed to build under `tcc`, so no compiler change is needed for them

The image sets `JSLOG_LSP_PROFILE=aws` as a forward-looking hook for a language-profile
switch in `neovim-config`. **The config does not read it yet** — it is there so the profile
mechanism has somewhere to land without another image rebuild.

## Gotchas baked into the Dockerfile

Each is commented in place; recorded here so they aren't rediscovered the hard way.

- **Ubuntu 24.04 ships a stock `ubuntu` user at uid 1000**, which must be removed before
  the `dev` user can own uid 1000.
- **The Temurin base has no `xz`**, so `xz-utils` is required to unpack the Node tarball.
  `node:24` includes it; a JDK image does not.
- **`tcc` alone cannot compile anything on this base**, so `libc6-dev` is installed with it.
  node-base names only `tcc` and gets away with it: `node:24` derives from buildpack-deps,
  so gcc and libc6-dev are already present and `cc` resolves to gcc, not tcc. On Temurin
  neither is present, tcc becomes the only `cc`, and the tcc package ships eight
  freestanding headers with no `stdint.h` and no `crti.o`. The symptom is every
  nvim-treesitter parser failing to build on startup with `tcc: error: file 'crti.o' not
  found`, on any file, with Mason itself perfectly healthy.
- **`corepack enable` must run as root** (shims go to `/usr/local/bin`) but
  **`corepack prepare` must run as `dev`** (it caches the pinned version under `$HOME`).
  Get the second one wrong and the build still goes green while corepack silently fetches
  the latest pnpm at runtime instead of the pinned version.
- **Every named-volume mount point is pre-created and chowned to `dev`.** Docker creates
  missing mount points as `root:root`, which would leave `dev` unable to write to them.
- **`~/.local/share/nvim` (Mason/LSP data) and `~/.local/share/pnpm` (the pnpm store) are
  deliberately not volumes.** Neither has ever needed to survive a rebuild in practice, so
  a re-fetch is accepted rather than pre-solved.
- **`~/.config/nvim` deliberately has no volume either**, for a different reason than
  Mason/pnpm above. Docker seeds a named volume from the image only while the volume is
  empty, so a volume there would mask the Dockerfile's `git clone` after the first run and
  no image rebuild could ever update the config again. Leaving it as image state means the
  clone is authoritative and edits worth keeping have to be committed and pushed to
  `neovim-config`. The trade is that the clone is unpinned: a rebuild takes whatever is on
  that repo's default branch, which is the one place this image is not reproducible.
- **`COPY . .` is deliberately last**, unlike node-base, so editing the repo doesn't
  invalidate ~2GB of cached tool layers above it.
