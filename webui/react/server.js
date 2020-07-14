var http = require('http')

function infinite (req, res) {
  res.setHeader('Content-Type', 'application/json')
  	// Set CORS headers
	res.setHeader('Access-Control-Allow-Origin', '*');
	res.setHeader('Access-Control-Request-Method', '*');
	res.setHeader('Access-Control-Allow-Methods', 'OPTIONS, GET');
	res.setHeader('Access-Control-Allow-Headers', '*');
  var seq = 0
  setInterval(function () {
    res.write(JSON.stringify({value: seq++}) + '\n')
  }, 100)
}

http.createServer(infinite).listen(9090)

