if [ ! $1 ]; then
  ENV="staging"
else
  ENV=$1
fi

export HSS_API_URL="${ENV}-hyrax.api-hss.com"
export HSS_API_SEARCH_URL="${ENV}-hyraxsearch.api-hss.com"

echo " "
echo "HSS-ENV vars set to:"
echo "HSS_API_URL: ${HSS_API_URL}"
echo "HSS_API_SEARCH_URL: ${HSS_API_SEARCH_URL}"
echo " "
