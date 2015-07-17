xquery version "1.0-ml";

module namespace spawnlib = "http://marklogic.com/spawnlib";
import module namespace admin = "http://marklogic.com/xdmp/admin" at "/MarkLogic/admin.xqy";
import module namespace functx = "http://www.functx.com" at "/MarkLogic/functx/functx-1.0-nodoc-2007-01.xqy";
import module namespace mem = "http://xqdev.com/in-mem-update" at "/MarkLogic/appservices/utils/in-mem-update.xqy";
import module namespace config = "http://marklogic.com/spawnlib/config" at "../config.xqy";
import module namespace sec = "http://marklogic.com/orion/security/lib" at "/security/lib/security-lib.xqy";

declare namespace eval = "xdmp:eval";

declare variable $debug := fn:false();

declare variable $CORB-SCRIPT := '
	xquery version "1.0-ml";
	import module namespace spawnlib = "http://marklogic.com/spawnlib" at "/spawn/lib/spawnlib.xqy";
	declare variable $uri-query external;
	declare variable $transform-query external;
	declare variable $options external;
	declare variable $name external;
	declare variable $job-id external;
	let $uris := spawnlib:inforest-eval-query($uri-query, (), ())

	let $cnt := fn:count($uris)
	let $status := if ($cnt eq 0) then
							"complete"
						else
							"running"

	let $varsmap := map:map()
	let $_ := map:put($varsmap, "job-id", $job-id)
	let $_ := map:put($varsmap, "total-tasks", $cnt)
	let $_ := map:put($varsmap, "uri-query", $uri-query)
	let $_ := map:put($varsmap, "transform-query", $transform-query)
	let $_ := map:put($varsmap, "options", $options)
	let $_ := map:put($varsmap, "name", $name)
	let $_ := map:put($varsmap, "status", $status)
	let $create-job-doc := spawnlib:inforest-eval($spawnlib:CREATE-JOBDOC, $varsmap, ())
	for $uri at $x in $uris
	return spawnlib:spawn-local($transform-query, (xs:QName("URI"), $uri, xs:QName("job-id"), $job-id, xs:QName("task-number"), $x, xs:QName("options"), $options), $options)
';

