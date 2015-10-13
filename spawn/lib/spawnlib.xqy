xquery version "1.0-ml";

module namespace spawnlib = "http://marklogic.com/spawnlib";
import module namespace admin = "http://marklogic.com/xdmp/admin" at "/MarkLogic/admin.xqy";
import module namespace functx = "http://www.functx.com" at "/MarkLogic/functx/functx-1.0-nodoc-2007-01.xqy";
import module namespace mem = "http://xqdev.com/in-mem-update" at "/MarkLogic/appservices/utils/in-mem-update.xqy";
import module namespace config = "http://marklogic.com/spawnlib/config" at "../config.xqy";

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
	declare variable $throttle := xs:int(($options//*:throttle, 10)[1]);
	declare variable $language := ($options//*:language, "xquery")[1];
	let $error := ()
	let $varsmap := map:map()
	let $_ := map:put($varsmap, "job-id", $job-id)
	let $_ := map:put($varsmap, "uri-query", $uri-query)
	let $_ := map:put($varsmap, "transform-query", $transform-query)
	let $_ := map:put($varsmap, "options", $options)
	let $_ := map:put($varsmap, "name", $name)
	let $_ := map:put($varsmap, "throttle", $throttle)
	let $create-job-doc := spawnlib:inforest-eval($spawnlib:CREATE-JOBDOC, $varsmap, ())
	let $uris :=
		try {
			spawnlib:inforest-eval-query($uri-query, (), (), $language)
		} catch ($e) {
			xdmp:set($error, $e)
		}
	let $uris := if ($language = "javascript") then json:array-values($uris, fn:true()) else $uris
	let $cnt := fn:count($uris)
	let $status :=
		if ($cnt eq 0 and fn:empty($error)) then
			"complete"
		else if ($cnt eq 0) then
			"error"
		else
			"running"

	let $_ := map:put($varsmap, "total-tasks", $cnt)
	let $_ := map:put($varsmap, "status", $status)
	let $_ := map:put($varsmap, "error", $error)
	let $init-job-doc := spawnlib:inforest-eval($spawnlib:INIT-JOBDOC, $varsmap, ())
	for $uri at $x in $uris
	return spawnlib:spawn-local($transform-query, (xs:QName("URI"), $uri, xs:QName("job-id"), $job-id, xs:QName("task-number"), $x), $options)
';

declare variable $CREATE-JOBDOC := '
	xquery version "1.0-ml";
	declare variable $job-id external;
	declare variable $uri-query external;
	declare variable $transform-query external;
	declare variable $name external;
	declare variable $options external;
	declare variable $throttle external;

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
				<status>initializing</status>
				<throttle>{$throttle}</throttle>
				<uri-query>{$uri-query}</uri-query>
				<transform-query>{$transform-query}</transform-query>
				<inforest>{($options//*:inforest/fn:string(), "false")[1]}</inforest>
				<language>{($options//*:language/fn:string(), "xquery")[1]}</language>
				<options>{$options}</options>
			</job>
		)
';

declare variable $INIT-JOBDOC := '
	xquery version "1.0-ml";
	declare namespace spawnlib = "http://marklogic.com/spawnlib";
	declare variable $job-id external;
	declare variable $total-tasks external;
	declare variable $status external;
	declare variable $error external := ();
	declare variable $throttle external;

	let $progress-map := map:map()
	let $_ := for $i in (1 to xs:integer($total-tasks)) return map:put($progress-map, fn:string($i), 1)
	let $_ :=
		if ($status eq "running") then
			(
				xdmp:set-server-field("spawnlib:progress-" || fn:string($job-id), $progress-map),
				xdmp:set-server-field("spawnlib:throttle-" || fn:string($job-id), $throttle)
			)
		else
			()
	let $host-id := fn:string(xdmp:host())
	let $jobdocuri := "/spawnlib-jobs/" || $job-id || "/" || $host-id || ".xml"
	let $_ := xdmp:lock-for-update($jobdocuri)
	let $jobdoc := fn:doc($jobdocuri)
	return (
		xdmp:node-replace($jobdoc/spawnlib:job/spawnlib:status/text(), text {$status})
		,
		if ($status eq "complete") then
			xdmp:node-insert-child($jobdoc/spawnlib:job, <spawnlib:completed>{fn:current-dateTime()}</spawnlib:completed>)
		else ()
		,
		xdmp:node-insert-child($jobdoc/spawnlib:job, <spawnlib:total>{$total-tasks}</spawnlib:total>)
		,
		if (fn:exists($error)) then
			xdmp:node-insert-child($jobdoc/spawnlib:job, <spawnlib:uri-error>{$error}</spawnlib:uri-error>)
		else ()
	)
';

declare variable $SINGLE-TASK-COMPLETE := '
	xquery version "1.0-ml";
	declare namespace spawnlib = "http://marklogic.com/spawnlib";
	declare namespace error = "http://marklogic.com/xdmp/error";
	declare variable $job-id external;
	declare variable $task-number external;
	declare variable $error external := ();
	declare variable $URI external;
	declare variable $host-id := fn:string(xdmp:host());
	let $progress-uri := "/spawnlib-jobs/" || $job-id || "/" || $host-id || ".xml"
	let $_ := xdmp:lock-for-update($progress-uri)
	let $progress-map := xdmp:get-server-field("spawnlib:progress-" || $job-id)
	let $error-map := (xdmp:get-server-field("spawnlib:error-" || $job-id), map:map())[1]
	return
		(
			map:put($progress-map, xs:string($task-number), ()),
			if (fn:exists($error) and map:count($error-map) lt 10) then
				let $_ := map:put($error-map, fn:string($URI), $error/error:format-string/fn:string())
				return xdmp:set-server-field("spawnlib:error-" || $job-id, $error-map)
			else (),
			if (map:count($progress-map) eq 0 and $task-number ne 0) then
				(: The whole job is done. Clean up. :)
				(
					xdmp:set-server-field("spawnlib:progress-" || $job-id, ()),
					xdmp:set-server-field("spawnlib:throttle-" || $job-id, ()),
					xdmp:set-server-field("spawnlib:kill-" || $job-id, ()),
					if (map:count($error-map) gt 0) then
						xdmp:node-replace(fn:doc($progress-uri)//spawnlib:status/text(), text{"error"})
					else
						xdmp:node-replace(fn:doc($progress-uri)//spawnlib:status/text(), text{"complete"}),
					xdmp:node-insert-after(fn:doc($progress-uri)/spawnlib:job/spawnlib:status, <spawnlib:completed>{fn:current-dateTime()}</spawnlib:completed>),
					if (map:count($error-map) gt 0) then xdmp:node-insert-child(fn:doc($progress-uri)/spawnlib:job, <spawnlib:transform-errors>{<x>{$error-map}</x>/node()}</spawnlib:transform-errors>) else (),
					xdmp:set-server-field("spawnlib:error-" || $job-id, ())
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
		let $job-result-map := map:map()
		let $progress-map := xdmp:get-server-field("spawnlib:progress-" || $job-id)
		let $error-map := (xdmp:get-server-field("spawnlib:error-" || $job-id), map:map())[1]
		let $count := (map:count($progress-map), 0)[1]
		let $_ := map:put($job-result-map, "count", $count)
		let $_ := map:put($job-result-map, "errors", $error-map)
		return map:put($result-map, $job-id, $job-result-map)
	return <x>{$result-map}</x>/node()
';

declare variable $POISON-PILL := '
	xquery version "1.0-ml";
	declare namespace spawnlib = "http://marklogic.com/spawnlib";
	declare variable $job-id external;
	declare variable $host-id := fn:string(xdmp:host());
	if ($job-id eq 0) then
		for $progress-doc in xdmp:directory("/spawnlib-jobs/", "infinity")[.//*:status eq "running" or .//*:status eq "initializing"]
		return
			(
				xdmp:set-server-field("spawnlib:kill-" || $progress-doc//*:job-id/fn:string(), fn:true()),
				xdmp:node-replace($progress-doc//spawnlib:status/text(), text{"killed"}),
				xdmp:set-server-field("spawnlib:progress-" || fn:string($job-id), ()),
				xdmp:set-server-field("spawnlib:error-" || fn:string($job-id), ()),
				xdmp:set-server-field("spawnlib:throttle-" || fn:string($job-id), ())
			)
	else
		let $jobdocuri := "/spawnlib-jobs/" || $job-id || "/" || $host-id || ".xml"
		let $progress-doc := fn:doc($jobdocuri)
		return
			if ($progress-doc//*:status eq "running" or $progress-doc//*:status eq "initializing") then
				let $_ := xdmp:lock-for-update($jobdocuri)
				return
				(
					xdmp:set-server-field("spawnlib:kill-" || fn:string($job-id), fn:true()),
					xdmp:node-replace($progress-doc//spawnlib:status/text(), text{"killed"}),
					xdmp:set-server-field("spawnlib:progress-" || fn:string($job-id), ()),
					xdmp:set-server-field("spawnlib:error-" || fn:string($job-id), ()),
					xdmp:set-server-field("spawnlib:throttle-" || fn:string($job-id), ())
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
		let $jobdocuri := "/spawnlib-jobs/" || $job-id || "/" || $host-id || ".xml"
		let $progress-doc := fn:doc($jobdocuri)
		return
			if ($progress-doc//*:status eq "running") then
				let $_ := xdmp:lock-for-update($jobdocuri)
				return
				(
					xdmp:set-server-field("spawnlib:throttle-" || fn:string($job-id), $throttle),
					xdmp:node-replace($progress-doc//*:throttle/text(), text{$throttle})
				)
			else ()
';

declare variable $GET-SPAWNLIB-SERVER-FIELDS := '
	xquery version "1.0-ml";
	let $names := xdmp:get-server-field-names()
	let $spawnlib-field-names := $names ! (if (fn:starts-with(., "spawnlib")) then . else ())
	let $m := map:map()
	let $_ :=
		for $n in $spawnlib-field-names
		let $f := xdmp:get-server-field($n)
		let $v := if (fn:contains($n, "progress") or fn:contains($n, "error")) then map:count($f) else xdmp:quote($f)
		return map:put($m, $n, $v)
	return <x>{$m}</x>/node()
';

declare variable $CLEAR-SPAWNLIB-SERVER-FIELDS := '
	xquery version "1.0-ml";
	let $names := xdmp:get-server-field-names()
	let $spawnlib-field-names := $names ! (if (fn:starts-with(., "spawnlib")) then . else ())
	for $field in $spawnlib-field-names
	return xdmp:set-server-field($field, ())
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
	spawnlib:eval($q, $varsmap, $options, "xquery")
};

declare function spawnlib:eval($q as xs:string, $varsmap as map:map?, $options as node()?, $language as xs:string) {
	if ($language = "xquery") then
		xdmp:eval(
			$q,
			(for $key in map:keys($varsmap) return (xs:QName($key), map:get($varsmap, $key))),
			functx:remove-elements-deep($options, ("inforest", "appserver", "database", "priority", "result", "authentication", "throttle", "inforest", "language"))
		)
	else
		xdmp:apply(
			xdmp:function(xs:QName("xdmp:javascript-eval")),
			$q,
			$varsmap,
			functx:remove-elements-deep($options, ("inforest", "appserver", "database", "priority", "result", "authentication", "throttle", "inforest", "language"))
		)
};

declare function spawnlib:inforest-eval($q as xs:string, $varsmap as map:map?, $options as node()?) {
	spawnlib:inforest-eval($q, $varsmap, $options, "xquery")
};

declare function spawnlib:inforest-eval($q as xs:string, $varsmap as map:map?, $options as node()?, $language as xs:string) {
	if ($language = "xquery") then
		xdmp:eval(
			$q,
			(for $key in map:keys($varsmap) return (xs:QName($key), map:get($varsmap, $key))),
			<options xmlns="xdmp:eval">
				{functx:remove-elements-deep($options, ("inforest", "appserver", "database", "priority", "result", "authentication", "throttle", "inforest", "language"))/node()}
				<database>{spawnlib:forest-ids-to-string($local-forests)}</database>
			</options>
		)
	else
		xdmp:apply(
			xdmp:function(xs:QName("xdmp:javascript-eval")),
			$q,
			$varsmap,
			<options xmlns="xdmp:eval">
				{functx:remove-elements-deep($options, ("inforest", "appserver", "database", "priority", "result", "authentication", "throttle", "inforest", "language"))/node()}
				<database>{spawnlib:forest-ids-to-string($local-forests)}</database>
			</options>
		)
};

declare function spawnlib:inforest-eval-query($q as xs:string, $varsmap as map:map?, $options as node()?) {
	spawnlib:inforest-eval-query($q, $varsmap, $options, "xquery")
};

declare function spawnlib:inforest-eval-query($q as xs:string, $varsmap as map:map?, $options as node()?, $language as xs:string) {
	if ($language = "xquery") then
		xdmp:eval(
			$q,
			(for $key in map:keys($varsmap) return (xs:QName($key), map:get($varsmap, $key))),
			<options xmlns="xdmp:eval">
				{functx:remove-elements-deep($options, ("inforest", "appserver", "database", "priority", "result", "authentication", "throttle", "inforest", "language"))/node()}
				<database>{spawnlib:forest-ids-to-string($local-forests)}</database>
				<transaction-mode>query</transaction-mode>
			</options>
		)
	else
		xdmp:apply(
			xdmp:function(xs:QName("xdmp:javascript-eval")),
			$q,
			$varsmap,
			<options xmlns="xdmp:eval">
				{functx:remove-elements-deep($options, ("inforest", "appserver", "database", "priority", "result", "authentication", "throttle", "inforest", "language"))/node()}
				<database>{spawnlib:forest-ids-to-string($local-forests)}</database>
				<transaction-mode>query</transaction-mode>
			</options>
		)
};

declare function spawnlib:spawn-local-task($q as xs:string, $varsmap as map:map, $options as node()?) {
	let $options := if (fn:exists($options)) then $options else <options xmlns="xdmp:eval"/>
	return
		xdmp:spawn(
			"/spawn/runner.xqy",
			(xs:QName("q"), $q, xs:QName("varsmap"), $varsmap, xs:QName("options"), $options),
			functx:remove-elements-deep($options, ("inforest", "appserver", "authentication", "throttle", "inforest", "language"))
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
		let $url := 'http://' || $host-name || ':' || fn:string($port) || '/spawn/spawn-receiver.xqy'
		let $result := xdmp:http-post($url, $http-options)
		return
			if ($result[1]//*:code/fn:string() eq "200") then
				let $res := $result[2]
				let $res := if (fn:string-length($res) = 0) then () else $res
				return map:put($result-map, fn:string($host-id), $res)
			else
				(
					xdmp:log(xdmp:quote($result[2])),
					fn:error(xs:QName("SPAWNLIB-HTTP"), "Error farming job to cluster")
				)
	return $result-map
};

declare function spawnlib:corb($uri-query as xs:string, $transform-query as xs:string) {
	spawnlib:corb($uri-query, $transform-query, (), ())
};

declare function spawnlib:corb($uri-query as xs:string, $transform-query as xs:string, $options as node()?) {
	spawnlib:corb($uri-query, $transform-query, (), $options)
};

declare function spawnlib:corb($uri-query as xs:string, $transform-query as xs:string, $name as xs:string?, $options as node()?) {
	let $job-id := xdmp:hash64(fn:string(fn:current-dateTime()))
	let $options := spawnlib:merge-options($options)
	let $name := ($name, "")[1]
	let $result-map :=
		spawnlib:farm(
			$CORB-SCRIPT,
			(xs:QName('uri-query'), $uri-query, xs:QName('transform-query'), $transform-query, xs:QName('job-id'), $job-id, xs:QName('task-number'), 0, xs:QName('name'), $name, xs:QName('options'), $options),
			<options xmlns="xdmp:eval">
			{
				functx:remove-elements-deep($options, ("inforest", "result"))/node(),
				<priority>higher</priority>
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
	spawnlib:check-progress((), "normal")
};

declare function spawnlib:check-progress($job-id as xs:unsignedLong?, $detail as xs:string) {
	spawnlib:check-progress($job-id, $detail, (), ())
};

declare function spawnlib:check-progress($job-id as xs:unsignedLong?, $detail as xs:string, $start as xs:int?, $end as xs:int?) {
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
	let $job-name-map := cts:element-value-co-occurrences(xs:QName("spawnlib:job-id"), xs:QName("spawnlib:name"), ("map", "collation-2=http://marklogic.com/collation/codepoint", "concurrent"), $q)
	let $job-status-map := cts:element-value-co-occurrences(xs:QName("spawnlib:job-id"), xs:QName("spawnlib:status"), ("map", "collation-2=http://marklogic.com/collation/codepoint", "concurrent"), $q)
	let $job-created-map := cts:element-value-co-occurrences(xs:QName("spawnlib:job-id"), xs:QName("spawnlib:created"), ("map", "concurrent"), $q)
	let $job-completed-map := cts:element-value-co-occurrences(xs:QName("spawnlib:job-id"), xs:QName("spawnlib:completed"), ("map", "concurrent"), $q)
	let $job-inforest-map := cts:element-value-co-occurrences(xs:QName("spawnlib:job-id"), xs:QName("spawnlib:inforest"), ("map", "concurrent", "collation-2=http://marklogic.com/collation/codepoint"), $q)
	let $job-language-map := cts:element-value-co-occurrences(xs:QName("spawnlib:job-id"), xs:QName("spawnlib:language"), ("map", "collation-2=http://marklogic.com/collation/codepoint", "concurrent"), $q)
	let $job-throttle-map := cts:element-value-co-occurrences(xs:QName("spawnlib:job-id"), xs:QName("spawnlib:throttle"), ("map", "concurrent"), $q)

	let $active-job-q := cts:element-range-query(xs:QName("spawnlib:status"), "=", ("initializing", "running"))
	let $active-jobs := cts:element-values(xs:QName("spawnlib:job-id"), (), (), $active-job-q)
	let $inactive-job-q :=
		cts:and-not-query(
			cts:element-range-query(xs:QName("spawnlib:status"), "=", ("error", "killed", "complete", "server shutdown")),
			cts:element-range-query(xs:QName("spawnlib:job-id"), "=", $active-jobs)
		)
	let $sort-sequence := cts:element-value-co-occurrences(xs:QName("spawnlib:created"), xs:QName("spawnlib:job-id"), ("concurrent", "item-order", "descending"), $inactive-job-q)

	let $start :=
		if (fn:exists($start)) then
			$start
		else
			1

	let $end :=
		if (fn:exists($end)) then
			$end
		else
			fn:count($sort-sequence)

	let $total-inactive-jobs := ()

	let $jobs-to-return :=
		if ($job-id) then
			$job-id
		else
			(
			for $job-id in $active-jobs
			let $created := fn:min(map:get($job-created-map, fn:string($job-id)))
			order by $created ascending
			return $job-id
			,
				fn:distinct-values($sort-sequence ! (xs:unsignedLong(./cts:value[2]/fn:string())))[$start to $end],
				xdmp:set($total-inactive-jobs, fn:count(cts:element-values(xs:QName("spawnlib:job-id"), (), (), $inactive-job-q)))
			)

	let $job-objects :=
		for $job-id in $jobs-to-return
		let $statuses := map:get($job-status-map, fn:string($job-id))
		let $overall-status :=
			if ($statuses = "error") then "error"
			else if ($statuses = "initializing") then "initializing"
			else if ($statuses = "running") then "running"
			else if ($statuses = "killed") then "killed"
			else if ($statuses = "server shutdown") then "server shutdown"
			else "complete"
		let $name := map:get($job-name-map, fn:string($job-id))
		let $total-progress := (fn:sum(for $host-id in map:keys($progress-map) return xs:unsignedLong(map:get(map:get(map:get($progress-map, $host-id), fn:string($job-id)), "count"))), 0)[1]
		let $total-tasks := cts:sum-aggregate(cts:element-reference(xs:QName("spawnlib:total")), "concurrent", cts:element-range-query(xs:QName("spawnlib:job-id"), "=", $job-id))
		let $created-date := fn:min(map:get($job-created-map, fn:string($job-id)))
		let $completed-dateTimes := map:get($job-completed-map, fn:string($job-id))
		let $inforest := (map:get($job-inforest-map, fn:string($job-id))[1], fn:false())[1]
		let $language := (map:get($job-language-map, fn:string($job-id))[1], "xquery")[1]
		let $throttle := (map:get($job-throttle-map, fn:string($job-id))[1], 10)[1]
		order by $created-date descending
		return
			<json type="object" xmlns="http://marklogic.com/xdmp/json/basic">
				<id type="string">{$job-id}</id>
				<name type="string">{$name}</name>
				<language type="string">{$language}</language>
				<status type="string">{$overall-status}</status>
				{
					if ($overall-status ne "initializing") then
						<progress type="number">{$total-tasks - $total-progress}</progress>
					else ()
				}
				<throttle type="number">{$throttle}</throttle>
				{
					if ($overall-status ne "initializing") then
						<total type="number">{$total-tasks}</total>
					else ()
				}
				<created type="string">{$created-date}</created>
				{
					if (fn:count($completed-dateTimes) eq map:count($progress-map)) then
						<completed type="string">{fn:max($completed-dateTimes)}</completed>
					else
						()
				}
				<inforest type="boolean">{$inforest}</inforest>
				{
					if ($detail = "full") then
						(
							<uriquery type="string">{xdmp:directory("/spawnlib-jobs/" || $job-id || "/")[1]//spawnlib:uri-query/fn:string()}</uriquery>,
							<transformquery type="string">{xdmp:directory("/spawnlib-jobs/" || $job-id || "/")[1]//spawnlib:transform-query/fn:string()}</transformquery>
						)
					else ()
				}
				{
					if ($detail = "full") then
						<hoststatus type="object">
						{
							let $job-query := cts:element-range-query(xs:QName("spawnlib:job-id"), "=", $job-id)
							let $host-status-map := cts:element-value-co-occurrences(xs:QName("spawnlib:host-id"), xs:QName("spawnlib:status"), ("map", "collation-2=http://marklogic.com/collation/codepoint"), $job-query)
							let $host-total-map := cts:element-value-co-occurrences(xs:QName("spawnlib:host-id"), xs:QName("spawnlib:total"), ("map"), $job-query)
							let $host-created-map := cts:element-value-co-occurrences(xs:QName("spawnlib:host-id"), xs:QName("spawnlib:created"), ("map"), $job-query)
							let $host-completed-map := cts:element-value-co-occurrences(xs:QName("spawnlib:host-id"), xs:QName("spawnlib:completed"), ("map"), $job-query)
							for $host-id in xdmp:hosts()
							let $host-id := fn:string($host-id)
							let $hostname := xdmp:host-name(xs:unsignedLong($host-id))
							let $progress := (map:get($host-total-map, $host-id) - map:get(map:get(map:get($progress-map, $host-id), fn:string($job-id)), "count"), 0)[1]
							let $uri-error := xdmp:quote(fn:doc("/spawnlib-jobs/" || $job-id || "/" || $host-id || ".xml")//spawnlib:uri-error/node())
							let $transform-errors := (map:get(map:get(map:get($progress-map, $host-id), fn:string($job-id)), "errors"), map:map())[1]
							let $transform-error-node := fn:doc("/spawnlib-jobs/" || $job-id || "/" || $host-id || ".xml")//spawnlib:transform-errors/map:map
							let $transform-errors :=
								if (fn:exists($transform-error-node)) then
									map:map($transform-error-node) + $transform-errors
								else
									$transform-errors
							let $total := (map:get($host-total-map, $host-id), 0)[1]
							return
								element {fn:QName("http://marklogic.com/xdmp/json/basic", $hostname)} {
									attribute type {"object"},
									<status type="string">{map:get($host-status-map, $host-id)}</status>,
									<progress type="number">{$progress}</progress>,
									<total type="number">{$total}</total>,
									<created type="string">{map:get($host-created-map, $host-id)}</created>,
									if (fn:exists(map:get($host-completed-map, $host-id))) then
										<completed type="string">{map:get($host-completed-map, $host-id)}</completed>
									else
										()
									,
									if (fn:exists($transform-errors)) then
										<transformerrors type="array">
										{
											for $uri in map:keys($transform-errors)
											return
												<transformerror type="object">
													<uri type="string">{$uri}</uri>
													<error type="string">{map:get($transform-errors, $uri)}</error>
												</transformerror>
										}
										</transformerrors>	
									else
										()
									,
									if (fn:exists($uri-error) and $uri-error ne "") then
										<urierror type="string">{$uri-error}</urierror>
									else
										()
								}
						}
						</hoststatus>
					else ()
				}
			</json>
	return
		<json type="object" xmlns="http://marklogic.com/xdmp/json/basic">
			<success type="boolean">true</success>
			<results type="array">{$job-objects}</results>
			{
				if (fn:exists($total-inactive-jobs)) then
					<totalInactiveJobs type="number">{$total-inactive-jobs}</totalInactiveJobs>
				else
					()
			}
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
	spawnlib:remove(())
};

declare function spawnlib:remove($job-id as xs:unsignedLong?) {
	let $inactive-job-q := cts:element-range-query(xs:QName("spawnlib:status"), "=", ("error", "killed", "complete"), ("collation=http://marklogic.com/collation/codepoint"))
	let $job-q :=
		cts:and-query((
			if ($job-id) then cts:element-range-query(xs:QName("spawnlib:job-id"), "=", $job-id, ("collation=http://marklogic.com/collation/codepoint")) else (),
			$inactive-job-q
		))
	let $uris-to-delete := cts:uris((), (), $job-q)
	let $remove :=
		for $uri in $uris-to-delete
		return xdmp:document-delete($uri)
	return
		<json type="object" xmlns="http://marklogic.com/xdmp/json/basic">
			<success type="boolean">true</success>
		</json>
};

declare function spawnlib:get-server-fields() {
	let $sf-map :=
		spawnlib:farm(
			$GET-SPAWNLIB-SERVER-FIELDS,
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
		<json type="object" xmlns="http://marklogic.com/xdmp/json/basic">
			<success type="boolean">true</success>
			<results type="array">
			{
				for $host-id in map:keys($result-map)
				let $sf-map := map:get($result-map, $host-id)
				return
					<json type="object">
						<host-id type="string">{$host-id}</host-id>
						<host-name type="string">{xdmp:host-name(xs:unsignedLong($host-id))}</host-name>
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
};

declare function spawnlib:clear-server-fields() {
	let $result-map :=
		spawnlib:farm(
			$CLEAR-SPAWNLIB-SERVER-FIELDS,
			(),
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