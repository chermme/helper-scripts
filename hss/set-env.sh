if [ ! $1 ]; then
  ENV="nightly"
else
  ENV=$1
fi

if [[ $ENV == "dev"* ]]; then
  export API_URL="${ENV}-hyrax.dev.api-hss.com"
  export API_SEARCH_URL="${ENV}-hyraxsearch.dev.api-hss.com"

  export HSS_API_URL="${ENV}-hyrax.dev.api-hss.com"
  export HSS_API_SEARCH_URL="${ENV}-hyraxsearch.dev.api-hss.com"
else
  export API_URL="${ENV}-hyrax.api-hss.com"
  export API_SEARCH_URL="${ENV}-hyraxsearch.api-hss.com"

  export HSS_API_URL="${ENV}-hyrax.api-hss.com"
  export HSS_API_SEARCH_URL="${ENV}-hyraxsearch.api-hss.com"
fi

echo "------------------------------------------"
echo "ENV vars set to:"
echo "API_URL: ${API_URL}"
echo "API_SEARCH_URL: ${API_SEARCH_URL}"
echo "------------------------------------------"
echo "HSS-ENV vars set to:"
echo "HSS_API_URL: ${HSS_API_URL}"
echo "HSS_API_SEARCH_URL: ${HSS_API_SEARCH_URL}"
echo "------------------------------------------"
