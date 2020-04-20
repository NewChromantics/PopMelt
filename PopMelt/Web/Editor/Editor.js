

//	run a webserver on desktop to serve the html version
let HttpServer = new Pop.Http.Server(0);
const Url = 'http://' + HttpServer.GetAddress()[0].Address;
Pop.ShowWebPage(Url);



