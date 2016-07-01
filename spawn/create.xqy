xquery version "1.0-ml";

import module namespace spawnlib = "http://marklogic.com/spawnlib" at "/spawn/lib/spawnlib.xqy";
import module namespace json="http://marklogic.com/xdmp/json" at "/MarkLogic/json/json.xqy";

declare option xdmp:update "true";

xdmp:set-response-content-type("application/json"),
try {
	let $uris-query := xdmp:get-request-field("uris-query")
	let $xform-query := xdmp:get-request-field("xform-query")
	let $inforest := xs:boolean((xdmp:get-request-field("inforest"), "true")[1])
	let $language := fn:lower-case((xdmp:get-request-field("language"), "xquery")[1])
	let $throttle := xs:integer((xdmp:get-request-field("throttle"), 10)[1])

	let $options :=
		<options xmlns="xdmp:eval">
			<inforest>{$inforest}</inforest>
			<throttle>{$throttle}</throttle>
			<language>{$language}</language>
		</options>

	let $response := spawnlib:corb($uris-query, $xform-query, "Spawn UI", $options)
	let $id := $response[1]

	return object-node {
		"success": fn:true(),
		"message": "Successfully created spawnlib task ID: " || $id,
		"id": $id
	}
} catch ($e) {
	xdmp:log(xdmp:quote($e)),
	object-node {"success": fn:false(), "message": $e/*:message/fn:string()}
}