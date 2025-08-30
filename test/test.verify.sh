OUTPUT_LOG="./run/logs/output.log"

echo "Validating ${1} test"

if [ "$1" = "success" ]; then
	# Successful test
	if ! grep -q "X-Is-Trusted: yes" $OUTPUT_LOG; then
		echo "'X-Is-Trusted: yes' header was not added and parsed"
		exit 5
	fi
	if ! grep -q "X-Forwarded-For: ${2}, 172.19.0.10" $OUTPUT_LOG; then
		echo "'X-Forwarded-For: ${2}, 172.19.0.10' header not defined"
		exit 5
	fi
	if ! grep -q "X-Real-Ip: ${2}" $OUTPUT_LOG; then
		echo "'X-Real-Ip: ${2}' header not defined"
		exit 5
	fi
	if ! grep -q "Cf-Visitor: {\"scheme\":\"https\"}" $OUTPUT_LOG; then
		echo "'Cf-Visitor: {\"scheme\":\"https\"}' header not defined"
		exit 5
	fi
elif [ "$1" = "fail" ]; then
	# Test ran with no trusted proxies
	if ! grep -q "X-Is-Trusted: no" $OUTPUT_LOG; then
		echo "'X-Is-Trusted: no' header was not added"
		exit 5
	fi
	if ! grep -q "X-Forwarded-For: 172.19.0.10" $OUTPUT_LOG; then
		echo "'X-Forwarded-For: 172.19.0.10' was not defined as the original IP"
		exit 5
	fi
	if ! grep -q "X-Real-Ip: 172.19.0.10" $OUTPUT_LOG; then
		echo "'X-Real-Ip: 172.19.0.10' was not defined as the original IP"
		exit 5
	fi
elif [ "$1" = "invalid" ]; then
	# Test ran with invalid IP in Cloudflare header
	if ! grep -q "X-Is-Trusted: no" $OUTPUT_LOG; then
		echo "'X-Is-Trusted: no' header was not added"
		exit 5
	fi
	if ! grep -q "X-Forwarded-For: 172.19.0.10" $OUTPUT_LOG; then
		echo "'X-Forwarded-For: 172.19.0.10' was not defined as the original IP"
		exit 5
	fi
	if ! grep -q "X-Real-Ip: 172.19.0.10" $OUTPUT_LOG; then
		echo "'X-Real-Ip: 172.19.0.10' was not defined as the original IP"
		exit 5
	fi
else
	echo "Error, unknown test type ${1}"
	exit 10
fi

echo "Test OK"
