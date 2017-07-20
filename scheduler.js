var fs = require('fs');
var _ = require('lodash');
var http = require('http');
var querystring = require('querystring');
var config = JSON.parse(fs.readFileSync('/opt/sasquatch/config.json', 'utf8'));
var date = new Date();
var currentHour = date.getHours();
var currentMinute = date.getMinutes();
var dayOfWeek = date.getDay();

//default times
var times = {
	//cant execute when day of week is -3
	day: -3,

	//not possible to start on hour -1
	start: -1,

	//not possible to stop on hour -1
	stop: -2
}

//load days of week to run on, if defined
if(_.isUndefined(config.sasquatch.scheduler.days[dayOfWeek]) === false) {
	var todaySchedule = config.sasquatch.scheduler.days[dayOfWeek]
	times.day = dayOfWeek;
	times.start = todaySchedule.startHour || -1;
	times.stop = todaySchedule.stopHour || -1;
}


if(times.day >= 0) {
	if(currentMinute == 0) {
		if(currentHour == times.start) {
				wakeUp();
		}

		if(currentHour == times.stop) {
			//time to go to sleep
				goToSleep();
		}
	}
}


function goToSleep() {
  var post_data = querystring.stringify({
  	'token': config.auth.tokens[0],
  	'text': 'stop'
  });

  send_command(post_data);
}

function wakeUp() {
 var post_data = querystring.stringify({
  	'token': config.auth.tokens[0],
  	'text': 'muppets'
  });

  send_command(post_data);
}

function send_command(data) {
  // An object of options to indicate where to post to
  var post_options = {
      host: '127.0.0.1',
      port: '8000',
      path: '/handle',
      method: 'POST',
      headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Content-Length': Buffer.byteLength(data)
      }
  };

  // Set up the request
  var post_req = http.request(post_options, function(res) {
      res.setEncoding('utf8');
      res.on('data', function (chunk) {
          console.log('Response: ' + chunk);
      });
  });

  // post the data
  post_req.write(data);
  post_req.end();

}

