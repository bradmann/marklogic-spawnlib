xquery version "1.0-ml";

import module namespace spawnlib = "http://marklogic.com/spawnlib" at "/spawn/lib/spawnlib.xqy";
import module namespace json="http://marklogic.com/xdmp/json" at "/MarkLogic/json/json.xqy";

xdmp:set-response-content-type("application/json"),
try {
	let $job-id := xs:unsignedLong(xdmp:get-request-field("job-id"))
	let $detail := (xdmp:get-request-field("detail"), "normal")[1]
	let $start := xs:integer((xdmp:get-request-field("start"), "1")[1])
	let $end := xs:integer((xdmp:get-request-field("end"), "10")[1])
	return json:transform-to-json(spawnlib:check-progress($job-id, $detail, $start, $end))
} catch ($e) {
	xdmp:log(xdmp:quote($e)),
	'{"success": false, "message": "' || $e/*:message/text() || '"}'
}