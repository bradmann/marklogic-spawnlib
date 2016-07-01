xquery version "1.0-ml";

import module namespace spawnlib = "http://marklogic.com/spawnlib" at "/spawn/lib/spawnlib.xqy";
import module namespace json="http://marklogic.com/xdmp/json" at "/MarkLogic/json/json.xqy";

declare option xdmp:update "true";

xdmp:set-response-content-type("application/json"),
try {
	let $job-id := xs:unsignedLong(xdmp:get-request-field("job-id"))
	let $throttle := xs:int(xdmp:get-request-field("throttle"))
	return
		if ($job-id) then
			spawnlib:throttle($job-id, $throttle)
		else
			spawnlib:throttle($throttle)
} catch ($e) {
	xdmp:log(xdmp:quote($e)),
	object-node {"success": fn:false(), "message": $e/*:message/fn:string()}
}