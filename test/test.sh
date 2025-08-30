#!/usr/bin/env sh

cd "$(dirname "$0")"

cleanup() {
	echo "Cleaning up..."
	# Call test base cleanup as well
	"$SHELL" test.base.sh CLEANUP
	exit $1
}

trap "cleanup 1" SIGINT SIGTERM SIGHUP

[ -d "output" ] && rm -r "output"
mkdir output
mkdir -p run

TEST_IP="187.2.2.1"

# Set environment variable defaults
TRAEFIK_WHOAMI_VERSION=${TRAEFIK_WHOAMI_VERSION:=latest}
TRAEFIK_VERSION=${TRAEFIK_VERSION:=latest}

# Go module name
MODULE_NAME=$(grep '^module ' ../go.mod | awk '{print $2}')

TRAEFIK_CONFIG="./run/traefik.toml"
TRAEFIK_CONFIG_BASE="./traefik.base.toml"

DOCKER_COMPOSE="./run/docker-compose.yml"
DOCKER_COMPOSE_BASE="./docker-compose.base.yml"

echo "Using Traefik whoami ${TRAEFIK_WHOAMI_VERSION}"
echo "Using Traefik ${TRAEFIK_VERSION}"

docker pull traefik/whoami:${TRAEFIK_WHOAMI_VERSION}>/dev/null
docker pull traefik:${TRAEFIK_VERSION}>/dev/null

cp $TRAEFIK_CONFIG_BASE $TRAEFIK_CONFIG
cp $DOCKER_COMPOSE_BASE $DOCKER_COMPOSE

if [ ${ENVIRONMENT:=development} = "production" ]; then
	# Get latest tag
	LATEST_PLUGIN_VERSION=$(git describe --match "v*" --abbrev=0 --tags HEAD)
	echo "Testing production version ${LATEST_PLUGIN_VERSION}"
	
	cat >> $TRAEFIK_CONFIG <<-EOF
	
	[experimental]
	  [experimental.plugins]
	    [experimental.plugins.cloudflarewarp]
	      moduleName = "${MODULE_NAME}"
	      version = "${LATEST_PLUGIN_VERSION}"
	EOF
else
	echo "Testing development version"
	cat >> $TRAEFIK_CONFIG <<-EOF
	
	[experimental.localPlugins.cloudflarewarp]
	  moduleName = "${MODULE_NAME}"
	EOF

	# Provide local code to container
	cat >> $DOCKER_COMPOSE <<-EOF
      - ../../:/plugins-local/src/${MODULE_NAME}:ro
	EOF
fi

checkExit() {
	# Validate if exit code is fail, and cleanup/exit if so
	if [ ! $1 = 0 ]; then
		echo "Test fail"
		cleanup 1
	fi
}

runTest() {
	# Run test with same shell executable
	"$SHELL" test.base.sh $1 $2 $3
	# Check if it exited safely, and if not, cleanup
	checkExit $?
	# Validate test results
	"$SHELL" test.verify.sh $1 $3
	# Save exit code for later
	EXIT=$?
	# Move logs for packaging by CI
	mv run/logs output/$1-$2
	# Check if validate exited safely, and if not, cleanup
	checkExit $EXIT
}

# TOML config tests
runTest success toml $TEST_IP
runTest fail toml $TEST_IP
runTest invalid toml "1522.20.1"

# YAML config tests
runTest success yml $TEST_IP
runTest fail yml $TEST_IP
runTest invalid yml "1522.20.2"

echo All tests succeeded!

# Cleanup as success
cleanup 0
