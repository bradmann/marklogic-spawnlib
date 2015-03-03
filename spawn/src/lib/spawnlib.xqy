xquery version "1.0-ml";

module namespace spawnlib = "http://marklogic.com/spawnlib";
import module namespace admin = "http://marklogic.com/xdmp/admin" at "/MarkLogic/admin.xqy";
import module namespace functx = "http://www.functx.com" at "/MarkLogic/functx/functx-1.0-nodoc-2007-01.xqy";

declare namespace eval = "xdmp:eval";

declare variable $CORB-SCRIPT := '
	xquery version "1.0-ml";
	import module namespace spawnlib = "http://marklogic.com/spawnlib" at "/spawn/lib/spawnlib.xqy";
	declare variable $uri-query external;
	declare variable $transform-query external;
	declare variable $options external;
	let $uris := spawnlib:inforest-eval-query($uri-query, (), ())
	for $uri at $x in $uris
	return spawnlib:spawn-local($transform-query, (xs:QName("URI"), $uri), $options)
';

declare variable $RESET := '
	xquery version "1.0-ml";
	xdmp:set-server-field("spawnlib:kill", fn:false())
';

declare variable $POISON-PILL := '
	xquery version "1.0-ml";
	xdmp:set-server-field("spawnlib:kill", fn:true())
';

declare variable $database :=
    xdmp:database()
;

declare variable $local-forests as xs:unsignedLong* := 
  let $forests := xdmp:get-server-field("local-forests-" || fn:string(xdmp:host()) || "-" || fn:string($database))
  return
      if (fn:exists($forests)) then
        $forests
      else
        let $retval := spawnlib:lookup-local-forests()
        let $set := xdmp:set-server-field("local-forests-" || fn:string(xdmp:host()) || "-" || fn:string($database), $retval)
        return $retval

;

declare function spawnlib:sequence-to-map($items as item()*) as map:map* {
	let $m := map:map()
	let $_ :=
		for $item at $i in $items
		let $idx := $i + 1
		return if ($i mod 2 eq 1) then map:put($m, $item, $items[$idx]) else ()
	return $m
};

declare function spawnlib:lookup-local-forests() as xs:unsignedLong* {
    spawnlib:lookup-forests(xdmp:host())
};

declare function spawnlib:lookup-forests($host as xs:unsignedLong) as xs:unsignedLong* {
    let $config := admin:get-configuration()
    return
      xdmp:database-forests($database)[admin:forest-get-host($config, .) eq $host]
};

declare function spawnlib:forest-ids-to-string($forests as xs:unsignedLong+) as xs:string {
    (: we need to make sure that the forest ids in the list are distinct :)
    (: because passing in the same id more than once will cause the forest :)
    (: to be accessed multiple times and could induce a duplicate URI exception :)
    fn:string-join(for $i in fn:distinct-values($forests) return fn:string($i), " ")
};

declare function spawnlib:eval($q as xs:string, $varsmap as map:map?, $options as node()?) {
	xdmp:eval(
		$q,
		(for $key in map:keys($varsmap) return (xs:QName($key), map:get($varsmap, $key))),
		functx:remove-elements-deep($options, ("inforest", "appserver", "database", "priority", "result", "taskid", "batchsize"))
	)
};

declare function spawnlib:inforest-eval($q as xs:string, $varsmap as map:map?, $options as node()?) {
	xdmp:eval(
		$q,
		(for $key in map:keys($varsmap) return (xs:QName($key), map:get($varsmap, $key))),
		<options xmlns="xdmp:eval">
			{functx:remove-elements-deep($options, ("inforest", "appserver", "database", "priority", "result", "taskid", "batchsize"))/node()}
			<database>{spawnlib:forest-ids-to-string($local-forests)}</database>
		</options>
	)
};

declare function spawnlib:inforest-eval-query($q as xs:string, $varsmap as map:map?, $options as node()?) {
	xdmp:eval(
		$q,
		(for $key in map:keys($varsmap) return (xs:QName($key), map:get($varsmap, $key))),
		<options xmlns="xdmp:eval">
			{functx:remove-elements-deep($options, ("inforest", "appserver", "database", "priority", "result", "taskid", "batchsize"))/node()}
			<database>{spawnlib:forest-ids-to-string($local-forests)}</database>
			<transaction-mode>query</transaction-mode>
		</options>
	)
};

