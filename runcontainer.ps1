$param1 = $args[0]

if ($param1 -ne "start" -and $param1 -ne "destructive" -and $param1 -ne "purge") {
    Write-Host "Error: Invalid parameter. Acceptable parameters are 'start', 'destructive', or 'purge'."
    exit 1
}

# The workspace volume, mounted at /app. Holds all work, and with Terraform
# all local state, so this is the one `destructive` exists to remove.
$workspaceVolume = "devcontainer-aws-base-volume"

# The named volumes declared in devcontainer.json under /home/dev. These are
# caches and credentials rather than work: Mason downloads and LSP indexes,
# the pnpm store, Gradle and Terraform plugin caches, SSO config, cluster
# config. `destructive` deliberately keeps them - rebuilding them is slow and
# ~/.aws and ~/.kube are hand-configured. Only `purge` removes them.
$homeVolumes = @(
    "aws-base-nvim-data",
    "aws-base-pnpm-store",
    "aws-base-aws",
    "aws-base-kube",
    "aws-base-gradle",
    "aws-base-tf-cache"
)

docker pull jslog/devcontainer-aws-base:latest

if ($param1 -ne "start") {
    Write-Host "Destroying the existing container and the /app volume with it. Any work not committed and pushed is lost."
    Write-Host "WARNING: if any AWS infrastructure is currently deployed from this container, destroy it FIRST."
    if ($param1 -eq "purge") {
        Write-Host "PURGE additionally removes the cache and credential volumes, including ~/.aws and ~/.kube. SSO and cluster config will have to be set up again."
    }

    $volumesToRemove = @($workspaceVolume)

    $containers = @(docker ps -aq --filter "volume=$workspaceVolume")
    if ($containers.Count -gt 0) {
        # The docker-in-docker feature mounts its own volume at /var/lib/docker,
        # named dind-var-lib-docker-<devcontainerId>. It is created by the feature
        # rather than declared in devcontainer.json, so it is invisible there and
        # nothing else would ever reclaim it. Left behind it grows without bound -
        # `./buildimage.sh` builds a ~2GB image inside it - and reattaching a fresh
        # container to an orphaned daemon state directory is a good way to get a
        # daemon holding stale networks and containers that no longer exist.
        #
        # Read the name off the container rather than matching the name prefix.
        # The Extension section of the README expects sibling projects forked from
        # this one, each with its own dind volume, and a prefix match would destroy
        # theirs too.
        foreach ($container in $containers) {
            $attached = docker inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}} {{end}}{{end}}' $container
            # @() so a container with no dind volume appends nothing. A bare
            # pipeline that matches nothing is $null, and += $null would append an
            # empty element that `docker volume rm` then chokes on.
            $volumesToRemove += @($attached -split '\s+' | Where-Object { $_ -like "dind-var-lib-docker-*" })
        }

        docker rm -f $containers
    }
    else {
        Write-Host "No container found using $workspaceVolume, so its docker-in-docker volume cannot be identified. If a container existed previously, check for an orphan with: docker volume ls --filter name=dind-var-lib-docker-"
    }

    if ($param1 -eq "purge") {
        $volumesToRemove += $homeVolumes
    }

    # --force so a volume that was already removed is not an error.
    foreach ($volume in ($volumesToRemove | Select-Object -Unique)) {
        docker volume rm --force $volume
    }
}

devcontainer up --remote-env GIT_USER_NAME=$(git config --get user.name) --remote-env GIT_USER_EMAIL=$(git config --get user.email) --workspace-folder .
