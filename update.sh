#!/bin/bash
set -e

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

stage3="$(wget -qO- 'http://distfiles.gentoo.org/releases/arm/autobuilds/latest-stage3-armv6j_hardfp.txt' | tail -n1)"

if [ -z "$stage3" ]; then
	echo >&2 'wtf failure'
	exit 1
fi

url="http://distfiles.gentoo.org/releases/arm/autobuilds/$stage3"
name="$(basename "$stage3")"

( set -x; wget -N "$url" )

base="${name%%.*}"
image="gentoo-temp:$base"
container="gentoo-temp-$base"

# bzcat thanks to https://code.google.com/p/go/issues/detail?id=7279
( set -x; bzcat -p "$name" | docker import - "$image" )

docker rm -f "$container" > /dev/null 2>&1 || true
( set -x; docker run -t -v /usr/portage:/usr/portage:ro --name "$container" "$image" bash -exc $'
	export MAKEOPTS="-j$(nproc)"
	pythonTarget="$(emerge --info | sed -n \'s/.*PYTHON_TARGETS="\\([^"]*\\)".*/\\1/p\')"
	pythonTarget="${pythonTarget##* }"
	echo \'PYTHON_TARGETS="\'$pythonTarget\'"\' >> /etc/portage/make.conf
	echo \'PYTHON_SINGLE_TARGET="\'$pythonTarget\'"\' >> /etc/portage/make.conf
	emerge --newuse --deep --with-bdeps=y @system @world
	emerge -C editor ssh man man-pages openrc e2fsprogs texinfo service-manager
	emerge --depclean
' )

xz="$base.tar.xz"
( set -x; docker export "$container" | xz -9 > "$xz" )

docker rm "$container"
docker rmi "$image"

echo 'FROM scratch' > Dockerfile
echo "ADD $xz /" >> Dockerfile
echo 'CMD ["/bin/bash"]' >> Dockerfile

user="$(docker info | awk '/^Username:/ { print $2 }')"
[ -z "$user" ] || user="$user/"
( set -x; docker build -t "${user}rpi-gentoo-stage3" . )

# Quick n' dirty solution
git add Dockerfile "$xz" && \
git commit -m "New version - $base" && \
git checkout master && \
git merge script -m "New version - $base" && \
git checkout script && \
git reset --hard HEAD^1 && \
git checkout master && \
echo "Git structure prepared correctly" || \
echo "An error was found. Please check it manually"