declare function spawnlib:spawn-local-task($q as xs:string, $varsmap as map:map, $options as node()?) {
	xdmp:spawn-function(
		function() {
			let $taskid := $options//*:taskid/text()
			let $kill := xs:boolean(xdmp:get-server-field("spawnlib:kill", fn:false()))
			let $priority := ($options//*:priority/fn:string(), "normal")[1]
			return
				if ($kill and ($priority = "normal")) then
					()
				else
					spawnlib:eval($q, $varsmap, $options),
			xdmp:commit()
		},
		functx:remove-elements-deep($options, ("inforest", "appserver", "taskid", "batchsize"))
	)
};

declare function spawnlib:spawn-local($q as xs:string, $vars as item()*, $options as node()?) {
	let $varsmap := map:map()
	let $options := if ($options) then $options else <options xmlns="xdmp:eval"/>
	let $_ :=
		for $item at $x in $vars
		return if ($x mod 2 != 0) then map:put($varsmap, fn:string($item), $vars[$x + 1]) else ()
	return spawnlib:spawn-local-task($q, $varsmap, $options)
};

declare function spawnlib:spawn($q as xs:string, $vars as item()*, $options as node()?) {
	let $varsmap := map:map()
	let $options := if (fn:exists($options)) then $options else <options xmlns="xdmp:eval"/>
	let $_ :=
		for $item at $x in $vars
		return if ($x mod 2 != 0) then map:put($varsmap, fn:string($item), $vars[$x + 1]) else ()
	let $group := xdmp:group()
	let $host-ids := xdmp:group-hosts($group)
	let $data-map := map:map()
	let $_ := map:put($data-map, 'query', $q)
	let $_ := map:put($data-map, 'vars', $varsmap)
	let $_ := map:put($data-map, 'options', $options)
	let $data-string := xdmp:quote(<x>{$data-map}</x>/node())
	let $http-options :=
		<options xmlns="xdmp:http">
			<data>{$data-string}</data>
			<headers>
				<Content-type>application/xml</Content-type>
			</headers>
			<verify-cert>false</verify-cert>
		</options>
	let $appserver := ($options//*:appserver/fn:string(), xdmp:server-name(xdmp:server()))[1]
	let $port := admin:appserver-get-port(admin:get-configuration(), xdmp:server($appserver))
	for $host-id in $host-ids
	let $host-name := xdmp:host-name($host-id)
	let $url := 'http://' || $host-name || ':' || fn:string($port) || '/spawn/spawn-receiver.xqy'
	return xdmp:http-post($url, $http-options)
};

declare function spawnlib:corb($uri-query as xs:string, $transform-query as xs:string, $options as node()?) {
	let $taskid := xdmp:hash64(fn:string(fn:current-dateTime()))
	let $options := if (fn:exists($options)) then $options else <options xmlns="xdmp:eval"/>
	let $options :=
		<options xmlns="xdmp:eval">
		{
			$options/node(),
			<taskid>{$taskid}</taskid>
		}
		</options>
	let $_resume := spawnlib:resume($options)
	return (
		$taskid,
		spawnlib:spawn(
			$CORB-SCRIPT,
			(xs:QName('uri-query'), $uri-query, xs:QName('transform-query'), $transform-query, xs:QName('options'), $options),
			<options xmlns="xdmp:eval">
			{
				<inforest>true</inforest>,
				functx:remove-elements-deep($options, ("inforest", "taskid"))/node()
			}
			</options>
		)
	)
};

declare function spawnlib:resume() {
	spawnlib:resume(())
};

declare function spawnlib:resume($options as node()?) {
	spawnlib:spawn(
		$RESET,
		(),
		<options xmlns="xdmp:eval">
		{
			functx:remove-elements-deep($options, ("priority"))/node(),
			<priority>higher</priority>
		}
		</options>
	)
};

declare function spawnlib:kill() {
	spawnlib:kill(())
};

declare function spawnlib:kill($options as node()?) {
	spawnlib:spawn(
		$POISON-PILL,
		(),
		<options xmlns="xdmp:eval">
		{
			functx:remove-elements-deep($options, "priority")/node(),
			<priority>higher</priority>
		}
		</options>
	)
};