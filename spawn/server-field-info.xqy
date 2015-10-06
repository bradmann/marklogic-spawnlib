xquery version "1.0-ml";

import module namespace spawnlib = "http://marklogic.com/spawnlib" at "/spawn/lib/spawnlib.xqy";
import module namespace json="http://marklogic.com/xdmp/json" at "/MarkLogic/json/json.xqy";

xdmp:set-response-content-type("application/json"),
try {
	let $sf-map :=
		spawnlib:farm(
			$spawnlib:GET-SPAWNLIB-SERVER-FIELDS,
			(),
			spawnlib:merge-options(
				<options xmlns="xdmp:eval">
					<priority>higher</priority>
					<result>{fn:true()}</result>
					<inforest>true</inforest>
				</options>
			)
		)
	let $result-map := map:map()
	let $_ :=
		for $host-id in map:keys($sf-map)
		let $result := map:map(map:get($sf-map, $host-id)/node())
		return map:put($result-map, $host-id, $result)
	return
		json:transform-to-json(
			<json type="object" xmlns="http://marklogic.com/xdmp/json/basic">
				<success type="boolean">true</success>
				<results type="array">
				{
					for $host-id in map:keys($result-map)
					let $sf-map := map:get($result-map, $host-id)
					return
						<json type="object">
							<host-id type="string">{$host-id}</host-id>
							<fields type="array">
							{
								for $f in map:keys($sf-map)
								return
									<field type="object">
										<key type="string">{$f}</key>
										<value type="string">{map:get($sf-map, $f)}</value>
									</field>
							}
							</fields>
						</json>
				}
				</results>
			</json>
		)
} catch ($e) {
	xdmp:log(xdmp:quote($e)),
	'{"success": false, "message": "' || $e/*:message/text() || '"}'
}