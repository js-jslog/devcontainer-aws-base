$param1 = $args[0]

if ($param1 -ne "start" -and $param1 -ne "destructive") {
    Write-Host "Error: Invalid parameter. Acceptable parameters are 'start', or 'destructive'."
    exit 1
}

docker pull jslog/devcontainer-aws-base:latest

if ($param1 -eq "destructive") {
    Write-Host "Destroying the existing container and the /app volume with it. Any work not committed and pushed is lost."
    Write-Host "WARNING: if any AWS infrastructure is currently deployed from this container, destroy it FIRST."

    $containers = docker ps -aq --filter volume=devcontainer-aws-base-volume
    if ($containers) {
        docker rm -f $containers
    }

    docker volume rm --force devcontainer-aws-base-volume
}

devcontainer up --remote-env GIT_USER_NAME=$(git config --get user.name) --remote-env GIT_USER_EMAIL=$(git config --get user.email) --workspace-folder .
