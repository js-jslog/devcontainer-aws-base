# AWS-base devcontainer

A devcontainer with tooling for all potential AWS exercises — certification study
(Solutions Architect, DevOps Engineer, Security) and small AWS projects.

Sibling of [devcontainer-node-base](https://github.com/js-jslog/devcontainer-node-base):
same conventions, same scripts, different toolchain. It carries three runtimes because
AWS work spans all three.

For general study you don't need to fork this. Clone work into the gitignored `/app/work/`
directory, which the workspace volume persists.

See [docs/aws-conventions.md](docs/aws-conventions.md) for credentials, cost control, the
CDK-versus-Terraform decision, Python packaging and the neovim roadmap.

## Toolchain

Everything is pinned and baked at image-build time. The only devcontainer *feature* is
docker-in-docker.

| Tool | Version |
|---|---|
| JDK (Temurin) | 21 |
| Node | 24.20.0 |
| pnpm | 10.21.0 |
| Python | 3.12 + `venv`, `pipx`, `boto3` |
| AWS CLI | v2 2.36.32 |
| Session Manager plugin | latest (no pinnable artifact is published) |
| AWS SAM CLI | 1.165.0 |
| AWS CDK | 2.1139.0 |
| Terraform | 1.15.9 |
| kubectl / helm / eksctl | 1.37.0 / 4.2.4 / 0.230.0 |
| neovim | 0.11.2 + [neovim-config](https://github.com/js-jslog/neovim-config) |
| lazygit / GCM / Claude Code | 0.63.1 / 2.4.1 / latest |
| jq, less, tcc + libc6-dev, ripgrep, tmux | apt |

## Extension

To fork this for a specific project, update the image name in all the following files to
the Docker Hub resource address you want to use:

- `.devcontainer/devcontainer.json`: the `image` prop.
- `runcontainer.ps1`: the `docker pull` command.
- `buildimage.sh`: the `image` var.

Update the volume name in all the following files appropriately:

- `.devcontainer/devcontainer.json`: the `workspaceMount` source name.
- `runcontainer.ps1`: the `--filter volume=` & the `volume rm --force` commands.

The named volumes in the `mounts` array are shared cache and credential stores. Rename
them too if you want a project's caches kept separate.

Then follow the Launch from Windows instructions with the additional step of manually
building and pushing your very first image immediately after cloning:

```
docker build -t <user>/<image>:latest -f Dockerfile .
docker push <user>/<image>:latest
```

**The build context must be a git checkout.** The Dockerfile runs `git reset --hard` to
restore symlinks after the Windows prep change, so `docker build` fails in a directory
with no `.git`. This is inherited from node-base.

## Usage

### Launch from Windows

The project is intended for initiation on a Windows machine with Docker Desktop installed.
Windows is intended to only be used as a launchpad, and no changes to the project contents
are expected.

There is a prerequisite to have installed the devcontainer CLI.

```
git clone https://github.com/js-jslog/devcontainer-aws-base.git
./runcontainer.ps1 start # replace with `destructive` to replace an existing container and volume.
```

**Before running `destructive`, destroy any AWS infrastructure currently deployed from the
container.** With Terraform, local state lives in the workspace volume and goes with it,
leaving paid resources running and nothing to destroy them with. CDK is safe here, because
CloudFormation holds state server-side.

### Publish a new image

New images are built and published from inside a container. By default the image will be
tagged as `latest` for convenience as the priority and this should be the normal workflow.

```
docker login
./buildimage.sh # optional tag id param (see below)
```

For simplicity, testing the new container is done back in Windows. Clone a new project and
build a test container on a different volume and with a different name. Edit all the
locations in the Extension section above for completeness. Start the container and do
whatever tests are required.

### Broken :latest tag

If you overwrite the `:latest` tag with something which doesn't produce a working
devcontainer then you can recover from a "fallback" tagged image that you can make by
using the optional parameter to the `buildimage.sh`. It is not necessary to do this
frequently, because even a very old tag will allow you to pull the project inside the
devcontainer and be back up to date to tweak whatever mistake you made.

You will need to update certain resources in order to make use of a "fallback" tag. This
path is not seamlessly catered for, but should be simple enough if you again follow the
file update list in the Extension section above.
