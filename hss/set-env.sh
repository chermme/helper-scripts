if [ ! $1 ]; then
  ENV="nightly"
else
  ENV=$1
fi

export API_ENV=$ENV
export API_URL="${ENV}-hyrax.api-hss.com"
export API_SEARCH_URL="${ENV}-hyraxsearch.api-hss.com"

export HSS_API_ENV=$ENV
export HSS_API_URL="${ENV}-hyrax.api-hss.com"
export HSS_API_SEARCH_URL="${ENV}-hyraxsearch.api-hss.com"

echo "------------------------------------------"
echo "ENV vars set to:"
echo "API_ENV: ${API_ENV}"
echo "API_URL: ${API_URL}"
echo "API_SEARCH_URL: ${API_SEARCH_URL}"
echo "------------------------------------------"
echo "HSS-ENV vars set to:"
echo "HSS_API_ENV: ${HSS_API_ENV}"
echo "HSS_API_URL: ${HSS_API_URL}"
echo "HSS_API_SEARCH_URL: ${HSS_API_SEARCH_URL}"
echo "------------------------------------------"
