xquery version "1.0-ml";

import module namespace spawnlib = "http://marklogic.com/spawnlib" at "spawnlib.xqy";

declare variable $SPAWNLIB-QUERY as xs:string external;
declare variable $SPAWNLIB-VARS as map:map external;
declare variable $SPAWNLIB-OPTIONS as node() external;

declare variable $KILL := if ($SPAWNLIB-OPTIONS//*:priority = "higher") then fn:false() else xdmp:get-server-field("spawnlib:kill", fn:false());

declare variable $UPDATE-PROGRESS :=
	let $current := xdmp:get-server-field("spawnlib:progress", 0)
	return xdmp:set-server-field("spawnlib:progress", $current + 1)
;

if (fn:not($KILL)) then
	spawnlib:eval($SPAWNLIB-QUERY, $SPAWNLIB-VARS, $SPAWNLIB-OPTIONS)
else
	()