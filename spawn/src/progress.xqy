xquery version "1.0-ml";

import module namespace spawnlib = "http://marklogic.com/spawnlib" at "lib/spawnlib.xqy";

xdmp:set-response-content-type("application/json"),
try {
	let $taskid := xdmp:get-request-field("taskid")
	return
		if ($taskid) then
			'{"success": true, "progress": ' || fn:string(spawnlib:progress($taskid)) || '}'
		else
			'{"success": true, "progress": ' || fn:string(spawnlib:progress()) || '}'
} catch ($e) {
	xdmp:log(xdmp:quote($e)),
	'{"success": false, "error": "' || $e/*:message/text() || '"}'
}