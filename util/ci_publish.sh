VERSION_BUMP=$1
UPDATE_DESCRIPTION="$2"
FILES_TO_UPDATE="README.md"

bumpVersion() {
	VERSION_OLD=$1
	VERSION_BUMP=$2

	if [ "$VERSION_BUMP" = "major" ]; then
		VERSION_DIFF="1"
	elif [ "$VERSION_BUMP" = "minor" ]; then
		VERSION_DIFF="0.1"
	elif [ "$VERSION_BUMP" = "patch" ]; then
		VERSION_DIFF="0.0.1"
	else
		echo "Unknown version type $VERSION_BUMP"
		exit 1
	fi

	VERSION_NEW=v$(echo "${VERSION_OLD#v}" | awk -v versionDiff="$VERSION_DIFF" -F. '
	/[0-9]+\./ {
		n = split(versionDiff, versions, ".");
		if(n>NF)
			nIter=n;
		else
			nIter=NF;
		lastNonzero = nIter;
		for(i = 1; i <= nIter; ++i) {
			if(int(versions[i]) > 0) {
				lastNonzero = i;
			}
			$i = versions[i] + $i;
		}
		for(i = lastNonzero+1; i <= nIter; ++i) {
			$i = 0;
		}
		print;
	}' OFS=.)

	echo $VERSION_NEW
}

checkExit() {
	if [ ! $1 = 0 ]; then echo "$2" && exit $1; fi
}

LATEST_PLUGIN_VERSION=$(git describe --match "v*" --abbrev=0 --tags HEAD)
echo "Detected current version $LATEST_PLUGIN_VERSION"

NEW_VERSION=$(bumpVersion $LATEST_PLUGIN_VERSION $VERSION_BUMP)
checkExit $? "$NEW_VERSION"
echo "Bumping version to $NEW_VERSION"

for file in $FILES_TO_UPDATE; do
	echo "Updating $file"
	sed -i "s/$LATEST_PLUGIN_VERSION/$NEW_VERSION/g" $file
done

if [ ${ENVIRONMENT:=default} = "ci" ]; then
	git add -A
	git commit -m "[Release $NEW_VERSION] Bump version from $LATEST_PLUGIN_VERSION\n$UPDATE_DESCRIPTION"
	git tag -a $NEW_VERSION -m "$UPDATE_DESCRIPTION"
	git push
else
	echo "Skipping commit/tag as ENVIRONMENT is not set to ci"
fi
