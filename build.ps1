# A powershell script to create WSL2 image from docker container
# Requirements (for windows):
# - Docker desktop
# - tar and gzip command
# - WSL2
# Recommended Windows versions is Windows 10 May 2019 update or higher

# Termux variables
$TERMUX_APPDIR = "/data/data/com.termux/files"
$TERMUX_PREFIX = "${TERMUX_APPDIR}/usr"
$TERMUX_HOME = "${TERMUX_APPDIR}/home"

$requiredTools = "gzip.exe","docker.exe","tar.exe","wsl.exe"
Foreach ($x in $requiredTools){
    Get-Command $x -ErrorAction SilentlyContinue -ErrorVariable ProcessError | Out-Null
    if ($ProcessError) {
        Write-Host "Tool $x is required for building procedure"
        exit 2
    }
}

# Prepare docker host. check if the service is running by expanding the service "status" property
$Service=$(Get-Service -Name com.docker.service | Select-Object -ExpandProperty Status)
if ("Running" -ne $Service){
    Write-Host "Docker service isn't running!"
    exit 2
}

# Initialize docker container
$CONTAINER_NAME = "termux_wsl"
$IMAGE_TAG = "x86_64"
$IMAGE_NAME = "kcubeterm/termux:${IMAGE_TAG}"

docker image inspect $IMAGE_NAME 2>&1 | Out-Null
if (False -eq $?){
    docker pull $IMAGE_NAME
}

# Create a pristine container if any
docker container inspect $CONTAINER_NAME 2>&1 | Out-Null
if (True -eq $?) {
    docker rm $CONTAINER_NAME --force
}

# Run docker in detached mode to avoid container startup failure later on
docker run -td --name $CONTAINER_NAME $IMAGE_NAME

# Create password database
Write-Output "root:x:0:0:root:/:/system/bin/sh" | Out-File ${env:TEMP}\passwd
Write-Output "system:x:1000:1000:system:${TERMUX_HOME}:/system/bin/init-container.sh" | Out-File -Append ${env:TEMP}\passwd
# Create init-container to setup termux variables
Write-Output "#!/system/bin/busybox sh
/system/bin/busybox env TMPDIR=${TERMUX_PREFIX}/tmp \
PATH=${TERMUX_PREFIX}/bin \
HOME=${TERMUX_HOME} \
ANDROID_DATA=/data \
ANDROID_ROOT=/system \
LANG=en_US.UTF-8 \
TZ=UTC \
${TERMUX_PREFIX}/bin/login" | Out-File ${env:TEMP}\init-container
# Create wsl.conf for logging in as system user
Write-Output "[user]
default = system" | Out-File ${env:TEMP}\wsl.conf

# Copy files into the container
docker cp ${env:TEMP}\wsl.conf ${CONTAINER_NAME}:/etc/wsl.conf
docker cp ${env:TEMP}\passwd ${CONTAINER_NAME}:/etc/passwd
docker cp ${env:TEMP}\init-container ${CONTAINER_NAME}:/system/bin/init-container.sh

# Set appropriate permissions
docker exec -it --user root ${CONTAINER_NAME} /system/bin/busybox chmod 644 /etc/passwd
docker exec -it --user root ${CONTAINER_NAME} /system/bin/busybox chmod 644 /etc/wsl.conf
docker exec -it --user root ${CONTAINER_NAME} /system/bin/busybox chmod 755 /system/bin/init-container.sh

# Convert line endings to LF
docker exec -it --user root ${CONTAINER_NAME} /system/bin/busybox dos2unix /etc/wsl.conf /etc/passwd /system/bin/init-container.sh

# Pack the container image
docker stop ${CONTAINER_NAME}
docker export ${CONTAINER_NAME} -o ${HOME}\termux-wsl.tar

# Remove container and image
docker rmi ${IMAGE_NAME} -f
docker rm ${CONTAINER_NAME} -f

# gzip the archive
gzip.exe ${HOME}\termux-wsl.tar

# Done
Write-Host "Successfully built the archive. you should be able to import it via `"wsl --import termux-wsl.tar.gz`""
