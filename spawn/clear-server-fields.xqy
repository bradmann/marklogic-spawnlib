xquery version "1.0-ml";

import module namespace spawnlib = "http://marklogic.com/spawnlib" at "/spawn/lib/spawnlib.xqy";
import module namespace json="http://marklogic.com/xdmp/json" at "/MarkLogic/json/json.xqy";

xdmp:set-response-content-type("application/json"),
try {
		spawnlib:clear-server-fields()
} catch ($e) {
	xdmp:log(xdmp:quote($e)),
	object-node {"success": fn:false(), "message": $e/*:message/fn:string()}
}