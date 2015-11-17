xquery version "1.0-ml";

module namespace scl = "http://marklogic.com/spawnlib/connection/lib";

import module namespace admin = "http://marklogic.com/xdmp/admin" at "/MarkLogic/admin.xqy";
import module namespace functx = "http://www.functx.com" at "/MarkLogic/functx/functx-1.0-nodoc-2007-01.xqy";

declare function scl:post($host-id as xs:unsignedLong, $data-string as xs:string, $options as element(options)) {
	let $appserver := ($options//*:appserver/fn:string(), xdmp:server-name(xdmp:server()))[1]
	let $port := admin:appserver-get-port(admin:get-configuration(), xdmp:server($appserver))
	let $host-name := xdmp:host-name($host-id)
	let $url := 'http://' || $host-name || ':' || fn:string($port) || '/spawn/spawn-receiver.xqy'
	let $http-options :=
		<options xmlns="xdmp:http">
			<data>{$data-string}</data>
			<headers>
				<Content-type>application/xml</Content-type>
			</headers>
			<verify-cert>false</verify-cert>
			{functx:change-element-ns-deep($options//*:authentication, "xdmp:http", "")}
		</options>
	return xdmp:http-post($url, $http-options)
};