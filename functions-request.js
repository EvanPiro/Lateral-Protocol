const config = {
  url: 'https://www.signdb.com/.netlify/functions/optimize',
};

const response = await Functions.makeHttpRequest(config);
const price = Math.round(response.data['weight']);
return Functions.encodeUint256(price);
