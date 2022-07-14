if [ ! $1 ]; then
  ENV="staging"
else
  ENV=$1
fi

export API_URL="${ENV}-hyrax.api-anyjunk.co.uk"
export API_SEARCH_URL="${ENV}-hyrax.api-anyjunk.co.uk",

echo " "
echo "ENV vars set to:"
echo "API_URL: ${API_URL}"
echo "API_SEARCH_URL: ${API_SEARCH_URL}"
echo " "
