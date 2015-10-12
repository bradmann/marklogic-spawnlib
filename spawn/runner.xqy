xquery version "1.0-ml";
import module namespace spawnlib = "http://marklogic.com/spawnlib" at "/spawn/lib/spawnlib.xqy";

declare variable $q external;
declare variable $varsmap external;
declare variable $options external;

let $job-id := map:get($varsmap, "job-id")
let $kill := xs:boolean(xdmp:get-server-field("spawnlib:kill", fn:false())) or xs:boolean(xdmp:get-server-field("spawnlib:kill-" || $job-id, fn:false()))
let $priority := ($options//*:priority/fn:string(), "normal")[1]
let $inforest := xs:boolean(($options//*:inforest/fn:string(), "false")[1])
let $throttle := xdmp:get-server-field("spawnlib:throttle-" || $job-id)
let $language := if ($priority = "higher") then "xquery" else ($options//*:language/fn:string(), "xquery")[1]
let $_ := if ($throttle lt 10 and fn:not($kill)) then xdmp:sleep(xs:int((xs:double(1) div $throttle) * 1000)) else ()
return
	if ($kill and ($priority = "normal")) then
		()
	else
		(
			try {
				if ($inforest) then
					spawnlib:inforest-eval($q, $varsmap, $options, $language)
				else
					spawnlib:eval($q, $varsmap, $options, $language)
			} catch ($e) {
				map:put($varsmap, "error", $e)
			},
			if ($job-id eq 0 or $priority eq "higher") then () else spawnlib:inforest-eval($spawnlib:SINGLE-TASK-COMPLETE, $varsmap, ())
		)