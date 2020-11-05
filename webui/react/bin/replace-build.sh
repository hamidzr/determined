#!/bin/bash -ex

## replace %PUBLIC_URL% with the corresponding environment value.

ESCAPED_REPLACE=$(printf '%s\n' "$PUBLIC_URL" | sed -e 's/[\/&]/\\&/g')
find build -type f -exec grep -Il "" {} \; | xargs sed -i "s/%PUBLIC_URL%/$ESCAPED_REPLACE/"
