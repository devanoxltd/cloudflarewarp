WORK_PATH="./run"

cleanup() {
	echo "Cleaning up..."
	docker compose -f "${WORK_PATH}/docker-compose.yml" stop traefik;
	exit $1
}

trap "cleanup 1" SIGINT SIGTERM SIGHUP

if [ "${1}" = "CLEANUP" ]; then
	echo "Removing Docker containers"
	docker compose -f "${WORK_PATH}/docker-compose.yml" down --remove-orphans -v;
	exit 0
fi

echo -e "\n\n*** STARTING TEST FOR : ${1}.${2}\n\n";

[ -d "${WORK_PATH}/logs" ] && rm -r "${WORK_PATH}/logs"
[ -d "${WORK_PATH}/config" ] && rm -r "${WORK_PATH}/config"

mkdir ${WORK_PATH}/logs;
mkdir ${WORK_PATH}/config;

touch ${WORK_PATH}/logs/access.log;
touch ${WORK_PATH}/logs/debug.log;
touch ${WORK_PATH}/logs/traefik.log;

cp -r "./config/${1}.${2}" "${WORK_PATH}/config/config.${2}"

docker compose -f "${WORK_PATH}/docker-compose.yml" up -d;
sleep 1s;

ITERATIONS=0
while ! grep -q "Starting TCP Server" "${WORK_PATH}/logs/debug.log" && [ $ITERATIONS -lt 30 ]; do
	sleep 1s
	echo "Waiting for Traefik to be ready [${ITERATIONS}s/30]"
	let ITERATIONS++
done

ITERATIONS=0
while ! grep -q "Provider connection established with docker" "${WORK_PATH}/logs/debug.log" && [ $ITERATIONS -lt 30 ]; do
	sleep 1s
	echo "Waiting for Traefik to connect to docker [${ITERATIONS}s/30]"
	let ITERATIONS++
done

ITERATIONS=0
while ! grep -q "Creating middleware" "${WORK_PATH}/logs/debug.log" && [ $ITERATIONS -lt 30 ]; do
	sleep 1s
	echo "Waiting for Traefik to finish setup [${ITERATIONS}s/30]"
	let ITERATIONS++
done

curl -s -H "CF-Connecting-IP:${3}" -H "CF-Visitor:{\"scheme\":\"https\"}" http://localhost:4008/ >> ${WORK_PATH}/logs/output.log;
echo "Headers:\nCF-Connecting-IP:${3}\nCF-Visitor:{\"scheme\":\"https\"}" >> ${WORK_PATH}/logs/request.log
cat ${WORK_PATH}/logs/output.log;

cleanup 0