declare variable $CREATE-JOBDOC := '
	xquery version "1.0-ml";
	declare variable $job-id external;
	declare variable $total-tasks external;
	declare variable $uri-query external;
	declare variable $transform-query external;
	declare variable $name external;
	declare variable $options external;
	declare variable $status external;
	declare variable $throttle := xs:int(($options//*:throttle, 10)[1]);

	let $progress-map := map:map()
	let $_ := for $i in (1 to xs:integer($total-tasks)) return map:put($progress-map, fn:string($i), 1)
	let $_ := xdmp:set-server-field("spawnlib:progress-" || fn:string($job-id), $progress-map)
	let $_ := xdmp:set-server-field("spawnlib:throttle-" || fn:string($job-id), $throttle)
	let $host-id := fn:string(xdmp:host())
	let $host-name := xdmp:host-name()
	return
		xdmp:document-insert("/spawnlib-jobs/" || $job-id || "/" || $host-id || ".xml",
			<job xmlns="http://marklogic.com/spawnlib">
				<job-id>{$job-id}</job-id>
				<name>{$name}</name>
				<host-id>{$host-id}</host-id>
				<host-name>{$host-name}</host-name>
				<created>{fn:current-dateTime()}</created>
				<status>{$status}</status>
				{ if ($status eq "complete") then
					<completed>{fn:current-dateTime()}</completed>
				else ()
				}<total>{$total-tasks}</total>
				<throttle>{$throttle}</throttle>
				<uri-query>{$uri-query}</uri-query>
				<transform-query>{$transform-query}</transform-query>
				<options>{$options}</options>
			</job>
		)
';

declare variable $SINGLE-TASK-COMPLETE := '
	xquery version "1.0-ml";
	declare namespace spawnlib = "http://marklogic.com/spawnlib";
	declare variable $job-id external;
	declare variable $task-number external;
	declare variable $host-id := fn:string(xdmp:host());
	let $progress-uri := "/spawnlib-jobs/" || $job-id || "/" || $host-id || ".xml"
	let $_ := xdmp:lock-for-update($progress-uri)
	let $progress-map := xdmp:get-server-field("spawnlib:progress-" || $job-id)
	return
		(
			map:put($progress-map, xs:string($task-number), ()),
			if (map:count($progress-map) eq 0 and $task-number ne 0) then
				(
					xdmp:set-server-field("spawnlib:progress-" || $job-id, ()),
					xdmp:set-server-field("spawnlib:kill-" || $job-id, ()),
					xdmp:set-server-field("spawnlib:throttle-" || $job-id, ()),
					xdmp:node-replace(fn:doc($progress-uri)//spawnlib:status/text(), text{"complete"}),
					xdmp:node-insert-after(fn:doc($progress-uri)/spawnlib:job/spawnlib:status, <spawnlib:completed>{fn:current-dateTime()}</spawnlib:completed>)
				)
			else ()
		)
';

declare variable $CHECK-PROGRESS := '
	xquery version "1.0-ml";
	declare variable $job-id-map external;
	let $result-map := map:map()
	let $_ :=
		for $job-id in map:keys($job-id-map)
		let $progress-map := xdmp:get-server-field("spawnlib:progress-" || $job-id)
		let $count := (map:count($progress-map), 0)[1]
		return map:put($result-map, $job-id, $count)
	return <x>{$result-map}</x>/node()
';

declare variable $POISON-PILL := '
	xquery version "1.0-ml";
	declare variable $job-id external;
	declare variable $host-id := fn:string(xdmp:host());
	if ($job-id eq 0) then
		for $progress-doc in xdmp:directory("/spawnlib-jobs/", "infinity")[.//*:status eq "running"]
		return
			(
				xdmp:set-server-field("spawnlib:kill-" || $progress-doc//*:job-id/fn:string(), fn:true()),
				xdmp:node-replace($progress-doc//*:status/text(), text{"killed"})
			)
	else
		let $progress-doc := fn:doc("/spawnlib-jobs/" || $job-id || "/" || $host-id || ".xml")
		return
			if ($progress-doc//*:status eq "running") then
				(
					xdmp:set-server-field("spawnlib:kill-" || fn:string($job-id), fn:true()),
					xdmp:node-replace($progress-doc//*:status/text(), text{"killed"})
				)
			else ()
';

declare variable $SET-THROTTLE := '
	xquery version "1.0-ml";
	declare variable $job-id external;
	declare variable $throttle external;
	declare variable $host-id := fn:string(xdmp:host());
	if ($job-id eq 0) then
		for $progress-doc in xdmp:directory("/spawnlib-jobs/", "infinity")[.//*:status eq "running"]
		return
			(
				xdmp:set-server-field("spawnlib:throttle-" || $progress-doc//*:job-id/fn:string(), $throttle),
				xdmp:node-replace($progress-doc//*:throttle/text(), text{$throttle})
			)
	else
		let $progress-doc := fn:doc("/spawnlib-jobs/" || $job-id || "/" || $host-id || ".xml")
		return
			if ($progress-doc//*:status eq "running") then
				(
					xdmp:set-server-field("spawnlib:throttle-" || fn:string($job-id), $throttle),
					xdmp:node-replace($progress-doc//*:throttle/text(), text{$throttle})
				)
			else ()
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
		functx:remove-elements-deep($options, ("inforest", "appserver", "database", "priority", "result", "authentication", "throttle"))
	)
};

declare function spawnlib:inforest-eval($q as xs:string, $varsmap as map:map?, $options as node()?) {
	xdmp:eval(
		$q,
		(for $key in map:keys($varsmap) return (xs:QName($key), map:get($varsmap, $key))),
		<options xmlns="xdmp:eval">
			{functx:remove-elements-deep($options, ("inforest", "appserver", "database", "priority", "result", "authentication", "throttle"))/node()}
			<database>{spawnlib:forest-ids-to-string($local-forests)}</database>
		</options>
	)
};

declare function spawnlib:inforest-eval-query($q as xs:string, $varsmap as map:map?, $options as node()?) {
	xdmp:eval(
		$q,
		(for $key in map:keys($varsmap) return (xs:QName($key), map:get($varsmap, $key))),
		<options xmlns="xdmp:eval">
			{functx:remove-elements-deep($options, ("inforest", "appserver", "database", "priority", "result", "authentication", "throttle"))/node()}
			<database>{spawnlib:forest-ids-to-string($local-forests)}</database>
			<transaction-mode>query</transaction-mode>
		</options>
	)
};

declare function spawnlib:spawn-local-task($q as xs:string, $varsmap as map:map, $options as node()?) {
	xdmp:spawn-function(
		function() {
			let $job-id := map:get($varsmap, "job-id")
			let $kill := xs:boolean(xdmp:get-server-field("spawnlib:kill", fn:false())) or xs:boolean(xdmp:get-server-field("spawnlib:kill-" || $job-id, fn:false()))
			let $priority := ($options//*:priority/fn:string(), "normal")[1]
			let $inforest := xs:boolean(($options//*:inforest/fn:string(), "false")[1])
			let $throttle := xdmp:get-server-field("spawnlib:throttle-" || $job-id)
			let $_ := if ($throttle lt 10) then xdmp:sleep(xs:int((xs:double(1) div $throttle) * 1000)) else ()
			return
				if ($kill and ($priority = "normal")) then
					()
				else
					(
						if ($inforest) then
							spawnlib:inforest-eval($q, $varsmap, $options)
						else
							spawnlib:eval($q, $varsmap, $options),
						if ($job-id eq 0 or $priority eq "higher") then () else spawnlib:inforest-eval($SINGLE-TASK-COMPLETE, $varsmap, ()),
						xdmp:commit()
					)
		},
		functx:remove-elements-deep($options, ("inforest", "appserver", "authentication", "throttle"))
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

declare function spawnlib:farm($q as xs:string, $vars as item()*, $options as node()?) {
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
			{functx:change-element-ns-deep($options//*:authentication, "xdmp:http", "")}
		</options>
	let $appserver := ($options//*:appserver/fn:string(), xdmp:server-name(xdmp:server()))[1]
	let $port := admin:appserver-get-port(admin:get-configuration(), xdmp:server($appserver))
	let $result-map := map:map()
	let $_ :=
		for $host-id in $host-ids
		let $host-name := xdmp:host-name($host-id)
		let $url := 'https://' || $host-name || ':' || fn:string($port) || '/spawn/spawn-receiver.xqy'
		let $result := sec:https-post($url, $http-options/node(), $appserver, fn:true())
		return
			if ($result[1]//*:code/fn:string() eq "200") then
				let $res := $result[2]
				let $res := if (fn:string-length($res) = 0) then () else $res
				return map:put($result-map, fn:string($host-id), $res)
			else
				fn:error(xs:QName("SPAWNLIB-HTTP"), "Error farming job to cluster")
	return $result-map
};

declare function spawnlib:corb($uri-query as xs:string, $transform-query as xs:string) {
	spawnlib:corb($uri-query, $transform-query, (), ())
};

declare function spawnlib:corb($uri-query as xs:string, $transform-query as xs:string, $options as node()?) {
	spawnlib:corb($uri-query, $transform-query, "", $options)
};

declare function spawnlib:corb($uri-query as xs:string, $transform-query as xs:string, $name as xs:string, $options as node()?) {
	let $job-id := xdmp:hash64(fn:string(fn:current-dateTime()))
	let $options := spawnlib:merge-options($options)
	let $result-map :=
		spawnlib:farm(
			$CORB-SCRIPT,
			(xs:QName('uri-query'), $uri-query, xs:QName('transform-query'), $transform-query, xs:QName('job-id'), $job-id, xs:QName('task-number'), 0, xs:QName('name'), $name, xs:QName('options'), $options),
			<options xmlns="xdmp:eval">
			{
				functx:remove-elements-deep($options, ("inforest", "result"))/node()
			}
			</options>
		)
	return $job-id
};

declare function spawnlib:merge-options($options as element()?) {
	let $config-options := $config:OPTIONS
	let $_ :=
		for $node in $options/node()
		return
			if (fn:local-name($node) eq $config-options/node()/fn:local-name(.)) then
				xdmp:set($config-options, mem:node-replace($config-options/node()[fn:local-name(.) eq fn:local-name($node)], $node))
			else
				xdmp:set($config-options, mem:node-insert-child($config-options, $node))
	return $config-options

};

declare function spawnlib:check-progress() {
	spawnlib:check-progress(())
};

declare function spawnlib:check-progress($job-id as xs:unsignedLong?) {
	let $job-ids :=
		if (fn:empty($job-id)) then
			cts:element-values(xs:QName("spawnlib:job-id"), (), (), ())
		else if (xdmp:estimate(cts:search(/, cts:element-range-query(xs:QName("spawnlib:job-id"), "=", $job-id))) gt 0) then
			$job-id
		else
			()
	let $job-id-map := map:map()
	let $_ := for $job-id in $job-ids return map:put($job-id-map, fn:string($job-id), 1)
	let $progress-map := 
			spawnlib:farm(
				$CHECK-PROGRESS,
				(xs:QName("job-id-map"), $job-id-map),
				spawnlib:merge-options(
					<options xmlns="xdmp:eval">
						<priority>higher</priority>
						<result>{fn:true()}</result>
						<inforest>true</inforest>
					</options>
				)
			)
	let $_ :=
		for $host-id in map:keys($progress-map)
		let $result := map:map(map:get($progress-map, $host-id)/node())
		return map:put($progress-map, $host-id, $result)

	let $q := cts:element-range-query(xs:QName("spawnlib:job-id"), "=", $job-ids)
	let $job-name-map := cts:element-value-co-occurrences(xs:QName("spawnlib:job-id"), xs:QName("spawnlib:name"), ("map"), $q)
	let $job-totals-map := cts:element-value-co-occurrences(xs:QName("spawnlib:job-id"), xs:QName("spawnlib:total"), ("map"), $q)
	let $job-status-map := cts:element-value-co-occurrences(xs:QName("spawnlib:job-id"), xs:QName("spawnlib:status"), ("map"), $q)
	let $job-created-map := cts:element-value-co-occurrences(xs:QName("spawnlib:job-id"), xs:QName("spawnlib:created"), ("map"), $q)
	let $job-completed-map := cts:element-value-co-occurrences(xs:QName("spawnlib:job-id"), xs:QName("spawnlib:completed"), ("map"), $q)
	let $job-uriquery-map := cts:element-value-co-occurrences(xs:QName("spawnlib:job-id"), xs:QName("spawnlib:uri-query"), ("map"), $q)
	let $job-transformquery-map := cts:element-value-co-occurrences(xs:QName("spawnlib:job-id"), xs:QName("spawnlib:transform-query"), ("map"), $q)
	let $job-throttle-map := cts:element-value-co-occurrences(xs:QName("spawnlib:job-id"), xs:QName("spawnlib:throttle"), ("map"), $q)

	let $job-objects :=
		for $job-id in $job-ids
		let $name := map:get($job-name-map, fn:string($job-id))
		let $total-progress := fn:sum(for $host-id in map:keys($progress-map) return xs:unsignedLong(map:get(map:get($progress-map, $host-id), fn:string($job-id))))
		let $total-tasks := fn:sum(map:get($job-totals-map, fn:string($job-id)))
		let $statuses := map:get($job-status-map, fn:string($job-id))
		let $overall-status := if ($statuses = "running") then "running" else if ($statuses = "killed") then "killed" else "complete"
		let $created-date := fn:min(map:get($job-created-map, fn:string($job-id)))
		let $completed-dateTimes := map:get($job-completed-map, fn:string($job-id))
		let $uri-query := map:get($job-uriquery-map, fn:string($job-id))[1]
		let $transform-query := map:get($job-transformquery-map, fn:string($job-id))[1]
		let $throttle := (map:get($job-throttle-map, fn:string($job-id))[1], 10)[1]
		order by $created-date descending
		return
			<json type="object" xmlns="http://marklogic.com/xdmp/json/basic">
				<id type="string">{$job-id}</id>
				<name type="string">{$name}</name>
				<status type="string">{$overall-status}</status>
				<progress type="number">{$total-tasks - $total-progress}</progress>
				<throttle type="number">{$throttle}</throttle>
				<total type="number">{$total-tasks}</total>
				<created type="string">{$created-date}</created>
				{
					if (fn:count($completed-dateTimes) eq map:count($progress-map)) then
						<completed type="string">{fn:max($completed-dateTimes)}</completed>
					else
						()
				}
				<uriquery type="string">{$uri-query}</uriquery>
				<transformquery type="string">{$transform-query}</transformquery>
				<hoststatus type="object">
				{
					let $job-query := cts:element-range-query(xs:QName("spawnlib:job-id"), "=", $job-id)
					let $host-status-map := cts:element-value-co-occurrences(xs:QName("spawnlib:host-id"), xs:QName("spawnlib:status"), ("map"), $job-query)
					let $host-total-map := cts:element-value-co-occurrences(xs:QName("spawnlib:host-id"), xs:QName("spawnlib:total"), ("map"), $job-query)
					let $host-created-map := cts:element-value-co-occurrences(xs:QName("spawnlib:host-id"), xs:QName("spawnlib:created"), ("map"), $job-query)
					let $host-completed-map := cts:element-value-co-occurrences(xs:QName("spawnlib:host-id"), xs:QName("spawnlib:completed"), ("map"), $job-query)
					for $host-id in map:keys($progress-map)
					let $hostname := xdmp:host-name(xs:unsignedLong($host-id))
					return
						element {fn:QName("http://marklogic.com/xdmp/json/basic", $hostname)} {
							attribute type {"object"},
							<status type="string">{map:get($host-status-map, $host-id)}</status>,
							<progress type="number">{map:get($host-total-map, $host-id) - map:get(map:get($progress-map, $host-id), fn:string($job-id))}</progress>,
							<total type="number">{map:get($host-total-map, $host-id)}</total>,
							<created type="string">{map:get($host-created-map, $host-id)}</created>,
							if (fn:exists(map:get($host-completed-map, $host-id))) then
								<completed type="string">{map:get($host-completed-map, $host-id)}</completed>
							else
								()
						}
				}
				</hoststatus>
			</json>
	return
		<json type="object" xmlns="http://marklogic.com/xdmp/json/basic">
			<success type="boolean">true</success>
			<results type="array">{$job-objects}</results>
		</json>

};

declare function spawnlib:kill() {
	spawnlib:kill(())
};

declare function spawnlib:kill($job-id as xs:unsignedLong?) {
	let $kill-map :=
		spawnlib:farm(
			$POISON-PILL,
			(xs:QName("job-id"), ($job-id, 0)[1]),
			spawnlib:merge-options(
				<options xmlns="xdmp:eval">
					<priority>higher</priority>
					<result>{fn:true()}</result>
				</options>
			)
		)
	return
		<json type="object" xmlns="http://marklogic.com/xdmp/json/basic">
			<success type="boolean">true</success>
		</json>
};

declare function spawnlib:throttle($throttle as xs:integer) {
	spawnlib:throttle((), $throttle)
};

declare function spawnlib:throttle($job-id as xs:unsignedLong?, $throttle as xs:integer) {
	if ($throttle gt 10 or $throttle lt 1) then
		<json type="object" xmlns="http://marklogic.com/xdmp/json/basic">
			<success type="boolean">false</success>
			<message>Throttle must be an integer between 1 and 10</message>
		</json>
	else
		let $throttle-map :=
			spawnlib:farm(
				$SET-THROTTLE,
				(xs:QName("job-id"), ($job-id, 0)[1], xs:QName("throttle"), $throttle),
				spawnlib:merge-options(
					<options xmlns="xdmp:eval">
						<priority>higher</priority>
						<result>{fn:true()}</result>
					</options>
				)
			)
		return
			<json type="object" xmlns="http://marklogic.com/xdmp/json/basic">
				<success type="boolean">true</success>
			</json>
};

declare function spawnlib:remove() {
	spawnlib:kill(())
};

declare function spawnlib:remove($job-id as xs:unsignedLong?) {
	let $remove :=
		if (fn:exists($job-id)) then
			xdmp:directory-delete("/spawnlib-jobs/" || fn:string($job-id) || "/")
		else
			xdmp:directory-delete("/spawnlib-jobs/")
	return
		<json type="object" xmlns="http://marklogic.com/xdmp/json/basic">
			<success type="boolean">true</success>
		</json>
};