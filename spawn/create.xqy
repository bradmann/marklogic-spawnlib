xquery version "1.0-ml";

import module namespace spawnlib = "http://marklogic.com/spawnlib" at "/spawn/lib/spawnlib.xqy";
import module namespace json="http://marklogic.com/xdmp/json" at "/MarkLogic/json/json.xqy";

declare option xdmp:update "true";

xdmp:set-response-content-type("application/json"),
try {
	let $uris-query := xdmp:get-request-field("uris-query")
	let $xform-query := xdmp:get-request-field("xform-query")
	let $inforest := xs:boolean((xdmp:get-request-field("inforest"), "true")[1])
	let $throttle := xs:integer((xdmp:get-request-field("throttle"), 10)[1])

	let $options :=
		<options xmlns="xdmp:eval">
			<inforest>{$inforest}</inforest>
			<throttle>{$throttle}</throttle>
		</options>

	let $response := spawnlib:corb($uris-query, $xform-query, "Spawn UI", $options)
	let $id := $response[1]

	let $response :=
		<json type="object" xmlns="http://marklogic.com/xdmp/json/basic">
			<success type="boolean">true</success>
			<message type="string">Successfully created spawnlib task ID: {$id}</message>
			<id type="number">{$id}</id>
		</json>

	return
		json:transform-to-json($response)
} catch ($e) {
	xdmp:log(xdmp:quote($e)),
	'{"success": false, "message": "' || $e/*:message/text() || '"}'
}